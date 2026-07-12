# Hello World for Nanvix (C)

A minimal example showing how to compile and run a "Hello World" C application on
[Nanvix](https://github.com/nanvix/nanvix).

## Prerequisites

- [Docker](https://docs.docker.com/engine/install/) (Docker Desktop on Windows)
- [GitHub CLI](https://cli.github.com/) (`gh`), authenticated (`gh auth login`)
- [Python](https://www.python.org/) 3.12 or newer (used by `get-nanvix.py` for `make init`)
- [KVM](https://github.com/nanvix/nanvix/blob/main/doc/setup.md#4-setup-kvm) enabled (Linux hosts only)
- On Windows: [Git for Windows](https://gitforwindows.org/) (provides Git Bash,
  which bundles `bash` and `cygpath` via msys2-runtime) plus GNU `make` on
  `PATH` (e.g. `choco install make`, or install [MSYS2](https://www.msys2.org/)
  and use the MSYS2 shell). Hardware virtualisation (Hyper-V / WHPX) must be
  enabled for `nanvixd.exe`.

## Quick Start

```bash
# 1. Download the Nanvix release.
make init

# 2. Build hello-c.elf using the Nanvix SDK Docker image.
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
- `NANVIX_SDK_IMAGE` — SDK Docker image (pinned by digest).
- `NANVIX_SDK_DIR` — SDK install prefix inside the Docker image.
- `NANVIX_MEMORY_SIZE` — MicroVM memory size used to select the release asset.
- `NANVIX_DEPLOYMENT_MODE` — Deployment mode: `standalone` (default) or `single-process`.
- `NANVIX_HOST_OS` — Host OS that drives `docker run` and launches `nanvixd`:
  `linux` or `windows`. Auto-detected from the build environment; override only
  when cross-driving (e.g. fetching Windows artifacts from a Linux box).
- `NANVIX_DIR` — Local directory for release artifacts.

See the top of the [Makefile](Makefile) for current default values.

### Deployment Modes

Two deployment modes are supported, selected via `NANVIX_DEPLOYMENT_MODE`:

- **`standalone`** (default) — Guest applications and the system daemons all
  run inside the Nanvix MicroVM.
- **`single-process`** — Guest applications run inside the Nanvix MicroVM, while the
  system daemons run on the hosting platform as part of the trusted computing base.

The release asset downloaded by `make init` is mode-specific, so switch modes by overriding the
variable on every relevant `make` invocation (after re-running `init`):

```bash
make distclean
make init NANVIX_DEPLOYMENT_MODE=single-process
make run  NANVIX_DEPLOYMENT_MODE=single-process
```

### Windows Hosts

Native Windows is supported through the same `Makefile`, driven from Git Bash
(with GNU `make` installed separately, e.g. `choco install make`) or from an
MSYS2 shell. Only the `standalone` deployment mode (the default) is
available: Windows releases ship `nanvixd.exe`, `mkimage.exe`, `kernel.elf`,
`uservm.exe`, and the system-daemon ELFs in a separate `.zip` asset, but
`single-process` requires `linuxd` which is Linux-only.

```bash
# From Git Bash, in the project root:
make init
make
make run
```

How this differs from a Linux host:

- `make init` downloads the Linux runtime tarball and the Windows host-binary
  zip. Both are merged under `.nanvix/`.
- `make` cross-compiles inside the Linux SDK container via Docker Desktop;
  the Makefile converts the MSYS-style workspace path with `cygpath -m` so the
  bind mount resolves correctly, and drops the Unix `-u $(id -u):$(id -g)` flag
  (Docker Desktop on Windows handles ownership through the bind mount).
- `make run` launches `nanvixd.exe` natively (no Docker), printing the guest
  console output to `CON`.

## Project Structure

```plain
.
├── main.c          # Hello World source code
├── Makefile        # Build rules, init target, and cross-compilation
└── .nanvix/        # Nanvix release artifacts (created by 'make init')
    └── bin/        # nanvixd.elf, kernel.elf, uservm.elf, linuxd.elf
```

## How It Works

### Cross-Compilation

Nanvix applications are cross-compiled with Clang in the versioned
[`nanvix-sdk-c-clang`](https://github.com/nanvix/sdk) image. The host `make`
invokes `make compile` inside that image via `docker run`, bind-mounting the
workspace so build artifacts land directly in `build/`.

The SDK Clang driver supplies Nanvix libc, compiler-rt, `crt0.o`, and
`user.ld`. Downloaded release artifacts are used only to run the application.

### Running

`nanvixd` is the Nanvix daemon that boots a microkernel VM and runs your application inside it.
The host-side executable suffix is host-specific: `nanvixd.elf` on Linux, `nanvixd.exe` on Windows
(both are native host binaries — the `.elf` suffix on Linux is historical). The Makefile selects the
right suffix automatically via `NANVIX_HOST_OS`.
The `-console-file` flag redirects the application's console output to the terminal: the Makefile
passes `/dev/stdout` on Linux and `CON` on Windows.

In `single-process` mode (Linux only) the application ELF is passed directly to `nanvixd.elf`. The
guest application runs inside the Nanvix MicroVM, while the system daemons run on the hosting
platform and are launched by `nanvixd.elf` from the release `bin/` directory.

In `standalone` mode the Makefile invokes `mkimage` (`mkimage.elf` on Linux, `mkimage.exe` on
Windows — both host-side tools shipped in the release `bin/` directory) to assemble an initrd image
bundling the application together with the system daemons. `nanvixd` is then booted with that
initrd as its payload, so the guest application and the system daemons all run together inside the
Nanvix MicroVM.

## License

This project is distributed under the [MIT License](LICENSE).
