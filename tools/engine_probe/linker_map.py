"""Validate Android LLD maps and publish bounded archive/section metadata."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import tempfile


_ARCHIVE_MEMBER = re.compile(r'(?P<archive>[^()\r\n]*\.a)\((?P<member>[^)\r\n]+)\)')
_MAP_ROW = re.compile(r'^\s*\S+\s+\S+\s+\S+\s+\S+\s+(?P<rest>.*)$')
_MAP_HEX = re.compile(r'(?:0[xX])?[0-9a-fA-F]+\Z')
_MAP_ALIGN = re.compile(r'[0-9]+\Z')
_SECTION_NAME = re.compile(r'\.[A-Za-z0-9_.$+-]+\Z')
_MEMBER_NAME = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.+-]*\.o\Z')
_CHUNK_BYTES = 1024 * 1024


def _sha256_file(path):
    before = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(before.st_mode):
        raise RuntimeError(f'not a regular archive file: {path.name}')
    flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
    fd = os.open(path, flags)
    try:
        stream = os.fdopen(fd, 'rb')
    except BaseException:
        os.close(fd)
        raise
    digest = hashlib.sha256()
    observed = 0
    with stream:
        opened = os.fstat(stream.fileno())
        if (opened.st_dev, opened.st_ino) != (before.st_dev, before.st_ino):
            raise RuntimeError(f'archive changed while opening: {path.name}')
        while True:
            chunk = stream.read(_CHUNK_BYTES)
            if not chunk:
                break
            observed += len(chunk)
            digest.update(chunk)
        after = os.fstat(stream.fileno())
    if (observed != before.st_size or after.st_size != before.st_size or
            (before.st_dev, before.st_ino, before.st_mtime_ns) !=
            (after.st_dev, after.st_ino, after.st_mtime_ns)):
        raise RuntimeError(f'archive changed while hashing: {path.name}')
    return observed, digest.hexdigest()


def _archive_location(raw_path, build_root, ndk_root):
    supplied = Path(raw_path)
    if '..' in supplied.parts:
        raise RuntimeError('linker map archive path contains parent traversal')
    path = supplied if supplied.is_absolute() else build_root / supplied
    try:
        resolved = path.resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise RuntimeError(f'linker map archive is missing: {raw_path}') from exc
    for root_name, root in (('build', build_root), ('ndk', ndk_root)):
        try:
            relative = resolved.relative_to(root)
        except ValueError:
            continue
        if not relative.parts:
            break
        return root_name, relative.as_posix()
    raise RuntimeError(f'linker map archive escapes configured roots: {raw_path}')


def _map_integer(value, base, description, line_number):
    if not isinstance(value, str) or not value or len(value) > 18:
        raise RuntimeError(f'malformed {description} on map line {line_number}')
    try:
        result = int(value, base)
    except ValueError as exc:
        raise RuntimeError(f'malformed {description} on map line {line_number}') from exc
    if result < 0 or result > ((1 << 64) - 1):
        raise RuntimeError(f'out-of-range {description} on map line {line_number}')
    return result


def _parse_archive_members(stream, build_root, ndk_root, max_bytes):
    digest = hashlib.sha256()
    observed = 0
    members_by_archive = {}
    contributions_by_archive = {}
    current_output_section = None
    current_output_end = 0
    for line_number, raw_line in enumerate(stream, 1):
        observed += len(raw_line)
        if observed > max_bytes:
            raise RuntimeError(f'linker map exceeds configured byte bound ({observed} > {max_bytes})')
        digest.update(raw_line)
        line = raw_line.decode('utf-8')
        row = _MAP_ROW.match(line)
        fields = line.split(None, 4) if row else []
        if len(fields) == 5 and '.a(' not in line:
            vma, _, size, _, rest = fields
            rest = rest.strip()
            if (_SECTION_NAME.fullmatch(rest) and not rest.startswith('.L') and
                    _MAP_HEX.fullmatch(vma) and _MAP_HEX.fullmatch(size)):
                section_start = _map_integer(vma, 16, 'section VMA', line_number)
                section_size = _map_integer(size, 16, 'section size', line_number)
                if section_size > 0 and section_start >= current_output_end:
                    current_output_section = rest
                    current_output_end = section_start + section_size
        if '.a(' not in line:
            continue
        if not row or len(fields) != 5:
            raise RuntimeError(f'unrecognized archive row on map line {line_number}')
        archive_text = row.group('rest').lstrip()
        output_section = None
        columns = archive_text.split(None, 1)
        if (len(columns) == 2 and columns[0].startswith('.') and
                '/' not in columns[0] and '\\' not in columns[0] and
                '.a(' not in columns[0] and '.a(' in columns[1]):
            # LLD may show the output section before the input archive path.
            output_section = columns[0]
            current_output_section = output_section
            if _MAP_HEX.fullmatch(fields[0]) and _MAP_HEX.fullmatch(fields[2]):
                current_output_end = max(
                    current_output_end,
                    _map_integer(fields[0], 16, 'contribution VMA', line_number) +
                    _map_integer(fields[2], 16, 'contribution size', line_number))
            archive_text = columns[1]
        matches = list(_ARCHIVE_MEMBER.finditer(archive_text))
        if not matches:
            raise RuntimeError(f'unrecognized archive row on map line {line_number}')
        for match in matches:
            raw_path = match.group('archive').strip()
            member = match.group('member')
            if not member:
                raise RuntimeError(f'empty archive member on map line {line_number}')
            root_name, relative = _archive_location(raw_path, build_root, ndk_root)
            key = (root_name, relative)
            members_by_archive.setdefault(key, set()).add(member)
            if root_name != 'ndk' or Path(relative).name != 'libc++_static.a':
                continue
            if len(matches) != 1:
                raise RuntimeError(f'ambiguous libc++ contribution on map line {line_number}')
            if not _MEMBER_NAME.fullmatch(member):
                raise RuntimeError(f'malformed libc++ member on map line {line_number}')
            vma_value, lma_value, size_value, align_value, _ = fields
            if not (_MAP_HEX.fullmatch(vma_value) and _MAP_HEX.fullmatch(lma_value) and
                    _MAP_HEX.fullmatch(size_value) and _MAP_ALIGN.fullmatch(align_value)):
                raise RuntimeError(f'malformed libc++ address/size/alignment on map line {line_number}')
            vma_number = _map_integer(vma_value, 16, 'VMA', line_number)
            lma_number = _map_integer(lma_value, 16, 'LMA', line_number)
            size_number = _map_integer(size_value, 16, 'contribution size', line_number)
            align_number = _map_integer(align_value, 10, 'alignment', line_number)
            tail = archive_text[match.end():]
            section_match = re.match(r'\s*:\s*\(([^)\r\n]+)\)', tail)
            if not section_match:
                raise RuntimeError(f'missing libc++ input section on map line {line_number}')
            input_section = section_match.group(1)
            mapped_output_section = output_section or current_output_section
            if (not mapped_output_section or
                    not _SECTION_NAME.fullmatch(mapped_output_section) or
                    mapped_output_section.startswith('.L') or
                    not _SECTION_NAME.fullmatch(input_section)):
                raise RuntimeError(f'missing or malformed libc++ section mapping on map line {line_number}')
            if vma_number + size_number > (1 << 64) or lma_number + size_number > (1 << 64):
                raise RuntimeError(f'libc++ contribution range overflows on map line {line_number}')
            contributions_by_archive.setdefault(key, []).append({
                'line': line_number,
                'member': member,
                'output_section': mapped_output_section,
                'input_section': input_section,
                'vma': '0x' + format(vma_number, 'x'),
                'lma': '0x' + format(lma_number, 'x'),
                'size_bytes': size_number,
                'align_bytes': align_number,
            })
    if observed == 0:
        raise RuntimeError('linker map is empty')
    if not members_by_archive:
        raise RuntimeError('linker map contains no archive-member rows')
    return observed, digest.hexdigest(), members_by_archive, contributions_by_archive

def _linked_archives(members_by_archive, build_root, ndk_root, map_size, map_sha256):
    archives = []
    for (root_name, relative), members in sorted(members_by_archive.items()):
        archive_path = (build_root if root_name == 'build' else ndk_root) / relative
        archive_path = archive_path.resolve(strict=True)
        size, digest = _sha256_file(archive_path)
        archives.append({
            'root': root_name,
            'path': relative,
            'size': size,
            'sha256': digest,
            'members': sorted(members),
        })
    return {
        'schema': 1,
        'link_map': {'size': map_size, 'sha256': map_sha256},
        'archives': archives,
    }


def record(path, max_bytes, output_dir, build_root, ndk_root):
    path = Path(path)
    output_dir = Path(output_dir)
    build_root = Path(build_root).resolve(strict=True)
    ndk_root = Path(ndk_root).resolve(strict=True)
    if (not build_root.is_dir() or not ndk_root.is_dir() or build_root == ndk_root or
            build_root in ndk_root.parents or ndk_root in build_root.parents):
        raise ValueError('build and NDK roots must be distinct, non-overlapping existing directories')
    if isinstance(max_bytes, bool) or not isinstance(max_bytes, int) or max_bytes <= 0:
        raise ValueError('map byte bound must be a positive integer')
    if path.is_symlink() or not path.is_file():
        raise RuntimeError('linker map is missing or not a regular file')
    map_parent = path.parent.resolve(strict=True)
    try:
        map_parent.relative_to(build_root)
    except ValueError as exc:
        raise ValueError('linker map must be inside the configured build root') from exc
    if map_parent != output_dir.parent.resolve(strict=True):
        raise ValueError('validated map directory must be beside the unvalidated map')
    if output_dir.exists() or output_dir.is_symlink():
        raise RuntimeError('validated map directory already exists')
    size = path.stat().st_size
    if size == 0:
        raise RuntimeError('linker map is empty')
    if size > max_bytes:
        raise RuntimeError(f'linker map exceeds configured byte bound ({size} > {max_bytes})')

    # Keep raw output and partially prepared evidence outside the workflow's
    # validated-map upload path. Publish the map, digest and archive inventory
    # together with one same-filesystem directory rename after every check.
    staging = Path(tempfile.mkdtemp(prefix='.linker-map-', dir=path.parent))
    try:
        staged_map = staging / 'llama-simple.map'
        os.replace(path, staged_map)
        before = staged_map.stat(follow_symlinks=False)
        if not stat.S_ISREG(before.st_mode):
            raise RuntimeError('linker map is not a regular file')

        with staged_map.open('rb') as stream:
            opened = os.fstat(stream.fileno())
            observed, map_sha256, members_by_archive, contributions_by_archive = _parse_archive_members(
                stream, build_root, ndk_root, max_bytes)
            after = os.fstat(stream.fileno())
        if (observed != size or after.st_size != size or
                (before.st_dev, before.st_ino, before.st_mtime_ns) !=
                (opened.st_dev, opened.st_ino, opened.st_mtime_ns) or
                (opened.st_dev, opened.st_ino, opened.st_mtime_ns) !=
                (after.st_dev, after.st_ino, after.st_mtime_ns)):
            raise RuntimeError('linker map changed while being recorded')

        map_record = {'size': observed, 'sha256': map_sha256}
        archive_record = _linked_archives(
            members_by_archive, build_root, ndk_root, observed, map_sha256)
        libcxx_archives = [archive for archive in archive_record['archives']
                           if archive['root'] == 'ndk' and
                           Path(archive['path']).name == 'libc++_static.a']
        if len(libcxx_archives) != 1:
            raise RuntimeError('expected exactly one selected NDK libc++ archive')
        libcxx_archive = libcxx_archives[0]
        archive_key = (libcxx_archive['root'], libcxx_archive['path'])
        contributions = contributions_by_archive.get(archive_key, [])
        mapped_members = {item['member'] for item in contributions}
        if set(libcxx_archive['members']) != mapped_members:
            raise RuntimeError('libc++ selected members do not have complete section mappings')
        contribution_record = {
            'schema': 1,
            'scope': 'link-map input-section contributions for selected libc++_static.a members; no archive-member objects retained',
            'link_map': map_record,
            'archive': {
                'path': 'ndk/' + libcxx_archive['path'],
                'size': libcxx_archive['size'],
                'sha256': libcxx_archive['sha256'],
            },
            'counts': {
                'members': len(libcxx_archive['members']),
                'members_with_contributions': len(mapped_members),
                'contributions': len(contributions),
            },
            'contributions': contributions,
        }
        contribution_bytes = (json.dumps(contribution_record, sort_keys=True, indent=2) + '\n').encode('utf-8')
        if len(contribution_bytes) > max_bytes:
            raise RuntimeError('libc++ contribution metadata exceeds configured linker-map byte bound')
        (staging / 'llama-simple.map.sha256.json').write_text(
            json.dumps(map_record, sort_keys=True) + '\n', encoding='utf-8')
        (staging / 'llama-simple.map.archives.json').write_text(
            json.dumps(archive_record, sort_keys=True, indent=2) + '\n', encoding='utf-8')
        (staging / 'llama-simple.map.contributions.json').write_bytes(contribution_bytes)
        os.rename(staging, output_dir)
        staging = None
        return map_record
    finally:
        if staging is not None:
            shutil.rmtree(staging)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', type=Path)
    parser.add_argument('--max-bytes', required=True, type=int)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--build-root', required=True, type=Path)
    parser.add_argument('--ndk-root', required=True, type=Path)
    args = parser.parse_args()
    record(args.path, args.max_bytes, args.output_dir, args.build_root, args.ndk_root)


if __name__ == '__main__':
    main()
