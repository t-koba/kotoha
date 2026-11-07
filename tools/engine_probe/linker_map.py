"""Validate and identify the Android LLD map retained by the developer probe."""
import argparse
import hashlib
import json
from pathlib import Path


def record(path, max_bytes):
    path = Path(path)
    if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
        raise ValueError('map byte bound must be a positive integer')
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('linker map is missing or not a regular file')
    size = path.stat().st_size
    if size == 0:
        raise RuntimeError('linker map is empty')
    if size > max_bytes:
        raise RuntimeError(f'linker map exceeds configured byte bound ({size} > {max_bytes})')
    digest = hashlib.sha256()
    observed = 0
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            observed += len(chunk)
            digest.update(chunk)
    if observed != size:
        raise RuntimeError('linker map changed while being recorded')
    result = {'size': size, 'sha256': digest.hexdigest()}
    record_path = path.with_name(path.name + '.sha256.json')
    record_path.write_text(json.dumps(result, sort_keys=True) + '\n', encoding='utf-8')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--max-bytes', required=True, type=int)
    args = parser.parse_args()
    record(args.path, args.max_bytes)


if __name__ == '__main__':
    main()
