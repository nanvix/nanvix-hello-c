# Copyright(c) The Maintainers of Nanvix.
# Licensed under the MIT License.

#===============================================================================
# Build Configuration
#===============================================================================

# Nanvix GitHub repository.
NANVIX_REPO ?= nanvix/nanvix

# Nanvix release tag embedded in the SDK (pinned).
NANVIX_RELEASE ?= v0.20.0

# Nanvix SDK Docker image (pinned by digest).
NANVIX_SDK_IMAGE_REPO ?= ghcr.io/nanvix/nanvix-sdk-c-clang
NANVIX_SDK_IMAGE_HASH ?= 880ed7e6a20fe9bf2536b1b3ba9bdbbd067a48f043ec9131d3dd398c65f11f35
NANVIX_SDK_IMAGE ?= $(NANVIX_SDK_IMAGE_REPO)@sha256:$(NANVIX_SDK_IMAGE_HASH)

# Nanvix release directory (populated by 'make init').
NANVIX_DIR ?= .nanvix

# Nanvix MicroVM memory size.
NANVIX_MEMORY_SIZE ?= 256mb

# Nanvix deployment mode (single-process or standalone).
# - single-process: guest applications run inside the Nanvix MicroVM;
#                   system daemons run on the hosting platform.
# - standalone:     guest applications and system daemons run inside the Nanvix MicroVM.
NANVIX_DEPLOYMENT_MODE ?= standalone

# SDK directory (set by the Docker image).
NANVIX_SDK_DIR ?= /opt/nanvix

#===============================================================================
# Constants
#===============================================================================

# Nanvix target machine (used to select the release asset).
NANVIX_MACHINE := microvm

# Build output directory.
BUILD_DIR := build

#===============================================================================
# Host OS Detection
#===============================================================================

# Host OS that drives 'docker run' and (in standalone mode) launches nanvixd.
# Auto-detected: Windows when MAKE sees OS=Windows_NT (set by Windows itself and
# inherited by Git Bash / MSYS2 shells); Linux otherwise. Override with
# NANVIX_HOST_OS=linux|windows if needed.
ifeq ($(OS),Windows_NT)
NANVIX_HOST_OS ?= windows
else
NANVIX_HOST_OS ?= linux
endif

ifeq ($(NANVIX_HOST_OS),windows)
# Only the standalone deployment mode is published for Windows: multi-process
# needs linuxd, which is Linux-only.
ifneq ($(NANVIX_DEPLOYMENT_MODE),standalone)
$(error On Windows hosts only NANVIX_DEPLOYMENT_MODE=standalone is supported \
  (got '$(NANVIX_DEPLOYMENT_MODE)'). Re-run with NANVIX_DEPLOYMENT_MODE=standalone.)
endif
# Host-side binaries shipped in the Windows release zip.
HOST_EXE := .exe
# Docker Desktop on Windows ignores Unix user mapping; converting the MSYS-style
# CURDIR (/c/Users/...) to a mixed Windows path (C:/Users/...) is required so
# Docker Desktop can resolve the bind mount.
DOCKER_USER_FLAG :=
DOCKER_WORKSPACE := $(shell cygpath -m '$(CURDIR)' 2>/dev/null || echo '$(CURDIR)')
# Windows console device — nanvixd.exe writes guest console output here.
NANVIX_CONSOLE := CON
# Translate an MSYS-style path (/c/Users/...) to a mixed Windows path
# (C:/Users/...) that native .exe tools (mkimage.exe, nanvixd.exe) understand.
native_path = $(shell cygpath -m '$(1)' 2>/dev/null || echo '$(1)')
else
HOST_EXE := .elf
DOCKER_USER_FLAG := -u $$(id -u):$$(id -g)
DOCKER_WORKSPACE := $(CURDIR)
NANVIX_CONSOLE := /dev/stdout
native_path = $(1)
endif

#===============================================================================
# SDK Configuration
#===============================================================================

# Cross-compiler.
CC := $(NANVIX_SDK_DIR)/bin/clang

# Compiler flags.
CFLAGS := -std=c17
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -O2

# Linker flags.
LDFLAGS := -Wl,-z,noexecstack

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

# Tool used to assemble the standalone initrd image. Suffix depends on the host
# OS: mkimage.elf on Linux, mkimage.exe on Windows (both are host-side binaries
# despite the .elf suffix on Linux).
MKIMAGE := $(NANVIX_DIR)/bin/mkimage$(HOST_EXE)

# Nanvix daemon (host-side launcher).
NANVIXD := $(NANVIX_DIR)/bin/nanvixd$(HOST_EXE)

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
# the Nanvix SDK container (which performs the actual cross-compilation).
# The host sets IN_NANVIX_CONTAINER=1 in the container's environment to select
# the container-side recipes below.
INSIDE_CONTAINER := $(IN_NANVIX_CONTAINER)

#===============================================================================
# Host Targets
#===============================================================================

all: $(BUILD_DIR)/$(BINARY)

ifeq ($(INSIDE_CONTAINER),)
# Build hello-c.elf inside the Nanvix SDK Docker image, bind-mounting the
# workspace so artifacts land directly in $(BUILD_DIR)/.
$(BUILD_DIR)/$(BINARY): $(SOURCES) Makefile | $(BUILD_DIR)
	docker run --rm \
		$(DOCKER_USER_FLAG) \
		-e IN_NANVIX_CONTAINER=1 \
		-v "$(DOCKER_WORKSPACE)":/workspace \
		-w /workspace \
		$(NANVIX_SDK_IMAGE) \
		make compile
