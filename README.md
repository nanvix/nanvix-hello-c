# Hello World for Nanvix (C)

A minimal example showing how to compile and run a "Hello World" C application on
[Nanvix](https://github.com/nanvix/nanvix).

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/)
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated (`gh auth login`)
- [Python](https://www.python.org/) 3.12 or newer (used by `get-nanvix.py` for `make init`)
- [KVM](https://github.com/nanvix/nanvix/blob/main/doc/setup.md#4-setup-kvm) enabled

## Quick Start

```bash
# 1. Download the Nanvix release.
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
- `NANVIX_TOOLCHAIN_DIR` — Cross-compiler install prefix inside the toolchain Docker image.
- `NANVIX_MEMORY_SIZE` — MicroVM memory size used to select the release asset.
- `NANVIX_DEPLOYMENT_MODE` — Deployment mode: `multi-process` (default) or `standalone`.
- `NANVIX_DIR` — Local directory for release artifacts.

See the top of the [Makefile](Makefile) for current default values.

### Deployment Modes

Two deployment modes are supported, selected via `NANVIX_DEPLOYMENT_MODE`:

- **`multi-process`** (default) — Guest applications run inside the Nanvix MicroVM, while the
  system daemons run on the hosting platform as part of the trusted computing base.
- **`standalone`** — Guest applications and the system daemons all
  run inside the Nanvix MicroVM.

The release asset downloaded by `make init` is mode-specific, so switch modes by overriding the
variable on every relevant `make` invocation (after re-running `init`):

```bash
make distclean
make init NANVIX_DEPLOYMENT_MODE=standalone
make run  NANVIX_DEPLOYMENT_MODE=standalone
```

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

In `multi-process` mode the application ELF is passed directly to `nanvixd.elf`. The guest
application runs inside the Nanvix MicroVM, while the system daemons run on the hosting platform and
are launched by `nanvixd.elf` from the release `bin/` directory.

In `standalone` mode the Makefile invokes `mkimage.elf` (a host-side tool shipped in the release
`bin/` directory) to assemble an initrd image bundling the application together with system daemons.
`nanvixd.elf` is then booted with that initrd as its payload, so the guest application and the
system daemons all run together inside the Nanvix MicroVM.

## License

This project is distributed under the [MIT License](LICENSE).
