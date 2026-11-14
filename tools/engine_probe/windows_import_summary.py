"""Capture a privacy-safe import summary for the built Windows Release runner."""

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from runtime_providers import parse_linkage_log, sha256_file, validate_linkage_target

MACHINE_RE = re.compile(r'^\s*8664\s+machine\s+\(x64\)\s*$', re.IGNORECASE | re.MULTILINE)
DLL_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.-]*\.dll$', re.IGNORECASE)


def make_summary(executable, direct, delay):
    """Create only the path-free identity and import fields intended for retention."""
    path = Path(executable)
    if path.name.lower() != 'kotoha.exe':
        raise ValueError('expected Release kotoha.exe')

    def safe_imports(names):
        normalized = set()
        for name in names:
            if not isinstance(name, str) or not DLL_RE.fullmatch(name):
                raise ValueError('import name is not a DLL basename')
            normalized.add(name.lower())
        return sorted(normalized)

    direct_imports = safe_imports(direct)
    delay_imports = sorted(set(safe_imports(delay)) - set(direct_imports))
    size, digest = sha256_file(path)
    return {
        'exe': 'kotoha.exe',
        'sha256': digest,
        'size': size,
        'machine': 'x64',
        'direct_imports': direct_imports,
        'delay_imports': delay_imports,
    }


def capture(executable, output, dumpbin):
    expected = Path(executable)
    if expected.name.lower() != 'kotoha.exe' or not expected.is_file():
        raise ValueError('expected Release kotoha.exe is missing')
    tool = Path(dumpbin)
    if not tool.is_file():
        raise ValueError('dumpbin tool is unavailable')
    result = subprocess.run([str(tool), '/HEADERS', '/DEPENDENTS', str(expected)],
                            capture_output=True, text=True, errors='replace', check=False)
    if result.returncode:
        raise ValueError('dumpbin inspection failed')
    text = result.stdout + '\n' + result.stderr
    validate_linkage_target(text, expected)
    if len(MACHINE_RE.findall(text)) != 1:
        raise ValueError('dumpbin x64 machine evidence is missing or ambiguous')
    direct, delay = parse_linkage_log(text, expected.name)
    summary = make_summary(expected, direct, delay)

    target = Path(output)
    if target.resolve() == expected.resolve():
        raise ValueError('summary output must not overwrite the executable')
    temporary = target.with_name(target.name + '.tmp')
    try:
        temporary.write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n',
                             encoding='utf-8')
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--exe', required=True)
    parser.add_argument('--dumpbin', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    try:
        capture(args.exe, args.output, args.dumpbin)
    except (OSError, ValueError, subprocess.SubprocessError):
        print('Windows import capture failed closed', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
