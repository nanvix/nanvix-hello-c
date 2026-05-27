# Hello World for Nanvix (C)

A minimal example showing how to compile and run a "Hello World" C application on
[Nanvix](https://github.com/nanvix/nanvix).

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/)
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [KVM](https://github.com/nanvix/nanvix/blob/main/doc/setup.md#4-setup-kvm) enabled

## Quick Start

```bash
# 1. Download the pinned Nanvix release (provides nanvixd.elf, libposix.a, and user.ld).
make init

# 2. Build hello-c.elf using the Nanvix toolchain Docker image.
make

# 3. Run on Nanvix.
make run
```

You should see:

```plain
Hello, World from Nanvix!
```

### Configuration

The following `make` variables can be overridden on the command line or in the environment:

- `NANVIX_REPO` — Nanvix GitHub repository.
- `NANVIX_RELEASE` — Nanvix release tag to fetch (pinned).
- `NANVIX_TOOLCHAIN_IMAGE` — Cross-compiler Docker image (pinned).
- `NANVIX_MEMORY_SIZE` — MicroVM memory size used to select the release asset.
- `NANVIX_DIR` — Local directory for release artifacts.

See the top of the [Makefile](Makefile) for current default values.

## Project Structure

```plain
.
├── main.c          # Hello World source code
├── Makefile        # Build rules, init target, and cross-compilation
└── .nanvix/        # Nanvix release artifacts (created by 'make init')
    ├── bin/        # nanvixd.elf, kernel.elf, uservm.elf, linuxd.elf
    └── lib/        # libposix.a, user.ld
```

## How It Works

### Cross-Compilation

Nanvix applications are cross-compiled using the `i686-nanvix-gcc` toolchain, which targets the
Nanvix microkernel. The
[`ghcr.io/nanvix/toolchain-gcc`](https://github.com/nanvix/toolchain-gcc) Docker image
provides the full cross-compiler toolchain. The host `make` invokes `make compile` inside that
image via `docker run`, bind-mounting the workspace so build artifacts land directly in `build/`.

The application is linked against:

- **`libposix.a`** — Nanvix POSIX compatibility layer (from the Nanvix release)
- **`libc.a`** — Newlib C library (from the toolchain)
- **`user.ld`** — Linker script defining the Nanvix user-space memory layout (from the Nanvix release)

### Running

`nanvixd.elf` is the Nanvix daemon that boots a microkernel VM and runs your application inside it.
The `-console-file /dev/stdout` flag redirects the application's console output to the terminal.

## License

This project is distributed under the [MIT License](LICENSE).
