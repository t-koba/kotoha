#!/usr/bin/env python3
"""Check (default) or regenerate the pinned Unicode bidi projection, offline."""
import argparse
import hashlib
from pathlib import Path
import re

SOURCE_URI = 'https://unicode.org/Public/18.0.0/ucd/extracted/DerivedBidiClass.txt'
SOURCE_SHA256 = 'd9e23222522551348ea1ccfbb4f62efbf98982afb95840f8959c08ed992c5607'
DATA_SHA256 = '69712a92c89809280008948c79da6da675a980a490eee024a379aeb6f5fb5034'
OUTPUT = Path(__file__).resolve().parents[1] / 'lib/unicode_bidi_data.dart'
# Unicode scalar/code point space is a format limit, not a runtime policy.
CODE_POINTS = 0x110000
CLASSES = set('L R AL EN ES ET AN CS NSM BN B S WS ON LRE LRO RLE RLO PDF LRI RLI FSI PDI'.split())
ALIASES = {'Left_To_Right': 'L', 'Right_To_Left': 'R',
           'Arabic_Letter': 'AL', 'European_Terminator': 'ET'}


def project(text):
    missing, explicit = [], []
    for line in text.splitlines():
        if re.match(r'^\s*#\s*@missing:', line):
            rule = line.split('@missing:', 1)[1].split('#', 1)[0]
            target = missing
        else:
            rule = line.split('#', 1)[0].strip()
            if not rule:
                continue
            target = explicit
        span, bidi = (field.strip() for field in rule.split(';'))
        bidi = ALIASES.get(bidi, bidi)
        if bidi not in CLASSES:
            raise ValueError(f'Unknown bidi class: {bidi}')
        bounds = span.split('..')
        start, end = int(bounds[0], 16), int(bounds[-1], 16)
        if len(bounds) > 2 or not 0 <= start <= end < CODE_POINTS:
            raise ValueError(f'Invalid code point range: {span}')
        value = {'L': 0, 'R': 1, 'AL': 1, 'B': 2,
                 'LRI': 3, 'RLI': 3, 'FSI': 3, 'PDI': 4}.get(bidi, 5)
        target.append((start, end, value))
    # General @missing rule first, then its regional overrides, then ALL explicit
    # records. Applying explicit records while reading would lose their priority.
    data = bytearray(CODE_POINTS)
    for start, end, value in missing + explicit:
        data[start:end + 1] = bytes([value]) * (end - start + 1)
    ranges = []
    start = 0
    for end in range(1, CODE_POINTS + 1):
        if end == CODE_POINTS or data[end] != data[start]:
            if data[start] != 0:
                ranges.append((start, end - 1, data[start]))
            start = end
    return ranges


def render(ranges):
    # Normalized digest: uppercase six-digit hex bounds, decimal projection,
    # separated by single spaces; one interval per line, including final LF.
    normalized = ''.join(f'{a:06X} {b:06X} {c}\n' for a, b, c in ranges)
    if hashlib.sha256(normalized.encode('ascii')).hexdigest() != DATA_SHA256:
        raise ValueError('Projected range-data SHA-256 mismatch')
    header = f'''// Generated from Unicode 18.0.0 DerivedBidiClass.txt; do not edit by hand.
// Source: {SOURCE_URI}
// Source SHA-256: {SOURCE_SHA256}
// Projected range-data SHA-256: {DATA_SHA256}
// Projection: default L; 1=R/AL, 2=B, 3=isolate initiator, 4=PDI, 5=other.
// Copyright © 1991-2026 Unicode, Inc.; Unicode License v3 (Unicode-3.0).
// Full required notice is delivered in the app license page and design audit.

// dart format off
const List<int> unicodeBidiClassRanges = <int>[
'''
    return (header + ''.join(f'  0x{a:06X}, 0x{b:06X}, {c},\n'
                             for a, b, c in ranges) + '];\n').encode('utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path, help='local DerivedBidiClass-18.0.0.txt')
    parser.add_argument('--write', action='store_true', help='replace checked-in Dart data')
    args = parser.parse_args()
    source = args.source.read_bytes()
    if hashlib.sha256(source).hexdigest() != SOURCE_SHA256:
        parser.error('Source SHA-256 mismatch; no output written')
    expected = render(project(source.decode('utf-8')))
    if args.write:
        OUTPUT.write_bytes(expected)
    elif OUTPUT.read_bytes() != expected:
        parser.error('Checked-in Dart data differs; regenerate with --write')
    print(f'Unicode 18.0.0 bidi data verified: {DATA_SHA256}')


if __name__ == '__main__':
    main()
