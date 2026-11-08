import hashlib
import json
import re
from pathlib import Path
import tempfile
import unittest

from linker_map import record


class LinkerMapTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.build = self.root / 'build'
        self.ndk = self.root / 'ndk'
        self.build.mkdir()
        self.ndk.mkdir()
        self.map_path = self.build / 'llama-simple.map.pending'
        self.output_dir = self.build / 'validated-linker-map'
        self.build_archive = self.build / '_deps' / 'llama' / 'libllama.a'
        self.build_archive.parent.mkdir(parents=True)
        self.build_archive.write_bytes(b'linked llama archive')
        self.ndk_archive = self.ndk / 'toolchains' / 'libc++_static.a'
        self.ndk_archive.parent.mkdir(parents=True)
        self.ndk_archive.write_bytes(b'linked NDK C++ archive')

    def tearDown(self):
        self.temporary.cleanup()

    def write_map(self, content=None):
        if content is None:
            content = (
                f'  62d18 62d18 c 4 {self.build_archive.relative_to(self.build)}(llama.cpp.o):(.text)\n'
                f'  62d1c 62d1c 4 4 .rodata {self.build_archive.relative_to(self.build)}(llama-context.cpp.o):(.text)\n'
                '  62d20 62d20 8 4 .text\n'
                f'  62d20 62d20 8 4 {self.ndk_archive}(string.cpp.o):(.text)\n'
                f'  62d28 62d28 4 4 .rodata {self.ndk_archive}(locale.cpp.o):(.rodata)\n'
                f'  62d2c 62d2c 2 2 {self.ndk_archive}(wchar.cpp.o):(.rodata)\n'
            )
        self.map_path.write_text(content, encoding='utf-8')

    def capture(self, max_bytes=4096):
        return record(self.map_path, max_bytes, self.output_dir, self.build, self.ndk)

    def test_publishes_map_and_exact_selected_archive_hashes_together(self):
        self.write_map()
        expected_bytes = self.map_path.read_bytes()

        result = self.capture(max_bytes=max(4096, len(expected_bytes)))

        map_bytes = (self.output_dir / 'llama-simple.map').read_bytes()
        manifest = json.loads((self.output_dir / 'llama-simple.map.archives.json').read_text())
        self.assertEqual(result, {'size': len(map_bytes), 'sha256': hashlib.sha256(map_bytes).hexdigest()})
        self.assertEqual(json.loads((self.output_dir / 'llama-simple.map.sha256.json').read_text()), result)
        self.assertEqual(manifest['link_map'], result)
        self.assertEqual(manifest['schema'], 1)
        self.assertFalse(self.map_path.exists())
        self.assertEqual(manifest['archives'], [
            {
                'root': 'build',
                'path': '_deps/llama/libllama.a',
                'size': self.build_archive.stat().st_size,
                'sha256': hashlib.sha256(self.build_archive.read_bytes()).hexdigest(),
                'members': ['llama-context.cpp.o', 'llama.cpp.o'],
            },
            {
                'root': 'ndk',
                'path': 'toolchains/libc++_static.a',
                'size': self.ndk_archive.stat().st_size,
                'sha256': hashlib.sha256(self.ndk_archive.read_bytes()).hexdigest(),
                'members': ['locale.cpp.o', 'string.cpp.o', 'wchar.cpp.o'],
            },
        ])
        contributions = json.loads(
            (self.output_dir / 'llama-simple.map.contributions.json').read_text())
        self.assertEqual(contributions['schema'], 1)
        self.assertEqual(contributions['link_map'], result)
        self.assertEqual(contributions['archive'], {
            'path': 'ndk/toolchains/libc++_static.a',
            'size': self.ndk_archive.stat().st_size,
            'sha256': hashlib.sha256(self.ndk_archive.read_bytes()).hexdigest(),
        })
        self.assertEqual(contributions['counts'], {
            'members': 3, 'members_with_contributions': 3, 'contributions': 3})
        self.assertEqual(contributions['contributions'], [
            {
                'line': 4, 'member': 'string.cpp.o',
                'output_section': '.text', 'input_section': '.text',
                'vma': '0x62d20', 'lma': '0x62d20',
                'size_bytes': 8, 'align_bytes': 4,
            },
            {
                'line': 5, 'member': 'locale.cpp.o',
                'output_section': '.rodata', 'input_section': '.rodata',
                'vma': '0x62d28', 'lma': '0x62d28',
                'size_bytes': 4, 'align_bytes': 4,
            },
            {
                'line': 6, 'member': 'wchar.cpp.o',
                'output_section': '.rodata', 'input_section': '.rodata',
                'vma': '0x62d2c', 'lma': '0x62d2c',
                'size_bytes': 2, 'align_bytes': 2,
            },
        ])

    def test_rejects_missing_or_out_of_root_archive_without_publishing(self):
        outside = self.root / 'outside.a'
        outside.write_bytes(b'not in build or NDK')
        cases = (
            '1000 1000 4 4 _deps/missing.a(member.o)',
            f'1004 1004 4 4 {outside}(member.o)',
        )
        for reference in cases:
            with self.subTest(reference=reference):
                self.map_path.unlink(missing_ok=True)
                self.write_map(f'  {reference}:(.text)\n')
                with self.assertRaises(RuntimeError):
                    self.capture()
                self.assertFalse(self.output_dir.exists())

    def test_rejects_parent_traversal_and_maps_without_archive_rows(self):
        self.write_map('  1000 1000 4 4 ../outside.a(member.o):(.text)\n')
        with self.assertRaisesRegex(RuntimeError, 'parent traversal'):
            self.capture()
        self.assertFalse(self.output_dir.exists())

        self.map_path.unlink(missing_ok=True)
        self.write_map('  1000 1000 4 4 .text <internal>:(.text)\n')
        with self.assertRaisesRegex(RuntimeError, 'no archive-member rows'):
            self.capture()
        self.assertFalse(self.output_dir.exists())

    def test_rejects_libcxx_rows_without_a_valid_section_mapping(self):
        cases = (
            (f'  62d20 62d20 8 4 {self.ndk_archive}(string.cpp.o):(.text)\n',
             'missing or malformed libc++ section mapping'),
            (f'  62d20 62d20 8 4 .text {self.ndk_archive}(string.cpp.o):(bad)\n',
             'missing or malformed libc++ section mapping'),
            (f'  nope 62d20 8 4 .text {self.ndk_archive}(string.cpp.o):(.text)\n',
             'malformed libc++ address/size/alignment'),
        )
        for index, (content, message) in enumerate(cases):
            with self.subTest(content=content):
                self.map_path.unlink(missing_ok=True)
                self.output_dir = self.build / ('validated-' + str(index))
                self.write_map(content)
                with self.assertRaisesRegex(RuntimeError, re.escape(message)):
                    self.capture()
                self.assertFalse(self.output_dir.exists())

    def test_rejects_invalid_map_bounds_and_symlink_map(self):
        self.write_map()
        for limit in (0, -1, True):
            with self.subTest(limit=limit), self.assertRaisesRegex(ValueError, 'positive integer'):
                record(self.map_path, limit, self.output_dir / f'invalid-{limit}', self.build, self.ndk)
        with self.assertRaisesRegex(RuntimeError, 'exceeds configured byte bound'):
            self.capture(max_bytes=1)
        self.map_path.unlink(missing_ok=True)
        target = self.build / 'map-target'
        target.write_text('map', encoding='utf-8')
        try:
            self.map_path.symlink_to(target)
        except (OSError, NotImplementedError) as exc:
            self.skipTest(f'symlinks unavailable: {exc}')
        with self.assertRaisesRegex(RuntimeError, 'not a regular file'):
            self.capture()
        self.assertFalse(self.output_dir.exists())

    def test_rejects_empty_and_missing_maps(self):
        self.map_path.write_bytes(b'')
        with self.assertRaisesRegex(RuntimeError, 'empty'):
            self.capture()
        self.assertFalse(self.output_dir.exists())

        self.map_path.unlink(missing_ok=True)
        with self.assertRaisesRegex(RuntimeError, 'missing'):
            self.capture()
        self.assertFalse(self.output_dir.exists())


if __name__ == '__main__':
    unittest.main()
