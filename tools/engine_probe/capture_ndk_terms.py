"""Capture bounded, hash-identified NDK/LLVM license and source records.

This is audit evidence only: it does not determine which terms apply or classify
archive members. It must run against the installed NDK selected by the build.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import shutil
import xml.etree.ElementTree as ET


_VERSION = re.compile(r"[0-9]+\.[0-9]+\.[0-9]+")
_TERM_NAME = re.compile(r"(?:licenses?|licences?|notices?|copying|copyrights?)(?:[._-].*)?", re.IGNORECASE)
_TOOLCHAIN = Path("toolchains/llvm/prebuilt/linux-x86_64")
_SOURCE_INFO = _TOOLCHAIN / "clang-r530567/clang_source_info.md"
_LLVM_NOTICE = _TOOLCHAIN / "clang-r530567/NOTICE"
_REQUIRED_METADATA = (Path("source.properties"), Path("package.xml"))


def _regular_size(root: Path, relative: Path) -> int:
    path = root
    for component in relative.parts[:-1]:
        path = path / component
        if not stat.S_ISDIR(path.lstat().st_mode):
            raise RuntimeError(f"NDK record parent is not a real directory: {relative.as_posix()}")
    info = (path / relative.parts[-1]).lstat()
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError(f"NDK record is not a regular file: {relative.as_posix()}")
    return info.st_size


def _read_regular(root: Path, relative: Path, max_bytes: int) -> bytes:
    size = _regular_size(root, relative)
    if size > max_bytes:
        raise RuntimeError(f"NDK record exceeds configured byte bound: {relative.as_posix()}")
    data = (root / relative).read_bytes()
    if len(data) != size:
        raise RuntimeError(f"NDK record changed while being captured: {relative.as_posix()}")
    return data


def _candidate_terms(root: Path):
    """Walk only the installed LLVM toolchain subtree; never follow links."""
    base = root
    for component in _TOOLCHAIN.parts:
        base = base / component
        if not stat.S_ISDIR(base.lstat().st_mode):
            raise RuntimeError("installed LLVM toolchain directory is missing or linked")
    found = []
    for name in sorted(os.listdir(root)):
        candidate = root / name
        if _TERM_NAME.fullmatch(name):
            if candidate.is_symlink():
                raise RuntimeError(f"linked NDK root term record: {name}")
            if not stat.S_ISREG(candidate.lstat().st_mode):
                raise RuntimeError(f"non-file NDK root term record: {name}")
            found.append(Path(name))
    for directory, dirs, files in os.walk(base, followlinks=False):
        current = Path(directory)
        dirs[:] = sorted(name for name in dirs if not (current / name).is_symlink())
        for name in sorted(files):
            if _TERM_NAME.fullmatch(name):
                path = current / name
                if path.is_symlink():
                    raise RuntimeError(f"linked NDK term record: {path.relative_to(root).as_posix()}")
                found.append(path.relative_to(root))
    return found


def capture(ndk: Path, output: Path, expected_version: str,
            max_files: int, max_bytes: int) -> dict:
    if not _VERSION.fullmatch(expected_version):
        raise ValueError("expected version must be a numeric NDK package revision")
    if max_files <= 0 or max_bytes <= 0:
        raise ValueError("capture bounds must be positive")
    root = ndk.resolve(strict=True)
    if not root.is_dir() or ndk.is_symlink():
        raise RuntimeError("NDK root must be a real installed directory")
    source_properties = _read_regular(root, Path("source.properties"), max_bytes)
    try:
        properties = source_properties.decode("utf-8")
    except UnicodeDecodeError as error:
        raise RuntimeError("NDK source.properties is not UTF-8") from error
    if not re.search(r"(?m)^\s*Pkg\.Revision\s*=\s*" + re.escape(expected_version) + r"\s*$", properties):
        raise RuntimeError("installed NDK revision does not match the reviewed package")

    package_xml = _read_regular(root, Path("package.xml"), max_bytes - len(source_properties))
    try:
        package = ET.fromstring(package_xml)
    except ET.ParseError as error:
        raise RuntimeError("installed NDK package.xml is malformed") from error
    package_paths = [node.attrib.get("path", "") for node in package.iter()
                     if node.tag.rsplit("}", 1)[-1] == "localPackage"]
    if f"ndk;{expected_version}" not in package_paths:
        raise RuntimeError("installed NDK package metadata does not match the reviewed revision")

    # These records bind the package's own version and the exact compiler/LLVM
    # revision selected by the NDK release. Both are required, not best-effort.
    candidates = set(_candidate_terms(root))
    candidates.update(_REQUIRED_METADATA)
    candidates.update((_SOURCE_INFO, _LLVM_NOTICE))
    candidates = sorted(candidates, key=lambda path: path.as_posix())
    if len(candidates) > max_files:
        raise RuntimeError("NDK term-record count exceeds configured capture bound")

    sizes = {relative: _regular_size(root, relative) for relative in candidates}
    if any(size <= 0 for size in sizes.values()):
        raise RuntimeError("empty required/candidate NDK record")
    total_bytes = sum(sizes.values())
    if total_bytes > max_bytes:
        raise RuntimeError("NDK term-record bytes exceed configured capture bound")

    records = []
    for relative in candidates:
        data = _read_regular(root, relative, sizes[relative])
        destination = output / "records" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        records.append({
            "path": relative.as_posix(),
            "bytes": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
            "role": "package-metadata" if relative in _REQUIRED_METADATA else
                    "toolchain-source-info" if relative == _SOURCE_INFO else
                    "toolchain-notice" if relative == _LLVM_NOTICE else
                    "candidate-license-or-notice",
        })

    manifest = {
        "schema": 1,
        "ndk_revision": expected_version,
        "target": {"host": "linux-x86_64", "android_api": 35, "abi": "x86_64"},
        "capture_scope": "installed NDK package metadata plus matching root-level and host LLVM toolchain license/notice/copying/copyright-named regular files; not a legal classification or complete selected-member mapping",
        "bounds": {"max_files": max_files, "max_bytes": max_bytes},
        "total_bytes": total_bytes,
        "files": records,
    }
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n",
                                            encoding="utf-8")
    return manifest


def positive_int(value):
    if not value.isascii() or not value.isdigit() or int(value) <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return int(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--max-files", required=True, type=positive_int)
    parser.add_argument("--max-bytes", required=True, type=positive_int)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    try:
        manifest = capture(args.ndk, args.output, args.expected_version,
                           args.max_files, args.max_bytes)
    except (OSError, RuntimeError, ValueError, UnicodeError):
        shutil.rmtree(args.output)
        raise
    print("Captured NDK records: " + json.dumps({
        "files": len(manifest["files"]), "bytes": manifest["total_bytes"],
        "manifest_sha256": hashlib.sha256((args.output / "manifest.json").read_bytes()).hexdigest(),
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, UnicodeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
