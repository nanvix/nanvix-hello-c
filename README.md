# Hello World for Nanvix (C)

A minimal example showing how to compile and run a "Hello World" C application on
[Nanvix](https://github.com/nanvix/nanvix), using the
[ZScript](https://github.com/nanvix/zutils) build system.

## Prerequisites

- [Python 3.12+](https://www.python.org/downloads/)
- [Docker](https://docs.docker.com/engine/install/) *(optional — used as fallback when the native toolchain is not installed)*
- [GitHub CLI](https://cli.github.com/) (`gh`)
- [KVM](https://github.com/nanvix/nanvix/blob/main/doc/setup.md#4-setup-kvm) enabled

## Quick Start

```bash
# 1. Download the Nanvix sysroot (provides nanvixd.elf, libposix.a, user.ld).
./z setup

# 2. Cross-compile main.c → hello-c.elf.
./z build

# 3. Run smoke, integration, and functional tests on Nanvix.
./z test
```

On Windows (PowerShell 7+):

```powershell
./z.ps1 setup
./z.ps1 build
./z.ps1 test
```

You should see:

```plain
Hello, World from Nanvix!
```

## Project Structure

```plain
.
├── main.c            # Hello World source code
├── Makefile.nanvix   # Cross-compilation rules, test targets, and toolchain detection
├── z                 # Bootstrap wrapper (Bash) — finds Python, creates venv, runs z.py
├── z.ps1             # Bootstrap wrapper (PowerShell)
└── .nanvix/
    └── z.py          # ZScript build script (setup, build, test, clean)
```

## How It Works

### Cross-Compilation

Nanvix applications are cross-compiled using the `i686-nanvix-gcc` toolchain, which targets the
Nanvix microkernel. If the native toolchain is not installed at `/opt/nanvix`, the build
automatically falls back to the
[`nanvix/toolchain`](https://hub.docker.com/r/nanvix/toolchain) minimal Docker image.

The application is linked against:

- **`libposix.a`** — Nanvix POSIX compatibility layer (from the Nanvix sysroot)
- **`libc.a`** — Newlib C library (from the toolchain)
- **`user.ld`** — Linker script defining the Nanvix user-space memory layout (from the Nanvix sysroot)

### Running

`nanvixd.elf` is the Nanvix daemon that boots a microkernel VM and runs your application inside it.
Functional tests invoke `nanvixd.elf` and verify the expected output appears.

### Build System

The `./z` wrapper bootstraps a Python virtual environment, installs
[nanvix-zutil](https://github.com/nanvix/zutils), and delegates to `.nanvix/z.py`.
The build script drives `Makefile.nanvix` with the correct toolchain and sysroot paths.

Available commands: `./z setup`, `./z build`, `./z test`, `./z clean`, `./z help`.

## License

This project is distributed under the [MIT License](LICENSE).
