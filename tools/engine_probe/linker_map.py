"""Validate and publish only the Android LLD map retained by the developer probe."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import tempfile


def record(path, max_bytes, output_dir):
    path = Path(path)
    output_dir = Path(output_dir)
    if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
        raise ValueError('map byte bound must be a positive integer')
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('linker map is missing or not a regular file')
    if path.parent.resolve() != output_dir.parent.resolve():
        raise ValueError('validated map directory must be beside the unvalidated map')
    if output_dir.exists() or output_dir.is_symlink():
        raise RuntimeError('validated map directory already exists')
    size = path.stat().st_size
    if size == 0:
        raise RuntimeError('linker map is empty')
    if size > max_bytes:
        raise RuntimeError(f'linker map exceeds configured byte bound ({size} > {max_bytes})')

    # Keep raw output and partially prepared evidence outside the workflow's
    # validated-map upload path. Publish the complete map+record together with
    # one same-filesystem directory rename only after validation succeeds.
    staging = Path(tempfile.mkdtemp(prefix='.linker-map-', dir=path.parent))
    try:
        staged_map = staging / 'llama-simple.map'
        os.replace(path, staged_map)
        before = staged_map.stat(follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode):
            raise RuntimeError('linker map is not a regular file')

        digest = hashlib.sha256()
        observed = 0
        with staged_map.open('rb') as stream:
            opened = os.fstat(stream.fileno())
            while observed <= max_bytes:
                chunk = stream.read(min(1024 * 1024, max_bytes - observed + 1))
                if not chunk:
                    break
                observed += len(chunk)
                if observed > max_bytes:
                    raise RuntimeError(f'linker map exceeds configured byte bound ({observed} > {max_bytes})')
                digest.update(chunk)
            after = os.fstat(stream.fileno())
        if (observed != size or after.st_size != size or
                (opened.st_dev, opened.st_ino, opened.st_mtime_ns) !=
                (after.st_dev, after.st_ino, after.st_mtime_ns)):
            raise RuntimeError('linker map changed while being recorded')

        result = {'size': observed, 'sha256': digest.hexdigest()}
        record_path = staging / 'llama-simple.map.sha256.json'
        record_path.write_text(json.dumps(result, sort_keys=True) + '\n', encoding='utf-8')
        os.rename(staging, output_dir)
        staging = None
        return result
    finally:
        if staging is not None:
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--max-bytes', required=True, type=int)
    parser.add_argument('--output-dir', required=True, type=Path)
    args = parser.parse_args()
    record(args.path, args.max_bytes, args.output_dir)


if __name__ == '__main__':
    main()