endif

# Run on Nanvix.
run: all $(NANVIX_PAYLOAD)
	$(NANVIXD) -bin-dir $(NANVIX_DIR)/bin -console-file $(NANVIX_CONSOLE) -- $(NANVIX_PAYLOAD)

# Run on Nanvix without rebuilding (used by CI Windows job which downloads the
# pre-built standalone image artifact from the Linux build job). Depend on
# $(NANVIXD) so a fresh checkout that hasn't run 'make init' yet still triggers
# the downloader via the stamp rule below, instead of erroring out with a
# confusing "file not found" on the host launcher.
run-only: $(NANVIXD)
	$(NANVIXD) -bin-dir $(NANVIX_DIR)/bin -console-file $(NANVIX_CONSOLE) -- $(NANVIX_PAYLOAD)

# Assemble the standalone initrd: bundle the app together with the system
# daemons (procd, memd, vfsd) so they all run inside the Nanvix MicroVM. Each
# entry has the form '<host-path>;<argv0>'. mkimage.elf is a host-side binary
# shipped in the sysroot's bin/ despite its .elf suffix; it and the daemon
# ELFs are populated by 'make init', so they are listed
# as explicit prerequisites to force a rebuild when the release contents
# change (e.g. after switching modes or re-running 'make init').
$(INITRD): $(BUILD_DIR)/$(BINARY) $(MKIMAGE) $(NANVIX_DAEMONS) | $(BUILD_DIR)
	$(MKIMAGE) -o $@ \
		'$(NANVIX_DIR)/bin/procd.elf;procd' \
		'$(NANVIX_DIR)/bin/memd.elf;memd' \
		'$(NANVIX_DIR)/bin/vfsd.elf;vfsd' \
		'$(call native_path,$(abspath $(BUILD_DIR)/$(BINARY)));$(basename $(BINARY))'

clean:
	rm -rf $(BUILD_DIR)

#===============================================================================
# Container Targets (used inside Docker)
#===============================================================================

compile: $(BUILD_DIR)/$(BINARY)

ifneq ($(INSIDE_CONTAINER),)
$(BUILD_DIR)/$(BINARY): $(OBJECTS) | $(BUILD_DIR)
	$(CC) $(LDFLAGS) $(OBJECTS) -o $@
endif

$(BUILD_DIR)/%.o: %.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD_DIR):
	@mkdir -p $@

#===============================================================================
# Init — download the Nanvix release
#===============================================================================

# Stamp file written once 'make init' completes. The full configuration that
# selects the release asset is encoded in the filename so that changing any of
# NANVIX_HOST_OS, NANVIX_RELEASE, NANVIX_MACHINE, NANVIX_DEPLOYMENT_MODE or
# NANVIX_MEMORY_SIZE picks a different stamp and forces the downloader to
# re-run, instead of silently reusing an out-of-sync .nanvix/ layout.
#
# Using a stamp keeps this rule portable to GNU make versions older than
# 4.3, which do not support grouped targets ('&:').
NANVIX_STAMP := $(NANVIX_DIR)/.init-stamp-$(NANVIX_HOST_OS)-$(NANVIX_RELEASE)-$(NANVIX_MACHINE)-$(NANVIX_DEPLOYMENT_MODE)-$(NANVIX_MEMORY_SIZE)

init: $(NANVIX_STAMP)

# Runtime binaries are populated by get-nanvix.py as side effects of the stamp
# recipe. If the stamp exists but one is missing, rerun the downloader.
$(NANVIXD) $(MKIMAGE) $(NANVIX_DAEMONS): $(NANVIX_STAMP)
	@if [ ! -e "$@" ]; then \
		echo "Stamp $(NANVIX_STAMP) exists but $@ is missing; re-running 'make init'."; \
		rm -f "$(NANVIX_STAMP)"; \
		$(MAKE) --no-print-directory "$(NANVIX_STAMP)"; \
	fi
	@if [ ! -e "$@" ]; then \
		echo "ERROR: '$@' is still missing after running 'make init'." >&2; \
		echo "       The downloaded release may not contain this artifact" >&2; \
		echo "       for the requested configuration (host-os=$(NANVIX_HOST_OS)," >&2; \
		echo "       release=$(NANVIX_RELEASE), machine=$(NANVIX_MACHINE)," >&2; \
		echo "       deployment-mode=$(NANVIX_DEPLOYMENT_MODE)," >&2; \
		echo "       memory-size=$(NANVIX_MEMORY_SIZE))." >&2; \
		exit 1; \
	fi
	@touch "$@"

$(NANVIX_STAMP):
	./get-nanvix.py \
		--repo "$(NANVIX_REPO)" \
		--release "$(NANVIX_RELEASE)" \
		--machine "$(NANVIX_MACHINE)" \
		--deployment-mode "$(NANVIX_DEPLOYMENT_MODE)" \
		--memory-size "$(NANVIX_MEMORY_SIZE)" \
		--host-os "$(NANVIX_HOST_OS)" \
		--output-dir "$(NANVIX_DIR)"
	@touch $@

distclean: clean
	rm -rf $(NANVIX_DIR)

.PHONY: all run run-only compile clean init distclean
