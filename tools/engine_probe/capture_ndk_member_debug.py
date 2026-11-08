"""Capture bounded DWARF metadata for selected NDK libc++ archive members.

This developer-only probe hashes exact selected member bytes in memory and
records sanitized DWARF compile-unit names; temporary object files are deleted
and never included in artifacts. It does not claim
source identity, linked-section provenance, licensing, or redistribution rights.
"""
import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import selectors
import subprocess
import tempfile
import time


ARCHIVE_NAME = 'libc++_static.a'
COMPONENT = 'libcxx'
SHA_RE = re.compile(r'[0-9a-f]{64}')
MEMBER_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9_.+-]*\.o')
CLANG_VERSION_RE = re.compile(r'\bclang version\s+([0-9][A-Za-z0-9.+_-]*)', re.IGNORECASE)
CHUNK_BYTES = 1024 * 1024


def sha256_file(path):
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as stream:
        while True:
            chunk = stream.read(CHUNK_BYTES)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
    return size, digest.hexdigest()


def _safe_relative(value):
    if (not isinstance(value, str) or not value or '\\' in value or
            any(ord(char) < 32 or ord(char) == 127 for char in value)):
        raise ValueError('Archive manifest path is malformed; capture incomplete')
    path = PurePosixPath(value)
    if path.is_absolute() or '..' in path.parts or not path.parts:
        raise ValueError('Archive manifest path is unsafe; capture incomplete')
    return path


def _safe_archive_manifest(path, linker_map, ndk_root, max_members):
    raw = path.read_bytes()
    try:
        manifest = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError('Archive manifest is not valid JSON; capture incomplete') from error
    if not isinstance(manifest, dict) or manifest.get('schema') != 1:
        raise ValueError('Archive manifest schema is unsupported; capture incomplete')
    map_record = manifest.get('link_map')
    if (not isinstance(map_record, dict) or
            not isinstance(map_record.get('size'), int) or isinstance(map_record.get('size'), bool) or
            map_record['size'] <= 0 or
            not SHA_RE.fullmatch(map_record.get('sha256', ''))):
        raise ValueError('Archive manifest link-map binding is malformed; capture incomplete')
    map_size, map_hash = sha256_file(linker_map)
    if (map_size, map_hash) != (map_record['size'], map_record['sha256']):
        raise ValueError('Link-map bytes do not match archive manifest; capture incomplete')

    archives = manifest.get('archives')
    if not isinstance(archives, list):
        raise ValueError('Archive manifest list is malformed; capture incomplete')
    matches = []
    for record in archives:
        if not isinstance(record, dict) or record.get('root') != 'ndk':
            continue
        rel = _safe_relative(record.get('path'))
        if rel.name == ARCHIVE_NAME:
            matches.append((record, rel))
    if len(matches) != 1:
        raise ValueError('Expected exactly one selected libc++ archive; capture incomplete')
    archive, relative = matches[0]
    members = archive.get('members')
    if (not isinstance(members, list) or not members or len(members) > max_members or
            any(not isinstance(member, str) or not MEMBER_RE.fullmatch(member) for member in members) or
            len(set(members)) != len(members)):
        raise ValueError('Selected libc++ member set is malformed or exceeds its configured count')
    if (not isinstance(archive.get('size'), int) or isinstance(archive.get('size'), bool) or
            archive['size'] <= 0 or
            not SHA_RE.fullmatch(archive.get('sha256', ''))):
        raise ValueError('Selected libc++ archive identity is malformed; capture incomplete')

    candidate = ndk_root / Path(*relative.parts)
    if candidate.is_symlink():
        raise ValueError('Selected libc++ archive is a symbolic link; capture incomplete')
    archive_path = candidate.resolve(strict=True)
    try:
        archive_path.relative_to(ndk_root)
    except ValueError as error:
        raise ValueError('Selected libc++ archive escapes NDK root; capture incomplete') from error
    if not archive_path.is_file():
        raise ValueError('Selected libc++ archive is not a regular file; capture incomplete')
    size, digest = sha256_file(archive_path)
    if (size, digest) != (archive['size'], archive['sha256']):
        raise ValueError('Selected libc++ archive digest changed; capture incomplete')
    return raw, map_record, archive, relative, archive_path, sorted(members)


