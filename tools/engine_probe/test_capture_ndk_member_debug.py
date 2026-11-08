import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest

import capture_ndk_member_debug as capture


DWARF = b''' <0> DW_TAG_compile_unit
    <1> DW_AT_producer : (indexed string: 0): clang version 19.0.1 (/private/build)
    <2> DW_AT_name : (indexed string: 1): src/regex.cpp
    <3> DW_AT_comp_dir : (indexed string: 2): /home/runner/work/llvm-project/libcxx
    <4> DW_TAG_subprogram
      <5> DW_AT_name : (indexed string: 3): selected_member
'''


# Realistic LLVM 19 DWARFDebugLine::Prologue::dump text: include directories,
# file_names with name/dir_index/md5_checksum. The first file resolves through
# its directory to a component-relative libcxx path with a checksum; the second
# has no checksum and its directory carries no libcxx component, so only the
# basename is retained. Absolute directory strings must never appear in output.
LINE_TABLE_V19 = b'''debug_line[0x00000000]
Line table prologue:
    total_length: 0x00000123
    version: 5
    address_size: 8
    seg_select_size: 0
    prologue_length: 0x000000ab
    min_inst_length: 1
    max_ops_per_inst: 1
    default_is_stmt: 1
    line_base: -5
    line_range: 14
    opcode_base: 13
    standard_opcode_lengths[1] = 0
    standard_opcode_lengths[2] = 1
    include_directories[  0] = "/home/runner/work/llvm-project/libcxx/src"
    include_directories[  1] = "/home/runner/work/llvm-project/include"
    file_names[  0]:
               name: "regex.cpp"
               dir_index: 0
               mod_time: 0x00000000
               length: 0x00000000
               md5_checksum: 0123456789abcdef0123456789ABCDEF
    file_names[  1]:
               name: "secret.cpp"
               dir_index: 1
               mod_time: 0x00000000
               length: 0x00000000
'''


def digest(value):
    return hashlib.sha256(value).hexdigest()


def line_table(version, rows='', *, include_version=True):
    header = 'debug_line[0x00000000]\nLine table prologue:\n'
    if include_version:
        header += '    version: ' + str(version) + '\n'
    return (header + rows).encode('utf-8')


class CaptureMemberDebugTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.ndk = self.root / 'ndk'
        self.bindir = self.ndk / 'toolchains' / 'llvm' / 'bin'
        self.bindir.mkdir(parents=True)
        self.ar = self.bindir / 'llvm-ar'
        self.dwarfdump = self.bindir / 'llvm-dwarfdump'
        self.listing = self.root / 'members.txt'
        self.object_dir = self.root / 'objects'
        self.object_dir.mkdir()
        self.dwarf_file = self.root / 'dwarf.txt'
        self.line_file = self.root / 'line.txt'
        self.archive = self.ndk / 'sysroot' / 'usr' / 'lib' / 'x86_64-linux-android' / 'libc++_static.a'
        self.archive.parent.mkdir(parents=True)
        self.archive_bytes = b'exact synthetic archive bytes'
        self.archive.write_bytes(self.archive_bytes)
        self.map = self.root / 'llama-simple.map'
        self.map.write_bytes(b'exact linker map bytes')
        self.archive_manifest = self.root / 'archives.json'
        self.members = ['regex.cpp.o', 'algorithm.cpp.o']
        self.object_bytes = {name: ('synthetic object:' + name).encode() for name in self.members}
        self.listing.write_bytes(('\n'.join(self.members) + '\n').encode())
        for name, data in self.object_bytes.items():
            (self.object_dir / name).write_bytes(data)
        self.dwarf_file.write_bytes(DWARF)
        self.line_file.write_bytes(LINE_TABLE_V19)
        ar_script = (
            '#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n'
            'args=sys.argv[1:]\n'
            'target=Path(' + repr(str(self.listing)) + ') if args[0] == "t" else '
            'Path(' + repr(str(self.object_dir)) + ').joinpath(args[2])\n'
            'sys.stdout.buffer.write(target.read_bytes())\n'
        )
        self.tool_args = self.root / 'dwarfdump-args.json'
        self.tool_calls = self.root / 'dwarfdump-calls.jsonl'
        self.tool_calls.write_text('', encoding='utf-8')
        dwarfdump_script = (
            '#!/usr/bin/env python3\nimport json,sys\nfrom pathlib import Path\n'
            'args=sys.argv[1:]\n'
            'if len(args) != 2 or args[0] not in ("--debug-info", "--debug-line"):\n'
            ' sys.stderr.write("unsupported llvm-dwarfdump invocation\\n"); sys.exit(2)\n'
            'Path(' + repr(str(self.tool_args)) + ').write_text(json.dumps(args), encoding="utf-8")\n'
            'open(' + repr(str(self.tool_calls)) + ', "a").write(json.dumps(args) + "\\n")\n'
            'src=Path(' + repr(str(self.dwarf_file)) + ') if args[0] == "--debug-info" else Path(' + repr(str(self.line_file)) + ')\n'
            'sys.stdout.buffer.write(src.read_bytes())\n'
        )
        self.ar.write_text(ar_script, encoding='utf-8')
        self.dwarfdump.write_text(dwarfdump_script, encoding='utf-8')
        self.ar.chmod(0o755)
        self.dwarfdump.chmod(0o755)
        self.write_manifest()

    def tearDown(self):
        self.temp.cleanup()

    def write_manifest(self, *, path=None):
        record_path = path or 'sysroot/usr/lib/x86_64-linux-android/libc++_static.a'
        data = {
            'schema': 1,
            'link_map': {'size': self.map.stat().st_size, 'sha256': digest(self.map.read_bytes())},
            'archives': [{
                'root': 'ndk', 'path': record_path, 'size': len(self.archive_bytes),
                'sha256': digest(self.archive_bytes), 'members': self.members,
            }],
        }
        self.archive_manifest.write_text(json.dumps(data), encoding='utf-8')

    def run_capture(self, **overrides):
        args = {
            'archive_manifest': self.archive_manifest,
            'linker_map': self.map,
            'ndk_root': self.ndk,
            'llvm_ar': self.ar,
            'llvm_dwarfdump': self.dwarfdump,
            'temp_root': self.root,
            'max_members': 64,
            'max_object_bytes': 1024,
            'max_tool_output_bytes': 1024 * 1024,
            'max_diagnostic_bytes': 8192,
            'max_line_table_output_bytes': 1024 * 1024,
            'timeout_seconds': 5,
        }
        args.update(overrides)
        return capture.capture(**args)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_hashes_selected_members_and_sanitizes_compile_unit_paths(self):
        result = self.run_capture()
        self.assertEqual(result['link_map']['sha256'], digest(self.map.read_bytes()))
        self.assertEqual(result['archive']['sha256'], digest(self.archive_bytes))
        self.assertEqual(result['schema'], 2)
        self.assertEqual(result['counts']['members'], 2)
        self.assertEqual(result['counts']['members_with_line_tables'], 2)
        self.assertEqual(result['counts']['line_table_files_with_md5'], 2)
        self.assertTrue(all(item['line_table_state'] == 'tables' for item in result['members']))
        unit = result['members'][0]['compile_units'][0]
        self.assertEqual(unit['dwarf_name_path'], 'libcxx/src/regex.cpp')
        self.assertEqual(unit['dwarf_name_path_state'], 'component-relative')
        self.assertEqual(unit['dwarf_name_basename'], 'regex.cpp')
        self.assertEqual(unit['producer_version'], 'clang version 19.0.1')
        tables = result['members'][0]['line_tables']
        self.assertEqual(tables[0]['version'], 5)
        self.assertEqual(tables[0]['files'][0]['source_path'], 'libcxx/src/regex.cpp')
        self.assertEqual(tables[0]['files'][0]['source_path_state'], 'component-relative')
        self.assertEqual(tables[0]['files'][0]['md5'], '0123456789abcdef0123456789abcdef')
        self.assertEqual(tables[0]['files'][0]['md5_state'], 'present')
        self.assertEqual(tables[0]['files'][1]['source_path'], 'secret.cpp')
        self.assertEqual(tables[0]['files'][1]['md5_state'], 'unavailable')
        encoded = json.dumps(result)
        self.assertNotIn('/home/runner', encoded)
        self.assertNotIn('/private/build', encoded)
        self.assertNotIn('synthetic object:', encoded)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_uses_llvm_dwarfdump_for_info_and_line_tables(self):
        self.run_capture()
        calls = [json.loads(line) for line in self.tool_calls.read_text(encoding='utf-8').splitlines()]
        self.assertEqual(len(calls), 4)
        for index, member in enumerate(self.members):
            info_args, line_args = calls[2 * index], calls[2 * index + 1]
            self.assertEqual(info_args[0], '--debug-info')
            self.assertEqual(line_args[0], '--debug-line')
            self.assertEqual(len(info_args), 2)
            self.assertEqual(len(line_args), 2)
            self.assertFalse(Path(info_args[1]).exists())
            self.assertFalse(Path(line_args[1]).exists())
        args = json.loads(self.tool_args.read_text(encoding='utf-8'))
        self.assertEqual(args[0], '--debug-line')
        self.assertEqual(len(args), 2)
        self.assertFalse(Path(args[1]).exists())

    def test_llvm_dwarfdump_indexed_strings_are_extracted_without_form_text(self):
        text = '''0x00000000: DW_TAG_compile_unit
  DW_AT_producer [DW_FORM_strx1] (indexed (00000000) string = "clang version 19.0.1 (/private/build)")
  DW_AT_name [DW_FORM_strx1] (indexed (00000001) string = "src/regex.cpp")
  DW_AT_comp_dir [DW_FORM_strx1] (indexed (00000002) string = "/home/runner/llvm-project/libcxx")
  DW_TAG_subprogram
'''
        record = capture._member_record('regex.cpp.o', b'object', text.encode())
        unit = record['compile_units'][0]
        self.assertEqual(unit['dwarf_name_path'], 'libcxx/src/regex.cpp')
        self.assertEqual(unit['producer_version'], 'clang version 19.0.1')

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_member_listing_duplicate_fails_closed(self):
        self.listing.write_bytes(b'regex.cpp.o\nregex.cpp.o\nalgorithm.cpp.o\n')
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            self.run_capture()

    def test_changed_link_map_and_archive_fail_before_extraction(self):
        self.map.write_bytes(b'changed map')
        with self.assertRaisesRegex(ValueError, 'Link-map bytes'):
            self.run_capture()
        self.map.write_bytes(b'exact linker map bytes')
        self.archive.write_bytes(b'changed archive')
        with self.assertRaisesRegex(ValueError, 'archive digest changed'):
            self.run_capture()

    def test_unsafe_archive_path_fails_closed(self):
        self.write_manifest(path='../escape/libc++_static.a')
        with self.assertRaisesRegex(ValueError, 'unsafe'):
            self.run_capture()

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_object_byte_limit_is_enforced(self):
        with self.assertRaisesRegex(ValueError, 'configured byte bound'):
            self.run_capture(max_object_bytes=1)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_no_dwarf_is_a_recorded_finding_not_a_false_mapping(self):
        self.dwarf_file.write_bytes(b'')
        self.line_file.write_bytes(b'')
        result = self.run_capture()
        self.assertEqual(result['counts']['members_with_compile_units'], 0)
        self.assertTrue(all(item['dwarf_state'] == 'no-compile-units' for item in result['members']))
        self.assertTrue(all(item['line_table_state'] == 'no-line-table-output' for item in result['members']))
        self.assertTrue(all(item['line_tables'] == [] for item in result['members']))

    def test_absolute_source_path_without_component_root_is_redacted(self):
        path, state = capture._safe_source_path('/private/build/user/foo.cpp', '/other/root')
        self.assertIsNone(path)
        self.assertEqual(state, 'absolute-unmapped')

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_tool_output_limit_is_enforced_while_streaming(self):
        self.dwarf_file.write_bytes(b'x' * 4096)
        with self.assertRaisesRegex(ValueError, 'configured byte bound'):
            self.run_capture(max_tool_output_bytes=1024)

    def test_line_table_v19_prologue_resolves_dirs_and_checksums(self):
        tables = capture.parse_line_tables(LINE_TABLE_V19)
        self.assertEqual(len(tables), 1)
        self.assertEqual(tables[0]['version'], 5)
        self.assertEqual(len(tables[0]['files']), 2)
        first = tables[0]['files'][0]
        self.assertEqual(first['source_path'], 'libcxx/src/regex.cpp')
        self.assertEqual(first['source_path_state'], 'component-relative')
        self.assertEqual(first['md5'], '0123456789abcdef0123456789abcdef')
        self.assertEqual(first['md5_state'], 'present')
        second = tables[0]['files'][1]
        self.assertEqual(second['source_path'], 'secret.cpp')
        self.assertEqual(second['md5_state'], 'unavailable')
        self.assertIsNone(second['md5'])
        encoded = json.dumps(tables)
        self.assertNotIn('/home/runner', encoded)
        self.assertNotIn('/private', encoded)
        for record in tables[0]['files']:
            self.assertEqual(set(record.keys()), {'source_path', 'source_path_state', 'md5', 'md5_state'})

    def test_legacy_line_table_without_checksum_is_unavailable(self):
        table = line_table(
            4,
            '    include_directories[  1] = "/home/runner/llvm-project/libcxx/src"\n'
            '    file_names[  1]:\n'
            '               name: "old.cpp"\n'
            '               dir_index: 0\n'
            '    file_names[  2]:\n'
            '               name: "regex.cpp"\n'
            '               dir_index: 1\n')
        parsed = capture.parse_line_tables(table)
        self.assertEqual(parsed[0]['version'], 4)
        self.assertEqual(parsed[0]['files'][0]['source_path'], 'old.cpp')
        self.assertEqual(parsed[0]['files'][0]['source_path_state'], 'relative-name')
        self.assertEqual(parsed[0]['files'][1]['source_path'], 'libcxx/src/regex.cpp')
        self.assertIsNone(parsed[0]['files'][0]['md5'])
        self.assertEqual(parsed[0]['files'][0]['md5_state'], 'unavailable')

    def test_line_table_malformed_checksum_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'Malformed line-table checksum'):
            capture.parse_line_tables(line_table(
                5, '    file_names[  0]:\n'
                '               name: "a.cpp"\n'
                '               md5_checksum: 1234\n'))

    def test_line_table_malformed_version_fails_closed(self):
        malformed = b'debug_line[0x00000000]\nLine table prologue:\nversion: x\n'
        with self.assertRaisesRegex(ValueError, 'Malformed line-table version'):
            capture.parse_line_tables(malformed)
        with self.assertRaisesRegex(ValueError, 'Malformed line-table version'):
            capture.parse_line_tables(b'debug_line[0x00000000]\nLine table prologue:\nversion:\n')
        with self.assertRaisesRegex(ValueError, 'Unsupported line-table version'):
            capture.parse_line_tables(line_table(6))

    def test_line_table_malformed_dir_index_fails_closed(self):
        rows = '    file_names[  0]:\n               name: "a.cpp"\n'
        with self.assertRaisesRegex(ValueError, 'Malformed line-table directory index'):
            capture.parse_line_tables(line_table(5, rows + '               dir_index: x\n'))
        with self.assertRaisesRegex(ValueError, 'Malformed line-table directory index'):
            capture.parse_line_tables(line_table(5, rows + '               dir_index:\n'))

    def test_line_table_malformed_directory_record_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'Malformed line-table directory record'):
            capture.parse_line_tables(line_table(5, '    include_directories[  x] = "/tmp"\n'))

    def test_line_table_malformed_file_record_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'Malformed line-table file record'):
            capture.parse_line_tables(line_table(5, '    file_names[  x]:\n'))

    def test_line_table_directory_index_out_of_range_fails_closed(self):
        rows = (
            '    include_directories[  0] = "/tmp"\n'
            '    file_names[  0]:\n'
            '               name: "a.cpp"\n'
            '               dir_index: 5\n')
        with self.assertRaisesRegex(ValueError, 'out of range'):
            capture.parse_line_tables(line_table(5, rows))

    def test_line_table_duplicate_checksum_fails_closed(self):
        rows = (
            '    file_names[  0]:\n'
            '               name: "a.cpp"\n'
            '               md5_checksum: 0123456789abcdef0123456789abcdef\n'
            '               md5_checksum: 0123456789abcdef0123456789abcdef\n')
        with self.assertRaisesRegex(ValueError, 'Duplicate line-table checksum'):
            capture.parse_line_tables(line_table(5, rows))

    def test_line_table_checksum_without_path_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'checksum has no source path'):
            capture.parse_line_tables(line_table(
                5, '    md5_checksum: 0123456789abcdef0123456789abcdef\n'))

    def test_line_table_dir_index_without_path_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'directory index has no source path'):
            capture.parse_line_tables(line_table(5, '    dir_index: 0\n'))

    def test_line_table_missing_version_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'version is missing'):
            capture.parse_line_tables(line_table(None, include_version=False))

    def test_line_table_unrecognized_output_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'unrecognized'):
            capture.parse_line_tables(b'not a line table\n')
        with self.assertRaisesRegex(ValueError, 'unrecognized'):
            capture.parse_line_tables(b'x' * 64)

    def test_line_table_empty_is_no_table(self):
        self.assertEqual(capture.parse_line_tables(b''), [])
        self.assertEqual(capture.parse_line_tables(b'  \n '), [])

    def test_line_table_absolute_paths_are_redacted(self):
        rows = (
            '    include_directories[  0] = "/private/agent/source"\n'
            '    file_names[  0]:\n'
            '               name: "secret.cpp"\n'
            '               dir_index: 0\n'
            '    file_names[  1]:\n'
            '               name: "/private/agent/source/other.cpp"\n')
        tables = capture.parse_line_tables(line_table(5, rows))
        self.assertEqual(tables[0]['files'][0]['source_path'], 'secret.cpp')
        self.assertIsNone(tables[0]['files'][1]['source_path'])
        self.assertEqual(tables[0]['files'][1]['source_path_state'], 'absolute-unmapped')
        encoded = json.dumps(tables)
        self.assertNotIn('/private', encoded)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_line_table_output_budget_and_temp_object_cleanup(self):
        self.dwarfdump.write_text(
            '#!/usr/bin/env python3\nimport sys\n'
            'sys.stdout.write("x" * 4096) if sys.argv[1] == "--debug-line" else None\n', encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'output exceeds its configured byte bound'):
            self.run_capture(max_line_table_output_bytes=1024)
        self.assertEqual(list(self.root.glob('ndk-member-dwarf-*')), [])
        self.assertEqual(sorted(path.name for path in self.object_dir.iterdir()), sorted(self.members))

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_tool_timeout_terminates_capture(self):
        self.dwarfdump.write_text(
            '#!/usr/bin/env python3\nimport time\ntime.sleep(2)\n', encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'configured timeout'):
            self.run_capture(timeout_seconds=0.1)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_nonzero_debug_tool_reports_safe_member_context(self):
        self.dwarfdump.write_text(
            '#!/usr/bin/env python3\nimport sys\nsys.exit(7)\n', encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(
                ValueError,
                r'llvm-dwarfdump DWARF scan for algorithm\.cpp\.o returned exit status 7') as caught:
            self.run_capture()
        self.assertNotIn(str(self.root), str(caught.exception))

    def test_tool_diagnostic_strips_c0_and_c1_controls(self):
        raw = 'before\x07\u009b31mCSI\u0085next\u009dtitle'
        diagnostic = capture._safe_tool_diagnostic(raw.encode('utf-8'), 256)
        self.assertIn('before', diagnostic)
        self.assertIn('CSI', diagnostic)
        self.assertIn('next', diagnostic)
        self.assertFalse(any(
            ord(char) < 32 or 0x7f <= ord(char) <= 0x9f for char in diagnostic))

    def test_tool_diagnostic_has_a_utf8_byte_bound(self):
        diagnostic = capture._safe_tool_diagnostic(b'error: ' + b'x' * 128, 32)
        self.assertLessEqual(len(diagnostic.encode('utf-8')), 32)
        self.assertTrue(diagnostic.endswith('[truncated]'))

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_nonzero_debug_tool_reports_bounded_path_redacted_stderr(self):
        stderr = ('error: /home/runner/private/member.o: unsupported DWARF; '
                  'C:\\agent\\_work\\object.o\n')
        script = ('#!/usr/bin/env python3\nimport sys\n'
                  'sys.stderr.write(' + repr(stderr) + ')\n'
                  'sys.exit(7)\n')
        self.dwarfdump.write_text(script, encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(
                ValueError,
                r'llvm-dwarfdump DWARF scan for algorithm\.cpp\.o returned exit status 7') as caught:
            self.run_capture(max_diagnostic_bytes=256)
        message = str(caught.exception)
        self.assertIn('unsupported DWARF', message)
        self.assertIn('[path]', message)
        self.assertNotIn('/home/runner', message)
        self.assertNotIn('C:\\agent', message)
        self.assertNotIn(str(self.root), message)
        self.assertNotIn('[truncated]', message)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_nonzero_debug_tool_reports_sanitized_stdout_with_total_byte_bound(self):
        stdout = 'error: /home/runner/private/object.o: ' + 'x' * 512
        stderr = 'warning: /private/diagnostic.log\n'
        script = ('#!/usr/bin/env python3\nimport sys\n'
                  'sys.stdout.write(' + repr(stdout) + ')\n'
                  'sys.stderr.write(' + repr(stderr) + ')\n'
                  'sys.exit(1)\n')
        self.dwarfdump.write_text(script, encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'exit status 1') as caught:
            self.run_capture(max_diagnostic_bytes=64)
        message = str(caught.exception)
        diagnostic = message.split('; diagnostic: ', 1)[1].split('; capture incomplete', 1)[0]
        self.assertLessEqual(len(diagnostic.encode('utf-8')), 64)
        self.assertIn('[path]', diagnostic)
        self.assertIn('error:', diagnostic)  # The stdout stream is included after stderr.
        self.assertIn('warning:', diagnostic)
        self.assertNotIn('/home/runner', message)
        self.assertNotIn('/private/diagnostic.log', message)
        self.assertTrue(diagnostic.endswith('[truncated]'))

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_nonzero_debug_tool_reports_stdout_only_failure(self):
        stdout = 'no debug section\n'
        script = ('#!/usr/bin/env python3\nimport sys\n'
                  'sys.stdout.write(' + repr(stdout) + ')\n'
                  'sys.exit(1)\n')
        self.dwarfdump.write_text(script, encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'exit status 1') as caught:
            self.run_capture()
        self.assertIn('no debug section', str(caught.exception))

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_debug_tool_stderr_counts_against_output_bound(self):
        self.dwarfdump.write_text(
            '#!/usr/bin/env python3\nimport sys\n'
            'sys.stderr.write("x" * 4096)\n', encoding='utf-8')
        self.dwarfdump.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'output exceeds its configured byte bound'):
            self.run_capture(max_tool_output_bytes=1024)


if __name__ == '__main__':
    unittest.main()
