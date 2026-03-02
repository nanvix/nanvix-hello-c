# Copyright(c) The Maintainers of Nanvix.
# Licensed under the MIT License.

#===============================================================================
# Build Configuration
#===============================================================================

# Nanvix GitHub repository.
NANVIX_REPO ?= nanvix/nanvix

# Nanvix release directory (populated by 'make init').
NANVIX_DIR ?= .nanvix

# Toolchain directory (set by the Docker image).
TOOLCHAIN_DIR ?= /opt/nanvix

# Cross-compiler and tools.
CC := $(TOOLCHAIN_DIR)/bin/i686-nanvix-gcc

# Compiler flags.
CFLAGS := -std=c17
CFLAGS += -m32 -march=pentiumpro -Wa,-march=pentiumpro
CFLAGS += -Wall -Wextra -Werror
CFLAGS += -O2

# Linker flags.
LDFLAGS := -z noexecstack -T $(NANVIX_DIR)/lib/user.ld

# Libraries (order matters — use grouping to resolve circular dependencies).
LIBRARIES := -Wl,--start-group $(NANVIX_DIR)/lib/libposix.a $(TOOLCHAIN_DIR)/i686-nanvix/lib/libc.a -Wl,--end-group

# Source and object files.
SOURCES := main.c
OBJECTS := $(SOURCES:.c=.o)

# Output binary.
BINARY := hello-c.elf

#===============================================================================
# Host Targets
#===============================================================================

all: build/$(BINARY)

# Build hello-c.elf inside Docker and export to build/.
build/$(BINARY): $(SOURCES) Makefile Dockerfile $(NANVIX_DIR)/lib/libposix.a
	DOCKER_BUILDKIT=1 docker build \
		--build-arg BASE_IMAGE=$$(cat $(NANVIX_DIR)/.docker-image) \
		--output type=local,dest=build .
	@touch $@

# Run on Nanvix.
run: build/$(BINARY)
	$(NANVIX_DIR)/bin/nanvixd.elf -console-file /dev/stdout -- ./build/$(BINARY)

clean:
	rm -f $(OBJECTS) $(BINARY)
	rm -rf build

#===============================================================================
# Container Targets (used inside Docker)
#===============================================================================

compile: $(BINARY)

$(BINARY): $(OBJECTS)
	$(CC) $(LDFLAGS) $(OBJECTS) $(LIBRARIES) -o $@

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

#===============================================================================
# Init — download the latest Nanvix release and resolve the Docker image tag
#===============================================================================

init: $(NANVIX_DIR)/lib/libposix.a

$(NANVIX_DIR)/lib/libposix.a:
	@echo "Downloading the latest Nanvix release..."
	@RELEASE_INFO=$$(gh release view latest --repo "$(NANVIX_REPO)" --json tagName,assets); \
	TAG_NAME=$$(echo "$$RELEASE_INFO" | jq -r '.tagName'); \
	ASSET_NAME=$$(echo "$$RELEASE_INFO" | jq -r \
		'.assets[] | select(.name | startswith("nanvix-microvm-multi-process-release")) | .name'); \
	if [ -z "$$ASSET_NAME" ]; then \
		echo "ERROR: Could not find a microvm multi-process release asset." >&2; \
		exit 1; \
	fi; \
	echo "  Release: $$TAG_NAME"; \
	echo "  Asset: $$ASSET_NAME"; \
	CARGO_TOML=$$(gh api "repos/$(NANVIX_REPO)/contents/Cargo.toml?ref=$$TAG_NAME" \
		--jq '.content' 2>/dev/null | base64 -d) || true; \
	CARGO_VERSION=$$(echo "$$CARGO_TOML" | grep -m1 '^version' | sed 's/.*"\(.*\)".*/\1/') || true; \
	if [ -n "$$CARGO_VERSION" ]; then \
		MAJOR_MINOR="$${CARGO_VERSION%.*}"; \
		DOCKER_IMAGE="nanvix/toolchain:v$${MAJOR_MINOR}.x-minimal"; \
	else \
		DOCKER_IMAGE="nanvix/toolchain:latest-minimal"; \
	fi; \
	echo "  Docker image: $$DOCKER_IMAGE"; \
	TMPDIR=$$(mktemp -d); \
	gh release download latest --repo "$(NANVIX_REPO)" \
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
