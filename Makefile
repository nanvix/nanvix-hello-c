# Copyright(c) The Maintainers of Nanvix.
# Licensed under the MIT License.

#===============================================================================
# Build Configuration
#===============================================================================

# Nanvix GitHub repository.
NANVIX_REPO ?= nanvix/nanvix

# Nanvix release tag to fetch (pinned).
NANVIX_RELEASE ?= v0.15.26

# Nanvix toolchain Docker image.
# See: https://github.com/nanvix/toolchain-gcc/releases/tag/v2026.05.09-d3ba1c6
NANVIX_TOOLCHAIN_IMAGE ?= ghcr.io/nanvix/toolchain-gcc:sha-d3ba1c6

# Nanvix release directory (populated by 'make init').
NANVIX_DIR ?= .nanvix

# Nanvix MicroVM memory size (e.g. 128mb, 256mb).
NANVIX_MEMORY_SIZE ?= 128mb

# Nanvix deployment mode (multi-process or standalone).
# - multi-process: guest applications run inside the Nanvix MicroVM;
#                  system daemons run on the hosting platform, as part of the trusted computing base.
# - standalone:    guest applications and system daemons all run inside the Nanvix MicroVM.
NANVIX_DEPLOYMENT_MODE ?= multi-process

# Toolchain directory (set by the Docker image).
NANVIX_TOOLCHAIN_DIR ?= /opt/nanvix

#===============================================================================
# Constants
#===============================================================================

# Nanvix target machine (used to select the release asset).
NANVIX_MACHINE := microvm

# Build output directory.
BUILD_DIR := build

#===============================================================================
# Toolchain Configuration
#===============================================================================

# Cross-compiler and tools.
CC := $(NANVIX_TOOLCHAIN_DIR)/bin/i686-nanvix-gcc

# Compiler flags.
CFLAGS := -std=c17
CFLAGS += -m32 -march=pentiumpro -Wa,-march=pentiumpro
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -O2

# Nanvix POSIX library (sentinel for a populated $(NANVIX_DIR)).
LIBPOSIX_A := $(NANVIX_DIR)/lib/libposix.a

# C standard library (provided by the toolchain).
LIBC_A := $(NANVIX_TOOLCHAIN_DIR)/i686-nanvix/lib/libc.a

# Linker flags.
LDFLAGS := -z noexecstack -T $(NANVIX_DIR)/lib/user.ld

# Libraries (order matters — use grouping to resolve circular dependencies).
LIBRARIES := -Wl,--start-group $(LIBPOSIX_A) $(LIBC_A) -Wl,--end-group

#===============================================================================
# Build Artifacts
#===============================================================================

# Source and object files.
SOURCES := main.c
OBJECTS := $(SOURCES:%.c=$(BUILD_DIR)/%.o)

# Output binary.
BINARY := hello-c.elf

# Standalone initrd image (built only when NANVIX_DEPLOYMENT_MODE=standalone).
INITRD := $(BUILD_DIR)/hello-c.img

# Tool used to assemble the standalone initrd image.
MKIMAGE := $(NANVIX_DIR)/bin/mkimage.elf

# System daemons bundled into the standalone initrd image.
NANVIX_DAEMONS := \
	$(NANVIX_DIR)/bin/procd.elf \
	$(NANVIX_DIR)/bin/memd.elf \
	$(NANVIX_DIR)/bin/vfsd.elf

# Payload passed to nanvixd. In multi-process mode this is the app ELF; in
# standalone mode it is an initrd image bundling the app and system daemons.
ifeq ($(NANVIX_DEPLOYMENT_MODE),standalone)
NANVIX_PAYLOAD := $(INITRD)
else
NANVIX_PAYLOAD := $(BUILD_DIR)/$(BINARY)
endif

#===============================================================================
# Host vs. Container split
#===============================================================================

# The same Makefile is used on the host (which drives 'docker run') and inside
# the Nanvix toolchain container (which performs the actual cross-compilation).
# The host sets IN_NANVIX_CONTAINER=1 in the container's environment to select
# the container-side recipes below.
INSIDE_CONTAINER := $(IN_NANVIX_CONTAINER)

#===============================================================================
# Host Targets
#===============================================================================

all: $(BUILD_DIR)/$(BINARY)

ifeq ($(INSIDE_CONTAINER),)
# Build hello-c.elf inside the Nanvix toolchain Docker image, bind-mounting the
# workspace so artifacts land directly in $(BUILD_DIR)/.
$(BUILD_DIR)/$(BINARY): $(SOURCES) Makefile $(LIBPOSIX_A) | $(BUILD_DIR)
	docker run --rm \
		-u $$(id -u):$$(id -g) \
		-e IN_NANVIX_CONTAINER=1 \
		-v $(CURDIR):/workspace \
		-w /workspace \
		$(NANVIX_TOOLCHAIN_IMAGE) \
		make compile
endif

# Run on Nanvix.
run: all $(NANVIX_PAYLOAD)
	$(NANVIX_DIR)/bin/nanvixd.elf -bin-dir $(NANVIX_DIR)/bin -console-file /dev/stdout -- $(NANVIX_PAYLOAD)

# Assemble the standalone initrd: bundle the app together with the system
# daemons (procd, memd, vfsd) so they all run inside the Nanvix MicroVM. Each
# entry has the form '<host-path>;<argv0>'. mkimage.elf is a host-side binary
# shipped in the sysroot's bin/ despite its .elf suffix; it and the daemon
# ELFs are populated by 'make init' alongside libposix.a, so they are listed
# as explicit prerequisites to force a rebuild when the release contents
# change (e.g. after switching modes or re-running 'make init').
$(INITRD): $(BUILD_DIR)/$(BINARY) $(MKIMAGE) $(NANVIX_DAEMONS) | $(BUILD_DIR)
	$(MKIMAGE) -o $@ \
		'$(NANVIX_DIR)/bin/procd.elf;procd' \
		'$(NANVIX_DIR)/bin/memd.elf;memd' \
		'$(NANVIX_DIR)/bin/vfsd.elf;vfsd' \
		'$(abspath $(BUILD_DIR)/$(BINARY));$(basename $(BINARY))'

clean:
	rm -rf $(BUILD_DIR)

#===============================================================================
# Container Targets (used inside Docker)
#===============================================================================

compile: $(BUILD_DIR)/$(BINARY)

ifneq ($(INSIDE_CONTAINER),)
$(BUILD_DIR)/$(BINARY): $(OBJECTS) | $(BUILD_DIR)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LIBRARIES) -o $@
endif

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	@mkdir -p $@

#===============================================================================
# Init — download the Nanvix release
#===============================================================================

init: $(LIBPOSIX_A)

# mkimage and the system daemons are extracted together with libposix.a by
# get-nanvix.py, so use libposix.a as the sentinel that triggers 'make init'.
$(MKIMAGE) $(NANVIX_DAEMONS): $(LIBPOSIX_A)

$(LIBPOSIX_A):
	./get-nanvix.py \
		--repo "$(NANVIX_REPO)" \
		--release "$(NANVIX_RELEASE)" \
		--machine "$(NANVIX_MACHINE)" \
		--deployment-mode "$(NANVIX_DEPLOYMENT_MODE)" \
		--memory-size "$(NANVIX_MEMORY_SIZE)" \
		--output-dir "$(NANVIX_DIR)"

distclean: clean
	rm -rf $(NANVIX_DIR)

.PHONY: all run compile clean init distclean
