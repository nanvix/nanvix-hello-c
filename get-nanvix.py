#!/usr/bin/env python3
# Copyright(c) The Maintainers of Nanvix.
# Licensed under the MIT License.

"""Download and extract a Nanvix release.

Resolves the release asset for the requested machine / deployment mode / memory size, downloads it
via 'gh release download', and extracts it into the given output directory.
"""

import argparse
import json
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path
from typing import Any

# Minimum supported Python version.
#
# 'tarfile.extractall(..., filter="data")' (used below to apply the documented mitigation for
# CVE-2007-4559-class path-traversal in crafted archives) is only available from Python 3.12
# onwards. Fail loudly here rather than with a confusing TypeError deep in the extraction call.
MIN_PYTHON: tuple[int, int] = (3, 12)


def _check_python_version() -> None:
    if sys.version_info < MIN_PYTHON:
        required = ".".join(str(p) for p in MIN_PYTHON)
        current = "{}.{}.{}".format(*sys.version_info[:3])
        print(
            f"ERROR: get-nanvix.py requires Python {required} or newer (running {current}).",
            file=sys.stderr,
        )
        sys.exit(1)


def run_gh_json(*args: str) -> dict[str, Any]:
    """Run a 'gh' command that returns JSON and parse its stdout."""
    cmd = ["gh", *args]
    try:
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as exc:
        raise SystemExit(
            "ERROR: 'gh' CLI not found on PATH. Install it from https://cli.github.com/ "
            "and run 'gh auth login'."
        ) from exc
    except subprocess.CalledProcessError as exc:
        stderr = (exc.stderr or "").strip()
        raise SystemExit(
            f"ERROR: command failed ({' '.join(cmd)}): exit {exc.returncode}\n{stderr}"
        ) from exc
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: failed to parse JSON from '{' '.join(cmd)}': {exc}"
        ) from exc


