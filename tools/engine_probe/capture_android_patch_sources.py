"""Retain the selected Android LLVM patch blobs from their recorded Git commit.

This is audit tooling only. It executes no source from the fetched repository;
Git's immutable commit and blob objects bind the retained bytes.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time


_REPOSITORY = "https://android.googlesource.com/toolchain/llvm_android"
_REVISION = "e727bfb014bd436f581a66a450c939a6983a1fc3"
_PATCH_BASENAMES = (
    "move-cxa-demangle-into-libcxxdemangle.patch",
    "9a2fd97d391caf1060e303f636d7113501788d2f-r530567.patch",
    "b433076fcbacba8a3b91446390bbea5843322bcd-v2.patch",
    "e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch",
)
_EXACT_PATCH_PATHS = {
    "e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch":
        "patches/cherry/e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch",
}
_OBJECT_ID = re.compile(r"[0-9a-f]{40}")


def _git_environment():
    environment = os.environ.copy()
    for name in tuple(environment):
        if name.startswith("GIT_CONFIG_") or name in {
            "GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
            "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_ASKPASS",
        }:
            environment.pop(name, None)
    environment.update({
        "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_CONFIG_GLOBAL": os.devnull,
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_OPTIONAL_LOCKS": "0",
    })
    return environment


def _git(repository, arguments, deadline):
    command = ["git"]
    if repository is not None:
        command.extend(("-C", str(repository)))
    command.extend(arguments)
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError("Git source-capture deadline expired")
    try:
        result = subprocess.run(
            command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            timeout=remaining, check=False, env=_git_environment(),
        )
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Git source-capture deadline expired") from error
    except OSError as error:
        raise RuntimeError("Git source-capture command is unavailable") from error
    if result.returncode:
        raise RuntimeError(f"Git source-capture command failed (exit {result.returncode})")
    return result.stdout


def _validate_revision(revision):
    if not isinstance(revision, str) or not _OBJECT_ID.fullmatch(revision):
        raise ValueError("revision must be a complete lowercase Git commit ID")


def _capture(repository, revision, output, max_bytes, source_url, deadline):
    _validate_revision(revision)
    if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
        raise ValueError("max_bytes must be a positive integer")
    root = Path(repository)
    if root.is_symlink() or not root.is_dir():
        raise RuntimeError("source repository must be a real Git directory")

    commit = _git(root, ["rev-parse", "--verify", f"{revision}^{{commit}}"], deadline).decode("ascii").strip()
    if commit != revision:
        raise RuntimeError("fetched commit does not match the pinned source revision")
    tree = _git(root, ["rev-parse", "--verify", f"{revision}^{{tree}}"], deadline).decode("ascii").strip()
    if not _OBJECT_ID.fullmatch(tree):
        raise RuntimeError("pinned source tree ID is malformed")

    tree_listing = _git(root, ["ls-tree", "-r", "-z", revision, "--", "patches"], deadline)
    if len(tree_listing) > max_bytes:
        raise RuntimeError("pinned patch-tree index exceeds the configured capture bound")
    tree_index_bytes = len(tree_listing)
    rows = tree_listing.split(b"\0")
    if not rows or rows[-1] != b"":
        raise RuntimeError("pinned patch-tree index is malformed")
    wanted = {name.encode("ascii") for name in _PATCH_BASENAMES}
    selected = {}
    for row in rows[:-1]:
        metadata, separator, recorded_path = row.partition(b"\t")
        fields = metadata.split()
        if not separator or len(fields) != 3:
            raise RuntimeError("pinned patch-tree entry is malformed")
        basename = recorded_path.rsplit(b"/", 1)[-1]
        if basename not in wanted:
            continue
        path = recorded_path.decode("utf-8", errors="strict")
        basename_text = basename.decode("ascii")
        if _EXACT_PATCH_PATHS.get(basename_text, path) != path:
            continue
        if (basename in selected or fields[0] != b"100644" or fields[1] != b"blob"
                or not _OBJECT_ID.fullmatch(fields[2].decode("ascii", errors="replace"))):
            raise RuntimeError(f"pinned patch is duplicate or not a regular Git blob: {path}")
        selected[basename] = (path, fields[2].decode("ascii"))
    if set(selected) != wanted:
        missing = sorted(name.decode("ascii") for name in wanted - set(selected))
        raise RuntimeError("pinned source is missing named patch payloads: " + ", ".join(missing))

    captured = []
    total_bytes = 0
    for basename in _PATCH_BASENAMES:
        path, object_id = selected[basename.encode("ascii")]
        size_raw = _git(root, ["cat-file", "-s", object_id], deadline)
        try:
            size = int(size_raw.decode("ascii").strip())
        except (UnicodeDecodeError, ValueError) as error:
            raise RuntimeError(f"pinned patch size is malformed: {path}") from error
        if size <= 0 or size > max_bytes - tree_index_bytes - total_bytes:
            raise RuntimeError("patch index and payloads exceed the configured capture bound")
        content = _git(root, ["cat-file", "blob", object_id], deadline)
        if len(content) != size:
            raise RuntimeError(f"pinned patch changed during capture: {path}")
        captured.append({
            "path": path,
            "git_blob_id": object_id,
            "bytes": size,
            "sha256": hashlib.sha256(content).hexdigest(),
            "content": content,
        })
        total_bytes += size

    destination = Path(output)
    if destination.exists() or destination.is_symlink() or not destination.parent.is_dir():
        raise RuntimeError("capture output must be a new directory under an existing directory")
    manifest = {
        "schema": 1,
        "repository": source_url,
        "revision": commit,
        "tree": tree,
        "capture_scope": "hash and size metadata for four selected patch blobs; raw blobs are not retained in the artifact and no fetched code is executed",
        "max_bytes": max_bytes,
        "tree_index_bytes": tree_index_bytes,
        "patch_bytes": total_bytes,
        "total_bytes": tree_index_bytes + total_bytes,
        "files": [
            {key: record[key] for key in ("path", "git_blob_id", "bytes", "sha256")}
            for record in captured
        ],
    }
    destination.mkdir()
    try:
        manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode("utf-8")
        (destination / "manifest.json").write_bytes(manifest_bytes)
    except Exception:
        shutil.rmtree(destination)
        raise
    manifest["manifest_sha256"] = hashlib.sha256(manifest_bytes).hexdigest()
    return manifest


def fetch_and_capture(repository_url, revision, output, max_bytes, timeout_seconds):
    _validate_revision(revision)
    if isinstance(timeout_seconds, bool) or not isinstance(timeout_seconds, int) or timeout_seconds <= 0:
        raise ValueError("timeout_seconds must be a positive integer")
    deadline = time.monotonic() + timeout_seconds
    with tempfile.TemporaryDirectory(prefix="kotoha-android-llvm-") as temporary:
        repository = Path(temporary) / "source.git"
        _git(None, ["init", "--bare", "--quiet", str(repository)], deadline)
        _git(repository, ["fetch", "--depth=1", "--no-tags", "--quiet", repository_url, revision], deadline)
        fetched = _git(repository, ["rev-parse", "--verify", "FETCH_HEAD^{commit}"], deadline).decode("ascii").strip()
        if fetched != revision:
            raise RuntimeError("remote returned a commit other than the pinned revision")
        return _capture(repository, revision, output, max_bytes, repository_url, deadline)


def positive_int(value):
    if not value.isascii() or not value.isdigit() or int(value) <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return int(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--max-bytes", required=True, type=positive_int)
    parser.add_argument("--fetch-timeout-seconds", required=True, type=positive_int)
    args = parser.parse_args()
    manifest = fetch_and_capture(
        _REPOSITORY, _REVISION, args.output, args.max_bytes, args.fetch_timeout_seconds,
    )
    print("Captured pinned Android LLVM patches: " + json.dumps({
        "files": len(manifest["files"]),
        "bytes": manifest["total_bytes"],
        "revision": manifest["revision"],
        "manifest_sha256": manifest["manifest_sha256"],
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        raise SystemExit(f"FAIL: {error}") from error
