"""Explicit developer fixture acquisition, never called by the product."""
import argparse
import json
from pathlib import Path
import re
import urllib.request

import smoke


def acquire(directory, acceptance, timeout):
    pins = json.loads(smoke.MANIFEST.read_text(encoding='utf-8'))['files']
    names = ('LICENSE', 'README.md', smoke.MODEL)
    prefix = ('https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/'
              '9217f5db79a29953eb74d5343926648285ec7e67/')
    if (len(pins) != len(names) or any(
            pin['url'] != prefix + name or not re.fullmatch('[0-9a-f]{64}', pin['sha256'])
            for pin, name in zip(pins, names))):
        raise RuntimeError('unreviewed fixture manifest')
    directory.mkdir()  # Exclusive owner; caller removes it on all exits.
    for pin, name in zip(pins, names):
        path = directory / pin['sha256']
        with urllib.request.urlopen(pin['url'], timeout=timeout) as source, path.open('xb') as target:
            remaining = pin['size']
            while block := source.read(min(1024 * 1024, remaining + 1)):
                remaining -= len(block)
                if remaining < 0:
                    raise RuntimeError('fixture exceeds pinned size')
                target.write(block)
        smoke.verify_file(path, pin, gguf=name == smoke.MODEL)
        print('Acquired and verified: ' + json.dumps(pin, sort_keys=True), flush=True)
        if name == 'LICENSE' and acceptance != pin['sha256']:
            raise RuntimeError('explicit acceptance must equal verified LICENSE SHA256 before weight acquisition')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--accept-terms-sha256', required=True)
    parser.add_argument('--timeout-seconds', type=smoke.positive_seconds, required=True,
                        help='per network I/O timeout; workflow supplies total deadline')
    args = parser.parse_args()
    acquire(args.directory, args.accept_terms_sha256, args.timeout_seconds)