def _run(argv, deadline, max_output_bytes):
    if max_output_bytes < 0:
        raise ValueError('Configured tool-output budget is exhausted')
    remaining = deadline - time.monotonic()
    if not math.isfinite(remaining) or remaining <= 0:
        raise ValueError('NDK member-debug capture exceeded its configured timeout')
    try:
        process = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError as error:
        raise ValueError('NDK archive/debug tool invocation failed; capture incomplete') from error
    try:
        output = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            while True:
                remaining = deadline - time.monotonic()
                if not math.isfinite(remaining) or remaining <= 0:
                    raise ValueError('NDK member-debug capture exceeded its configured timeout')
                if not selector.select(remaining):
                    raise ValueError('NDK member-debug capture exceeded its configured timeout')
                chunk = os.read(process.stdout.fileno(), min(CHUNK_BYTES, max_output_bytes - len(output) + 1))
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > max_output_bytes:
                    raise ValueError('NDK tool output exceeds its configured byte bound')
        remaining = deadline - time.monotonic()
        if not math.isfinite(remaining) or remaining <= 0:
            raise ValueError('NDK member-debug capture exceeded its configured timeout')
        try:
            return_code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            raise ValueError('NDK member-debug capture exceeded its configured timeout') from error
        if return_code != 0:
            raise ValueError('NDK archive/debug tool returned failure; capture incomplete')
        return bytes(output)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()


def _attribute_value(line, attribute):
    if attribute not in line:
        return None
    tail = line.split(attribute, 1)[1].strip()
    if tail.startswith(':'):
        tail = tail[1:].strip()
    indexed = re.search(r'\(indexed string:[^)]*\)\s*:\s*(.*)$', tail)
    if indexed:
        return indexed.group(1).strip()
    quoted = re.search(r'"((?:[^"\\]|\\.)*)"', tail)
    if quoted:
        return quoted.group(1).replace('\\\\', '\\').replace('\\"', '"')
    return tail or None


def parse_compile_units(text):
    """Read only top-level CU attributes; never return raw comp_dir paths."""
    units = []
    current = None
    for line in text.splitlines():
        if 'DW_TAG_compile_unit' in line:
            if current is not None:
                units.append(current)
            current = {'name': None, 'comp_dir': None, 'producer': None}
            continue
        if current is None:
            continue
        if 'DW_TAG_' in line:
            units.append(current)
            current = None
            continue
        for key, attribute in (('producer', 'DW_AT_producer'),
                               ('name', 'DW_AT_name'),
                               ('comp_dir', 'DW_AT_comp_dir')):
            if current[key] is None and attribute in line:
                current[key] = _attribute_value(line, attribute)
    if current is not None:
        units.append(current)
    return units


def _safe_source_path(name, comp_dir):
    if (not isinstance(name, str) or not name or len(name) > 4096 or
            any(ord(char) < 32 or ord(char) == 127 for char in name)):
        return None, 'missing-or-malformed'
    if (comp_dir is not None and
            (not isinstance(comp_dir, str) or len(comp_dir) > 4096 or
             any(ord(char) < 32 or ord(char) == 127 for char in comp_dir))):
        return None, 'missing-or-malformed'
    normalized_name = name.replace('\\', '/')
    normalized_dir = comp_dir.replace('\\', '/') if isinstance(comp_dir, str) else ''
    name_path = PurePosixPath(normalized_name)
    candidate = name_path if name_path.is_absolute() else PurePosixPath(normalized_dir) / name_path
    parts = tuple(part for part in candidate.parts if part not in ('/', '', '.'))
    if COMPONENT in parts:
        start = parts.index(COMPONENT)
        suffix = parts[start:]
        if any(part == '..' for part in suffix):
            return None, 'unmapped'
        return '/'.join(suffix), 'component-relative'
    if not name_path.is_absolute() and all(part not in ('.', '..') for part in name_path.parts):
        return name_path.as_posix(), 'relative-name'
    return None, 'absolute-unmapped'


