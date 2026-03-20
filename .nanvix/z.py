# Copyright(c) The Maintainers of Nanvix.
# Licensed under the MIT License.

"""Nanvix build script for nanvix-hello-c.

Usage (from repository root):
    ./z setup      # Download sysroot
    ./z build      # Cross-compile main.c → hello-c.elf
    ./z test       # Run tests (smoke + integration + functional)
    ./z clean      # Remove build artifacts
"""

from nanvix_zutil import CFG_GH_TOKEN, CFG_SYSROOT, Sysroot, ZScript, log

# Exit codes (mirrors nanvix-zutil convention).
_EXIT_MISSING_DEP = 3

# Makefile variable names (build-system-specific).
_MAKE_VAR_CONFIG = "CONFIG_NANVIX"
_MAKE_VAR_HOME = "NANVIX_HOME"
_MAKE_VAR_PLATFORM = "PLATFORM"
_MAKE_VAR_PROCESS_MODE = "PROCESS_MODE"
_MAKE_VAR_MEMORY_SIZE = "MEMORY_SIZE"


class HelloCBuild(ZScript):
    """Build script for nanvix/nanvix-hello-c."""

    def _make(self, *targets: str, extra_vars: dict[str, str] | None = None) -> None:
        """Run ``make -f Makefile.nanvix`` with standard Nanvix variables."""
        nanvix_sysroot = self.config.get(CFG_SYSROOT, "")
        if not nanvix_sysroot:
            log.fatal(
                f"{CFG_SYSROOT} is not set.",
                code=_EXIT_MISSING_DEP,
                hint="Run `./z setup` first to download the sysroot.",
            )

        cmd: list[str] = [
            "make",
            "-f",
            "Makefile.nanvix",
            f"{_MAKE_VAR_CONFIG}=y",
            f"{_MAKE_VAR_HOME}={nanvix_sysroot}",
        ]
        if extra_vars:
            for key, val in extra_vars.items():
                cmd.append(f"{key}={val}")
        cmd.extend(targets)
        self.run(*cmd, cwd=self.repo_root)

    def setup(self) -> None:
        """Download the Nanvix sysroot and persist its path."""
        sysroot = Sysroot.download(
            machine=self.config.machine,
            deployment_mode=self.config.deployment_mode,
            memory_size=self.config.memory_size,
            tag="latest",
            gh_token=self.config.get(CFG_GH_TOKEN),
        )
        sysroot.verify(list(self.SYSROOT_REQUIRED_FILES))
        self.config.set(CFG_SYSROOT, str(sysroot.path))
        self.config.save()

    def build(self) -> None:
        """Cross-compile main.c into hello-c.elf for Nanvix."""
        self._make("all")

    def test(self) -> None:
        """Run the test suite (smoke + integration + functional)."""
        platform_vars = {
            _MAKE_VAR_PLATFORM: self.config.machine,
            _MAKE_VAR_PROCESS_MODE: self.config.deployment_mode,
            _MAKE_VAR_MEMORY_SIZE: self.config.memory_size,
        }
        self._make("test", extra_vars=platform_vars)

    def clean(self) -> None:
        """Remove build artifacts."""
        self.run("make", "-f", "Makefile.nanvix", "clean", cwd=self.repo_root)


if __name__ == "__main__":
    HelloCBuild.main()
