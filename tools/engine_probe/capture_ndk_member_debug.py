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
ANSI_ESCAPE_RE = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
PATH_RE = re.compile(
    r'''(?<![A-Za-z0-9_-])(?:[A-Za-z]:[\\/]|[\\/]{1,2}|\.{1,2}[\\/]|[^\s\"'<>:=]+[\\/])[^\s\"'<>]*''')


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


def _safe_tool_diagnostic(data, max_bytes, truncated=False):
    text = data.decode('utf-8', errors='replace')
    text = ANSI_ESCAPE_RE.sub('', text)
    text = PATH_RE.sub('[path]', text)
    text = ''.join(
        ' ' if ord(char) < 32 or 0x7f <= ord(char) <= 0x9f else char
        for char in text)
    text = ' '.join(text.split())
    marker = ' [truncated]'
    encoded = text.encode('utf-8')
    if truncated or len(encoded) > max_bytes:
        marker_bytes = marker.encode('utf-8')
        budget = max(0, max_bytes - len(marker_bytes))
        text = encoded[:budget].decode('utf-8', errors='ignore')
        if max_bytes >= len(marker_bytes):
            text += marker
    return text


def _run(argv, deadline, max_output_bytes, operation, *, capture_stderr=False,
         max_diagnostic_bytes=0):
    if max_output_bytes < 0:
        raise ValueError(operation + ' has no remaining output budget; capture incomplete')
    if capture_stderr and max_diagnostic_bytes < 1:
        raise ValueError(operation + ' has no diagnostic byte budget; capture incomplete')
    remaining = deadline - time.monotonic()
    if not math.isfinite(remaining) or remaining <= 0:
        raise ValueError(operation + ' exceeded its configured timeout')
    try:
        process = subprocess.Popen(
            argv, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE if capture_stderr else subprocess.DEVNULL)
    except OSError as error:
        raise ValueError(operation + ' invocation failed; capture incomplete') from error
    try:
        output = bytearray()
        stderr_output = bytearray()
        stderr_bytes = 0
        output_bytes = 0
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            if capture_stderr:
                selector.register(process.stderr, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if not math.isfinite(remaining) or remaining <= 0:
                    raise ValueError(operation + ' exceeded its configured timeout')
                events = selector.select(remaining)
                if not events:
                    raise ValueError(operation + ' exceeded its configured timeout')
                for key, _ in events:
                    stream = key.fileobj
                    is_stderr = capture_stderr and stream is process.stderr
                    read_size = min(CHUNK_BYTES, max_output_bytes - output_bytes + 1)
                    chunk = os.read(stream.fileno(), read_size)
                    if not chunk:
                        selector.unregister(stream)
                        stream.close()
                        continue
                    output_bytes += len(chunk)
                    if is_stderr:
                        stderr_bytes += len(chunk)
                        remaining_diagnostic = max_diagnostic_bytes - len(stderr_output)
                        if remaining_diagnostic > 0:
                            stderr_output.extend(chunk[:remaining_diagnostic])
                    else:
                        output.extend(chunk)
                    if output_bytes > max_output_bytes:
                        raise ValueError(operation + ' output exceeds its configured byte bound')
        remaining = deadline - time.monotonic()
        if not math.isfinite(remaining) or remaining <= 0:
            raise ValueError(operation + ' exceeded its configured timeout')
        try:
            return_code = process.wait(timeout=remaining)
        except subprocess.TimeoutExpired as error:
            raise ValueError(operation + ' exceeded its configured timeout') from error
        if return_code != 0:
            diagnostic = ''
            if capture_stderr:
                # Keep the existing stderr-first priority while using one strict
                # raw-byte budget across both streams. Only bounded, sanitized
                # diagnostics are returned; raw DWARF output is not retained.
                stderr_kept = bytes(stderr_output[:max_diagnostic_bytes])
                stdout_budget = max_diagnostic_bytes - len(stderr_kept)
                separator = b' ' if stderr_kept and output and stdout_budget else b''
                stdout_budget -= len(separator)
                stdout_kept = bytes(output[:stdout_budget])
                diagnostic_bytes = stderr_kept + separator + stdout_kept
                truncated = (stderr_bytes > len(stderr_kept) or
                             len(output) > len(stdout_kept))
                diagnostic = _safe_tool_diagnostic(
                    diagnostic_bytes, max_diagnostic_bytes, truncated=truncated)
            suffix = '; diagnostic: ' + diagnostic if diagnostic else ''
            raise ValueError(operation + ' returned exit status ' + str(return_code) +
                             suffix + '; capture incomplete')
        if capture_stderr:
            return bytes(output), stderr_bytes
        return bytes(output)
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        process.stdout.close()
        if process.stderr is not None:
            process.stderr.close()


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


def _unescape_dwarf_quoted(value):
    return value.replace('\\"', '"').replace('\\\\', '\\')


def parse_line_tables(data):
    """Extract only line-table versions and safe file/checksum records.

    Consumes LLVM's line-table prologue text. Paths are reduced to a safe
    component-relative or relative name; directory strings and raw DWARF are
    never retained. Empty output means no table was emitted. Nonempty output
    without a recognized prologue, malformed records, or unsupported versions
    fail closed. A checksum only records file bytes for later comparison; it
    does not establish source, patch or binary identity.
    """
    try:
        text = data.decode('utf-8', errors='strict')
    except (AttributeError, UnicodeDecodeError) as error:
        raise ValueError('Line-table output is malformed; capture incomplete') from error
    if '\ufffd' in text:
        raise ValueError('Line-table output contains invalid UTF-8; capture incomplete')
    if text.strip() == '':
        return []

    prologue_re = re.compile(r'\bLine table prologue:\s*$', re.IGNORECASE)
    version_re = re.compile(r'^\s*version\s*:\s*(\d+)\s*$')
    version_like_re = re.compile(r'^\s*version\s*:')
    line_header_re = re.compile(r'^\s*(?:\.debug_line contents:|debug_line\s*\[)', re.IGNORECASE)
    include_dir_re = re.compile(
        r'^\s*include_directories\s*\[\s*(\d+)\s*\]\s*=\s*"((?:[^"\\]|\\.)*)"\s*$')
    include_dir_like_re = re.compile(r'include_directories')
    file_re = re.compile(r'^\s*file_names\s*\[\s*(\d+)\s*\]\s*:\s*$')
    file_like_re = re.compile(r'file_names')
    name_re = re.compile(r'^\s*name\s*:\s*"((?:[^"\\]|\\.)*)"\s*$')
    name_like_re = re.compile(r'^\s*name\s*:')
    dir_index_re = re.compile(r'^\s*dir_index\s*:\s*(\d+)\s*$')
    dir_index_like_re = re.compile(r'\bdir_index\s*:')
    checksum_re = re.compile(
        r'^\s*(?:md5_checksum|md5)\s*:\s*(?:0x)?([0-9A-Fa-f]{32})\s*$')
    checksum_like_re = re.compile(r'\b(?:md5_checksum|md5)\s*:')

    tables = []
    version = None
    prologue_seen = False
    include_dirs = {}
    raw_files = []
    current = None

    def close_current():
        nonlocal current
        if current is None:
            return
        if current.get('raw_name') is None:
            raise ValueError('Line-table file name is missing; capture incomplete')
        raw_files.append(current)
        current = None

    def close_table():
        nonlocal version, prologue_seen, include_dirs, raw_files, current, tables
        if current is not None:
            close_current()
        has_table_data = prologue_seen or version is not None or raw_files or include_dirs
        if has_table_data:
            if not prologue_seen or version is None:
                raise ValueError('Line-table prologue or version is missing; capture incomplete')
            if version not in (2, 3, 4, 5):
                raise ValueError('Unsupported line-table version; capture incomplete')
            directory_base = 0 if version >= 5 else 1
            expected_dirs = list(range(directory_base, directory_base + len(include_dirs)))
            if sorted(include_dirs) != expected_dirs:
                raise ValueError('Line-table directory indexes are malformed; capture incomplete')
            file_indexes = [entry['file_index'] for entry in raw_files]
            if any(index is None for index in file_indexes) and any(
                    index is not None for index in file_indexes):
                raise ValueError('Line-table file indexes are incomplete; capture incomplete')
            if file_indexes and not any(index is None for index in file_indexes):
                file_base = 0 if version >= 5 else 1
                if file_indexes != list(range(file_base, file_base + len(file_indexes))):
                    raise ValueError('Line-table file indexes are malformed; capture incomplete')
            resolved = []
            for raw in raw_files:
                raw_name = raw['raw_name']
                name_path = PurePosixPath(raw_name.replace('\\', '/'))
                directory = None
                index = raw.get('dir_index')
                if index is not None and not name_path.is_absolute():
                    if version < 5 and index == 0:
                        # DWARF v2-v4 use zero for the compilation directory.
                        # It is unavailable here, so retain only the relative name.
                        directory = None
                    elif index in include_dirs:
                        directory = include_dirs[index]
                    else:
                        raise ValueError(
                            'Line-table directory index is out of range; capture incomplete')
                safe, state = _safe_source_path(raw_name, directory)
                resolved.append({
                    'source_path': safe,
                    'source_path_state': state,
                    'md5': raw.get('md5'),
                    'md5_state': raw.get('md5_state', 'unavailable'),
                })
            tables.append({'version': version, 'files': resolved})
        version = None
        prologue_seen = False
        include_dirs = {}
        raw_files = []
        current = None

    for line in text.splitlines():
        if line_header_re.search(line):
            if version is not None or raw_files or include_dirs or current is not None:
                close_table()
            continue
        if prologue_re.search(line):
            if version is not None or raw_files or include_dirs or current is not None:
                close_table()
            prologue_seen = True
            continue
        match = version_re.fullmatch(line)
        if match:
            if version is not None or raw_files or include_dirs or current is not None:
                close_table()
            if not prologue_seen:
                raise ValueError('Line-table version precedes its prologue; capture incomplete')
            version = int(match.group(1))
            if version not in (2, 3, 4, 5):
                raise ValueError('Unsupported line-table version; capture incomplete')
            continue
        if version_like_re.match(line):
            raise ValueError('Malformed line-table version; capture incomplete')
        if include_dir_like_re.search(line):
            match = include_dir_re.fullmatch(line)
            if not match or version is None or current is not None or raw_files:
                raise ValueError('Malformed line-table directory record; capture incomplete')
            index = int(match.group(1))
            base = 0 if version >= 5 else 1
            if index != base + len(include_dirs):
                raise ValueError('Line-table directory indexes are malformed; capture incomplete')
            value = _unescape_dwarf_quoted(match.group(2))
            if (len(value) > 4096 or
                    any(ord(char) < 32 or ord(char) == 127 for char in value)):
                raise ValueError('Malformed line-table directory path; capture incomplete')
            include_dirs[index] = value
            continue
        if file_like_re.search(line):
            match = file_re.fullmatch(line)
            if not match or version is None:
                raise ValueError('Malformed line-table file record; capture incomplete')
            if current is not None:
                close_current()
            file_index = int(match.group(1))
            expected = (0 if version >= 5 else 1) + len(raw_files)
            if file_index != expected:
                raise ValueError('Line-table file indexes are malformed; capture incomplete')
            current = {'file_index': file_index, 'raw_name': None, 'dir_index': None,
                       'md5': None, 'md5_state': 'unavailable'}
            continue
        name_match = name_re.fullmatch(line)
        if name_match is not None:
            if current is None:
                raise ValueError('Line-table file name has no file record; capture incomplete')
            if current.get('raw_name') is not None:
                raise ValueError('Duplicate line-table file name; capture incomplete')
            current['raw_name'] = _unescape_dwarf_quoted(name_match.group(1))
            continue
        if name_like_re.match(line):
            raise ValueError('Malformed line-table file name; capture incomplete')
        if dir_index_like_re.search(line):
            match = dir_index_re.fullmatch(line)
            if not match:
                raise ValueError('Malformed line-table directory index; capture incomplete')
            if current is None or current.get('raw_name') is None:
                raise ValueError('Line-table directory index has no source path; capture incomplete')
            if current.get('dir_index') is not None:
                raise ValueError('Duplicate line-table directory index; capture incomplete')
            current['dir_index'] = int(match.group(1))
            continue
        if checksum_like_re.search(line):
            match = checksum_re.fullmatch(line)
            if not match:
                raise ValueError('Malformed line-table checksum; capture incomplete')
            if current is None or current.get('raw_name') is None:
                raise ValueError('Line-table checksum has no source path; capture incomplete')
            if current['md5'] is not None:
                raise ValueError('Duplicate line-table checksum; capture incomplete')
            current['md5'] = match.group(1).lower()
            current['md5_state'] = 'present'
    close_table()
    if not tables:
        raise ValueError('Line-table output is unrecognized; capture incomplete')
    return tables


def _member_record(name, data, dwarfdump_output, line_table_output=b''):
    try:
        text = dwarfdump_output.decode('utf-8', errors='replace')
    except AttributeError as error:
        raise ValueError('Debug tool output is malformed; capture incomplete') from error
    units = parse_compile_units(text)
    line_tables = parse_line_tables(line_table_output)
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
        'line_table_state': 'tables' if line_tables else 'no-line-table-output',
        'line_tables': line_tables,
    }