def _safe_producer(value):
    if (not isinstance(value, str) or not value or len(value) > 1024 or
            any(ord(char) < 32 or ord(char) == 127 for char in value)):
        return None
    match = CLANG_VERSION_RE.search(value)
    if match:
        return 'clang version ' + match.group(1)
    if '/' in value or '\\' in value or re.search(r'[A-Za-z]:', value):
        return 'present-redacted'
    return value[:256]


def _member_record(name, data, readelf_output):
    try:
        text = readelf_output.decode('utf-8', errors='replace')
    except AttributeError as error:
        raise ValueError('Debug tool output is malformed; capture incomplete') from error
    units = parse_compile_units(text)
    safe_units = []
    for unit in units:
        source_path, path_state = _safe_source_path(unit.get('name'), unit.get('comp_dir'))
        raw_name = unit.get('name')
        basename = None
        if (isinstance(raw_name, str) and len(raw_name) <= 4096 and
                not any(ord(char) < 32 or ord(char) == 127 for char in raw_name)):
            candidate_basename = PurePosixPath(raw_name.replace('\\', '/')).name
            if len(candidate_basename) <= 256:
                basename = candidate_basename
        safe_units.append({
            'dwarf_name_path': source_path,
            'dwarf_name_path_state': path_state,
            'dwarf_name_basename': basename,
            'producer_version': _safe_producer(unit.get('producer')),
        })
    return {
        'member': name,
        'size': len(data),
        'sha256': hashlib.sha256(data).hexdigest(),
        'dwarf_state': 'compile-units' if safe_units else 'no-compile-units',
        'compile_units': safe_units,
    }


def capture(*, archive_manifest, linker_map, ndk_root, llvm_ar, llvm_readelf,
            temp_root, max_members, max_object_bytes, max_tool_output_bytes, timeout_seconds):
    if max_members < 1 or max_object_bytes < 1 or max_tool_output_bytes < 1:
        raise ValueError('Configured member capture limits must be positive')
    if not math.isfinite(timeout_seconds) or timeout_seconds <= 0:
        raise ValueError('Member-debug timeout must be finite positive')
    ndk_root = Path(ndk_root).resolve(strict=True)
    if not ndk_root.is_dir():
        raise ValueError('NDK root is not a directory; capture incomplete')
    archive_manifest = Path(archive_manifest)
    linker_map = Path(linker_map)
    manifest_bytes, map_record, archive, relative, archive_path, members = _safe_archive_manifest(
        archive_manifest, linker_map, ndk_root, max_members)
    for tool in (Path(llvm_ar), Path(llvm_readelf)):
        resolved = tool.resolve(strict=True)
        try:
            resolved.relative_to(ndk_root)
        except ValueError as error:
            raise ValueError('Archive/debug tools must be inside the pinned NDK; capture incomplete') from error
        if not resolved.is_file():
            raise ValueError('Archive/debug tool is not a regular file; capture incomplete')
    deadline = time.monotonic() + timeout_seconds
    listing = _run([str(Path(llvm_ar).resolve()), 't', str(archive_path)], deadline,
                   max_tool_output_bytes)
    try:
        listed = listing.decode('utf-8', errors='strict').splitlines()
    except UnicodeDecodeError as error:
        raise ValueError('Archive member listing is not UTF-8; capture incomplete') from error
    duplicates = [name for name, count in Counter(listed).items() if count != 1 and name in members]
    if duplicates:
        raise ValueError('Selected archive member names are ambiguous; capture incomplete')
    for name in members:
        if listed.count(name) != 1:
            raise ValueError('Selected archive member is absent or ambiguous; capture incomplete')

    member_records = []
    total_object_bytes = 0
    total_dwarf_bytes = 0
    total_tool_output_bytes = len(listing)
    with tempfile.TemporaryDirectory(prefix='ndk-member-dwarf-', dir=temp_root) as directory:
        temp = Path(directory)
        for index, name in enumerate(members):
            data = _run([str(Path(llvm_ar).resolve()), 'p', str(archive_path), name], deadline,
                        max_object_bytes - total_object_bytes)
            total_object_bytes += len(data)
            if not data or total_object_bytes > max_object_bytes:
                raise ValueError('Selected member bytes exceed configured bound; capture incomplete')
            object_path = temp / ('member-%04d.o' % index)
            object_path.write_bytes(data)
            dwarf = _run([str(Path(llvm_readelf).resolve()), '--debug-dump=info', str(object_path)],
                         deadline, max_tool_output_bytes - total_tool_output_bytes)
            total_dwarf_bytes += len(dwarf)
            total_tool_output_bytes += len(dwarf)
            if total_tool_output_bytes > max_tool_output_bytes:
                raise ValueError('DWARF output exceeds configured byte bound; capture incomplete')
            member_records.append(_member_record(name, data, dwarf))
            object_path.unlink()
    final_map_size, final_map_hash = sha256_file(linker_map)
    final_archive_size, final_archive_hash = sha256_file(archive_path)
    if ((final_map_size, final_map_hash) != (map_record['size'], map_record['sha256']) or
            (final_archive_size, final_archive_hash) != (archive['size'], archive['sha256'])):
        raise ValueError('Link-map or libc++ archive changed during capture; evidence incomplete')
    return {
        'schema': 1,
        'scope': 'selected libc++_static.a members only; source and licensing closure not established',
        'archive_manifest_sha256': hashlib.sha256(manifest_bytes).hexdigest(),
        'link_map': map_record,
        'archive': {'path': 'ndk/' + relative.as_posix(), 'size': archive['size'],
                    'sha256': archive['sha256']},
        'counts': {'members': len(member_records),
                   'compile_units': sum(len(item['compile_units']) for item in member_records),
                   'members_with_compile_units': sum(item['dwarf_state'] == 'compile-units' for item in member_records),
                   'member_bytes': total_object_bytes, 'dwarf_output_bytes': total_dwarf_bytes,
                   'tool_output_bytes': total_tool_output_bytes},
        'members': member_records,
    }


