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


def digest(value):
    return hashlib.sha256(value).hexdigest()


class CaptureMemberDebugTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.ndk = self.root / 'ndk'
        self.bindir = self.ndk / 'toolchains' / 'llvm' / 'bin'
        self.bindir.mkdir(parents=True)
        self.ar = self.bindir / 'llvm-ar'
        self.readelf = self.bindir / 'llvm-readelf'
        self.listing = self.root / 'members.txt'
        self.object_dir = self.root / 'objects'
        self.object_dir.mkdir()
        self.dwarf_file = self.root / 'dwarf.txt'
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
        ar_script = (
            '#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n'
            'args=sys.argv[1:]\n'
            'target=Path(' + repr(str(self.listing)) + ') if args[0] == "t" else '
            'Path(' + repr(str(self.object_dir)) + ').joinpath(args[2])\n'
            'sys.stdout.buffer.write(target.read_bytes())\n'
        )
        readelf_script = (
            '#!/usr/bin/env python3\nimport sys\nfrom pathlib import Path\n'
            'sys.stdout.buffer.write(Path(' + repr(str(self.dwarf_file)) + ').read_bytes())\n'
        )
        self.ar.write_text(ar_script, encoding='utf-8')
        self.readelf.write_text(readelf_script, encoding='utf-8')
        self.ar.chmod(0o755)
        self.readelf.chmod(0o755)
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
            'llvm_readelf': self.readelf,
            'temp_root': self.root,
            'max_members': 64,
            'max_object_bytes': 1024,
            'max_tool_output_bytes': 1024 * 1024,
            'timeout_seconds': 5,
        }
        args.update(overrides)
        return capture.capture(**args)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_hashes_selected_members_and_sanitizes_compile_unit_paths(self):
        result = self.run_capture()
        self.assertEqual(result['link_map']['sha256'], digest(self.map.read_bytes()))
        self.assertEqual(result['archive']['sha256'], digest(self.archive_bytes))
        self.assertEqual(result['counts']['members'], 2)
        unit = result['members'][0]['compile_units'][0]
        self.assertEqual(unit['dwarf_name_path'], 'libcxx/src/regex.cpp')
        self.assertEqual(unit['dwarf_name_path_state'], 'component-relative')
        self.assertEqual(unit['dwarf_name_basename'], 'regex.cpp')
        self.assertEqual(unit['producer_version'], 'clang version 19.0.1')
        encoded = json.dumps(result)
        self.assertNotIn('/home/runner', encoded)
        self.assertNotIn('/private/build', encoded)
        self.assertNotIn('synthetic object:', encoded)

    def test_llvm_readelf_indexed_strings_are_extracted_without_form_text(self):
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
        result = self.run_capture()
        self.assertEqual(result['counts']['members_with_compile_units'], 0)
        self.assertTrue(all(item['dwarf_state'] == 'no-compile-units' for item in result['members']))

    def test_absolute_source_path_without_component_root_is_redacted(self):
        path, state = capture._safe_source_path('/private/build/user/foo.cpp', '/other/root')
        self.assertIsNone(path)
        self.assertEqual(state, 'absolute-unmapped')

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_tool_output_limit_is_enforced_while_streaming(self):
        self.dwarf_file.write_bytes(b'x' * 4096)
        with self.assertRaisesRegex(ValueError, 'configured byte bound'):
            self.run_capture(max_tool_output_bytes=1024)

    @unittest.skipUnless(os.name == 'posix', 'POSIX pipe tools are exercised on the Android Linux runner')
    def test_tool_timeout_terminates_capture(self):
        self.readelf.write_text(
            '#!/usr/bin/env python3\nimport time\ntime.sleep(2)\n', encoding='utf-8')
        self.readelf.chmod(0o755)
        with self.assertRaisesRegex(ValueError, 'configured timeout'):
            self.run_capture(timeout_seconds=0.1)


if __name__ == '__main__':
    unittest.main()
