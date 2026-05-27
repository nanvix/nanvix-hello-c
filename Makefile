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

# Nanvix target machine (used to select the release asset).
MACHINE := microvm

# Toolchain directory (set by the Docker image).
TOOLCHAIN_DIR ?= /opt/nanvix

# Cross-compiler and tools.
CC := $(TOOLCHAIN_DIR)/bin/i686-nanvix-gcc

# Compiler flags.
CFLAGS := -std=c17
CFLAGS += -m32 -march=pentiumpro -Wa,-march=pentiumpro
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -O2

# Nanvix POSIX library (sentinel for a populated $(NANVIX_DIR)).
LIBPOSIX_A := $(NANVIX_DIR)/lib/libposix.a

# C standard library (provided by the toolchain).
LIBC_A := $(TOOLCHAIN_DIR)/i686-nanvix/lib/libc.a

# Linker flags.
LDFLAGS := -z noexecstack -T $(NANVIX_DIR)/lib/user.ld

# Libraries (order matters — use grouping to resolve circular dependencies).
LIBRARIES := -Wl,--start-group $(LIBPOSIX_A) $(LIBC_A) -Wl,--end-group

# Build output directory.
BUILD_DIR := build

# Source and object files.
SOURCES := main.c
OBJECTS := $(SOURCES:%.c=$(BUILD_DIR)/%.o)

# Output binary.
BINARY := hello-c.elf

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
		$$(cat $(NANVIX_DIR)/.docker-image) \
		make compile
endif

# Run on Nanvix.
run: all
	$(NANVIX_DIR)/bin/nanvixd.elf -bin-dir $(NANVIX_DIR)/bin -console-file /dev/stdout -- $(BUILD_DIR)/$(BINARY)

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
# Init — download the latest Nanvix release and resolve the Docker image tag
#===============================================================================

init: $(LIBPOSIX_A)

$(LIBPOSIX_A):
	@echo "Downloading Nanvix release $(NANVIX_RELEASE)..."
	@set -e; \
	RELEASE_INFO=$$(gh release view "$(NANVIX_RELEASE)" --repo "$(NANVIX_REPO)" --json tagName,assets); \
	TAG_NAME=$$(echo "$$RELEASE_INFO" | jq -r '.tagName'); \
	ASSET_NAME=$$(echo "$$RELEASE_INFO" | jq -r \
		'[.assets[] | select(.name | startswith("nanvix-x86-$(MACHINE)-multi-process-release-$(NANVIX_MEMORY_SIZE)"))][0].name'); \
	if [ -z "$$ASSET_NAME" ] || [ "$$ASSET_NAME" = "null" ]; then \
		echo "ERROR: Could not find a microvm multi-process release asset." >&2; \
		exit 1; \
	fi; \
	echo "  Release: $$TAG_NAME"; \
	echo "  Asset: $$ASSET_NAME"; \
	DOCKER_IMAGE="$(NANVIX_TOOLCHAIN_IMAGE)"; \
	echo "  Docker image: $$DOCKER_IMAGE"; \
	TMPDIR=$$(mktemp -d); \
	gh release download "$(NANVIX_RELEASE)" --repo "$(NANVIX_REPO)" \
		--pattern "$$ASSET_NAME" \
		--dir "$$TMPDIR"; \
	mkdir -p $(NANVIX_DIR); \
	tar xjf "$$TMPDIR/$$ASSET_NAME" -C $(NANVIX_DIR) --strip-components=1; \
	rm -rf "$$TMPDIR"; \
	echo "$$DOCKER_IMAGE" > $(NANVIX_DIR)/.docker-image; \
	echo ""; \
	echo "Done. Nanvix release extracted to $(NANVIX_DIR)/."

distclean: clean
	rm -rf $(NANVIX_DIR)

.PHONY: all run compile clean init distclean