def run_gh(*args: str) -> None:
    """Run a 'gh' command, surfacing failures as friendly SystemExit messages."""
    cmd = ["gh", *args]
    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError as exc:
        raise SystemExit(
            "ERROR: 'gh' CLI not found on PATH. Install it from https://cli.github.com/ "
            "and run 'gh auth login'."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise SystemExit(
            f"ERROR: command failed ({' '.join(cmd)}): exit {exc.returncode}"
        ) from exc


def find_asset(assets: list[dict[str, Any]], prefix: str) -> str:
    """Return the first asset name starting with the given prefix."""
    for asset in assets:
        name = asset.get("name", "")
        if isinstance(name, str) and name.startswith(prefix):
            return name
    return ""


def main() -> int:
    _check_python_version()

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", required=True, help="Nanvix GitHub repository.")
    parser.add_argument("--release", required=True, help="Release tag to fetch.")
    parser.add_argument("--machine", required=True, help="Target machine.")
    parser.add_argument("--deployment-mode", required=True, help="Deployment mode.")
    parser.add_argument("--memory-size", required=True, help="MicroVM memory size.")
    parser.add_argument(
        "--host-os",
        default=_default_host_os(),
        choices=["linux", "windows"],
        help=(
            "Host OS that will run nanvixd (default: auto-detected from sys.platform). "
            "When 'windows', the Windows host-binary zip is downloaded and flat-extracted "
            "into <output-dir>/bin/ in addition to the Linux runtime tarball. "
            "Only the 'standalone' deployment mode is supported on Windows."
        ),
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Output directory for release artifacts.",
    )
    args = parser.parse_args()

    if args.host_os == "windows" and args.deployment_mode != "standalone":
        print(
            "ERROR: --host-os windows requires --deployment-mode standalone "
            f"(got '{args.deployment_mode}'). On Windows, single-process mode is not "
            "supported because the system daemons must run inside the Nanvix MicroVM.",
            file=sys.stderr,
        )
        return 1

    print(f"Downloading Nanvix release {args.release}...")

    release_info = run_gh_json(
        "release",
        "view",
        args.release,
        "--repo",
        args.repo,
        "--json",
        "tagName,assets",
    )
    tag_name = release_info["tagName"]
    assets: list[dict[str, Any]] = release_info.get("assets", [])

    # Always download the Linux runtime tarball for its complete bin/ layout.
    # On Windows, overlay the native host binaries used to run and bundle the
    # standalone guest.
    linux_prefix = (
        f"nanvix-x86-{args.machine}-{args.deployment_mode}-release-{args.memory_size}"
    )
    linux_asset = find_asset(assets, linux_prefix)
    if not linux_asset:
        print(
            f"ERROR: Could not find a release asset matching prefix '{linux_prefix}'.",
            file=sys.stderr,
        )
        return 1

    print(f"  Release: {tag_name}")
    print(f"  Linux asset: {linux_asset}")

    windows_asset = ""
    if args.host_os == "windows":
        windows_prefix = (
            f"nanvix-windows-x86-{args.machine}-{args.deployment_mode}"
            f"-release-{args.memory_size}"
        )
        windows_asset = find_asset(assets, windows_prefix)
        if not windows_asset:
            print(
                f"ERROR: Could not find a Windows release asset matching prefix "
                f"'{windows_prefix}'.",
                file=sys.stderr,
            )
            return 1
        print(f"  Windows asset: {windows_asset}")

    args.output_dir.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        patterns = [linux_asset] + ([windows_asset] if windows_asset else [])
        for pattern in patterns:
            run_gh(
                "release",
                "download",
                args.release,
                "--repo",
                args.repo,
                "--pattern",
                pattern,
                "--dir",
                str(tmp_path),
            )

        _extract_linux_tarball(tmp_path / linux_asset, args.output_dir)
        if windows_asset:
            _extract_windows_zip(tmp_path / windows_asset, args.output_dir / "bin")

    print()
    print(f"Done. Nanvix release extracted to {args.output_dir}/.")
    return 0


def _default_host_os() -> str:
    # 'win32' covers native CPython on Windows; 'cygwin' and 'msys' cover the
    # Cygwin and MSYS2 Python builds, both of which run on a Windows host and
    # therefore need the Windows host-binary zip even though they expose a
    # Unix-like environment.
    if sys.platform.startswith(("win", "cygwin", "msys")):
        return "windows"
    return "linux"


def _extract_linux_tarball(archive_path: Path, output_dir: Path) -> None:
    try:
        with tarfile.open(archive_path, "r:bz2") as tar:
            members: list[tarfile.TarInfo] = []
            for member in tar.getmembers():
                # Equivalent of 'tar --strip-components=1': split on '/' so that a leading './'
                # counts as one component, matching GNU tar's behaviour (pathlib.Path would
                # silently normalise it away and we would strip the wrong component).
                parts = member.name.split("/")
                if len(parts) <= 1:
                    continue
                stripped = "/".join(parts[1:])
                if not stripped:
                    continue
                member.name = stripped
                members.append(member)
            tar.extractall(output_dir, members=members, filter="data")
    except (tarfile.TarError, OSError) as exc:
        raise SystemExit(
            f"ERROR: failed to extract '{archive_path}' into '{output_dir}': {exc}\n"
            "The downloaded archive may be corrupted or incomplete. Try re-running "
            "'make distclean init', and verify 'gh auth status' if the problem persists."
        ) from exc


def _extract_windows_zip(archive_path: Path, output_dir: Path) -> None:
    # The Windows release zip is flat (no top-level directory). Extract everything
    # into <.nanvix>/bin/ so that nanvixd.exe, mkimage.exe, kernel.elf, uservm.exe
    # and the daemon ELFs sit alongside the Linux-extracted contents.
    output_dir.mkdir(parents=True, exist_ok=True)
    base = output_dir.resolve()
    try:
        with zipfile.ZipFile(archive_path) as zf:
            for info in zf.infolist():
                # Defence in depth against path-traversal in crafted archives.
                # Use Path.is_relative_to() against the resolved base directory:
                # a raw string prefix check would let e.g. '../out_evil/file'
                # escape '/tmp/out' into the sibling '/tmp/out_evil'.
                target = (output_dir / info.filename).resolve()
                if not target.is_relative_to(base):
                    raise SystemExit(
                        f"ERROR: refusing to extract suspicious path "
                        f"'{info.filename}' from '{archive_path}'."
                    )
                zf.extract(info, output_dir)
    except (zipfile.BadZipFile, OSError) as exc:
        raise SystemExit(
            f"ERROR: failed to extract '{archive_path}' into '{output_dir}': {exc}\n"
            "The downloaded archive may be corrupted or incomplete. Try re-running "
            "'make distclean init', and verify 'gh auth status' if the problem persists."
        ) from exc


if __name__ == "__main__":
    sys.exit(main())