def capture(*, archive_manifest, linker_map, ndk_root, llvm_ar, llvm_dwarfdump,
            temp_root, max_members, max_object_bytes, max_tool_output_bytes,
            max_line_table_output_bytes, max_diagnostic_bytes=8192, timeout_seconds=120):
    if (max_members < 1 or max_object_bytes < 1 or max_tool_output_bytes < 1 or
            max_diagnostic_bytes < 1 or max_line_table_output_bytes < 1):
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
    for tool in (Path(llvm_ar), Path(llvm_dwarfdump)):
        resolved = tool.resolve(strict=True)
        try:
            resolved.relative_to(ndk_root)
        except ValueError as error:
            raise ValueError('Archive/debug tools must be inside the pinned NDK; capture incomplete') from error
        if not resolved.is_file():
            raise ValueError('Archive/debug tool is not a regular file; capture incomplete')
    deadline = time.monotonic() + timeout_seconds
    listing = _run([str(Path(llvm_ar).resolve()), 't', str(archive_path)], deadline,
                   max_tool_output_bytes, 'llvm-ar selected-member listing')
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
    total_line_output_bytes = 0
    with tempfile.TemporaryDirectory(prefix='ndk-member-dwarf-', dir=temp_root) as directory:
        temp = Path(directory)
        for index, name in enumerate(members):
            data = _run([str(Path(llvm_ar).resolve()), 'p', str(archive_path), name], deadline,
                        max_object_bytes - total_object_bytes, 'llvm-ar extraction for ' + name)
            total_object_bytes += len(data)
            if not data or total_object_bytes > max_object_bytes:
                raise ValueError('Selected member bytes exceed configured bound; capture incomplete')
            object_path = temp / ('member-%04d.o' % index)
            object_path.write_bytes(data)
            dwarf, diagnostic_bytes = _run(
                [str(Path(llvm_dwarfdump).resolve()), '--debug-info', str(object_path)],
                deadline, max_tool_output_bytes - total_tool_output_bytes,
                'llvm-dwarfdump DWARF scan for ' + name, capture_stderr=True,
                max_diagnostic_bytes=max_diagnostic_bytes)
            total_dwarf_bytes += len(dwarf)
            total_tool_output_bytes += len(dwarf) + diagnostic_bytes
            if total_tool_output_bytes > max_tool_output_bytes:
                raise ValueError('DWARF output exceeds configured byte bound; capture incomplete')
            line_table, line_diagnostic_bytes = _run(
                [str(Path(llvm_dwarfdump).resolve()), '--debug-line', str(object_path)],
                deadline, max_line_table_output_bytes - total_line_output_bytes,
                'llvm-dwarfdump line-table scan for ' + name, capture_stderr=True,
                max_diagnostic_bytes=max_diagnostic_bytes)
            total_line_output_bytes += len(line_table) + line_diagnostic_bytes
            if total_tool_output_bytes + total_line_output_bytes > max_tool_output_bytes + max_line_table_output_bytes:
                raise ValueError('Aggregate tool output exceeds its configured byte bound; capture incomplete')
            if total_line_output_bytes > max_line_table_output_bytes:
                raise ValueError('Line-table output exceeds its configured byte bound; capture incomplete')
            member_records.append(_member_record(name, data, dwarf, line_table))
            object_path.unlink()
    final_map_size, final_map_hash = sha256_file(linker_map)
    final_archive_size, final_archive_hash = sha256_file(archive_path)
    if ((final_map_size, final_map_hash) != (map_record['size'], map_record['sha256']) or
            (final_archive_size, final_archive_hash) != (archive['size'], archive['sha256'])):
        raise ValueError('Link-map or libc++ archive changed during capture; evidence incomplete')
    return {
        'schema': 2,
        'scope': 'selected libc++_static.a members only; source and licensing closure not established',
        'archive_manifest_sha256': hashlib.sha256(manifest_bytes).hexdigest(),
        'link_map': map_record,
        'archive': {'path': 'ndk/' + relative.as_posix(), 'size': archive['size'],
                    'sha256': archive['sha256']},
        'counts': {'members': len(member_records),
                   'compile_units': sum(len(item['compile_units']) for item in member_records),
                   'members_with_compile_units': sum(item['dwarf_state'] == 'compile-units' for item in member_records),
                   'members_with_line_tables': sum(bool(item['line_tables']) for item in member_records),
                   'line_table_files': sum(len(table['files']) for item in member_records
                                           for table in item['line_tables']),
                   'line_table_files_with_md5': sum(
                       file['md5_state'] == 'present' for item in member_records
                       for table in item['line_tables'] for file in table['files']),
                   'member_bytes': total_object_bytes, 'dwarf_output_bytes': total_dwarf_bytes,
                   'tool_output_bytes': total_tool_output_bytes,
                   'line_table_output_bytes': total_line_output_bytes},
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
    parser.add_argument('--llvm-dwarfdump', type=Path, required=True)
    parser.add_argument('--temp-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--max-members', type=positive_int, default=64)
    parser.add_argument('--max-object-bytes', type=positive_int, default=16 * 1024 * 1024)
    parser.add_argument('--max-tool-output-bytes', type=positive_int, default=64 * 1024 * 1024)
    parser.add_argument('--max-diagnostic-bytes', type=positive_int, default=8192)
    parser.add_argument('--max-line-table-output-bytes', type=positive_int, required=True)
    parser.add_argument('--timeout-seconds', type=positive_seconds, default=120)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.unlink(missing_ok=True)
    try:
        manifest = capture(
            archive_manifest=args.archive_manifest, linker_map=args.linker_map,
            ndk_root=args.ndk_root, llvm_ar=args.llvm_ar, llvm_dwarfdump=args.llvm_dwarfdump,
            temp_root=args.temp_root, max_members=args.max_members,
            max_object_bytes=args.max_object_bytes, max_tool_output_bytes=args.max_tool_output_bytes,
            max_diagnostic_bytes=args.max_diagnostic_bytes,
            max_line_table_output_bytes=args.max_line_table_output_bytes,
            timeout_seconds=args.timeout_seconds)
        text = json.dumps(manifest, sort_keys=True, indent=2) + '\n'
        args.output.write_text(text, encoding='utf-8', newline='\n')
        print('Captured ' + str(manifest['counts']['members']) +
              ' selected libc++ members; ' +
              str(manifest['counts']['members_with_compile_units']) + ' contain DWARF compile units; ' +
              str(manifest['counts']['members_with_line_tables']) + ' have line tables with ' +
              str(manifest['counts']['line_table_files_with_md5']) + ' file checksums')
    except Exception as error:
        args.output.unlink(missing_ok=True)
        detail = str(error) if isinstance(error, ValueError) else type(error).__name__
        parser.exit(1, 'NDK member-debug capture failed: ' + detail + '; evidence incomplete\n')


if __name__ == '__main__':
    main()
