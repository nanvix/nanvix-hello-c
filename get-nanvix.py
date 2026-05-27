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
        "--output-dir",
        required=True,
        type=Path,
        help="Output directory for release artifacts.",
    )
    args = parser.parse_args()

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

    asset_prefix = (
        f"nanvix-x86-{args.machine}-{args.deployment_mode}"
        f"-release-{args.memory_size}"
    )
    asset_name = find_asset(release_info.get("assets", []), asset_prefix)
    if not asset_name:
        print(
            f"ERROR: Could not find a release asset matching prefix '{asset_prefix}'.",
            file=sys.stderr,
        )
        return 1

    print(f"  Release: {tag_name}")
    print(f"  Asset: {asset_name}")

    with tempfile.TemporaryDirectory() as tmpdir:
        tmp_path = Path(tmpdir)
        run_gh(
            "release",
            "download",
            args.release,
            "--repo",
            args.repo,
            "--pattern",
            asset_name,
            "--dir",
            str(tmp_path),
        )

        args.output_dir.mkdir(parents=True, exist_ok=True)
        archive_path = tmp_path / asset_name
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
                tar.extractall(args.output_dir, members=members, filter="data")
        except (tarfile.TarError, OSError) as exc:
            raise SystemExit(
                f"ERROR: failed to extract '{archive_path}' into '{args.output_dir}': {exc}\n"
                "The downloaded archive may be corrupted or incomplete. Try re-running "
                "'make distclean init', and verify 'gh auth status' if the problem persists."
            ) from exc

    print()
    print(f"Done. Nanvix release extracted to {args.output_dir}/.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