def positive_int(value):
    try:
        result = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('must be a positive integer') from error
    if result <= 0:
        raise argparse.ArgumentTypeError('must be a positive integer')
    return result


def positive_seconds(value):
    try:
        result = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('must be finite and positive') from error
    if not math.isfinite(result) or result <= 0:
        raise argparse.ArgumentTypeError('must be finite and positive')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive-manifest', type=Path, required=True)
    parser.add_argument('--linker-map', type=Path, required=True)
    parser.add_argument('--ndk-root', type=Path, required=True)
    parser.add_argument('--llvm-ar', type=Path, required=True)
    parser.add_argument('--llvm-readelf', type=Path, required=True)
    parser.add_argument('--temp-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-members', type=positive_int, default=64)
    parser.add_argument('--max-object-bytes', type=positive_int, default=16 * 1024 * 1024)
    parser.add_argument('--max-tool-output-bytes', type=positive_int, default=64 * 1024 * 1024)
    parser.add_argument('--timeout-seconds', type=positive_seconds, default=120)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)
    try:
        manifest = capture(
            archive_manifest=args.archive_manifest, linker_map=args.linker_map,
            ndk_root=args.ndk_root, llvm_ar=args.llvm_ar, llvm_readelf=args.llvm_readelf,
            temp_root=args.temp_root, max_members=args.max_members,
            max_object_bytes=args.max_object_bytes, max_tool_output_bytes=args.max_tool_output_bytes,
            timeout_seconds=args.timeout_seconds)
        text = json.dumps(manifest, sort_keys=True, indent=2) + '\n'
        args.output.write_text(text, encoding='utf-8', newline='\n')
        print('Captured ' + str(manifest['counts']['members']) +
              ' selected libc++ members; ' +
              str(manifest['counts']['members_with_compile_units']) + ' contain DWARF compile units')
    except Exception as error:
        args.output.unlink(missing_ok=True)
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        parser.exit(1, 'NDK member-debug capture failed: ' + detail + '; evidence incomplete\n')


if __name__ == '__main__':
    main()
