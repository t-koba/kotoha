"""Small POSIX Ninja records, not Android compilation or binary closure."""
import json
import os
from pathlib import Path
import tempfile
import unittest

import ninja_reads


@unittest.skipIf(os.name == 'nt', 'Clang/Ninja POSIX records; MSVC has separate tests')
class NinjaReadsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.build, self.source, self.ndk, self.probe = (self.root / n for n in ('build', 'source', 'ndk', 'probe'))
        for root in (self.build, self.source, self.ndk, self.probe):
            root.mkdir()
        self.cpp = self.source / 'selected.cpp'
        self.cpp.write_text('selected')
        (self.source / 'unselected.cpp').write_text('unselected')
        self.header = self.ndk / 'header.h'
        self.header.write_text('header')
        (self.build / 'selected.o').write_bytes(b'object')
        self.commands = [{'directory': str(self.build), 'file': str(self.cpp),
                          'command': f'clang -o selected.o -c {self.cpp}'},
                         {'directory': str(self.build), 'file': str(self.source / 'unselected.cpp'),
                          'command': f'clang -o unbuilt.o -c {self.source / "unselected.cpp"}'}]
        (self.build / '.ninja_log').write_text('# ninja log v5\n0\t1\t123\tselected.o\t0123456789abcdef\n')
        self.records = f'selected.o: #deps 2, deps mtime 123 (VALID)\n    {self.cpp}\n    {self.header}\n\n'

    def capture(self):
        (self.build / 'compile_commands.json').write_text(json.dumps(self.commands))
        (self.build / 'ninja-deps.txt').write_text(self.records)
        return ninja_reads.capture(self.build, self.source, self.ndk, self.probe)

    def test_built_objects_only_and_selected_hashes_change(self):
        outputs = self.capture()
        manifest = outputs[ninja_reads.OUTPUTS[0]]
        self.assertIn('source/selected.cpp', manifest)
        self.assertIn('ndk/header.h', manifest)
        self.assertNotIn('unselected', manifest)
        self.assertIn('represented: 1', outputs[ninja_reads.OUTPUTS[2]])
        self.header.write_text('changed')
        self.assertNotEqual(manifest, self.capture()[ninja_reads.OUTPUTS[0]])

    def test_empty_unknown_stale_missing_escaping_and_unrepresented(self):
        valid = self.records
        for text in ('', '    header.h\n', valid.replace('(VALID)', '(STALE)'),
                     valid.replace('#deps 2', '#deps 0'), valid + valid,
                     valid.replace(str(self.header), str(self.root / 'missing')),
                     valid.replace(str(self.header), str(self.root / 'outside.h')),
                     valid.replace(str(self.cpp), str(self.header)),
                     valid.replace('selected.o:', 'unbuilt.o:'),
                     valid.replace(str(self.header), '../ndk/header.h')):
            (self.root / 'outside.h').write_text('outside')
            self.records = text
            with self.subTest(text=text), self.assertRaises((ValueError, OSError)):
                self.capture()
        self.records = valid
        self.commands.append(self.commands[0])
        with self.assertRaisesRegex(ValueError, 'colliding'):
            self.capture()

    def test_dependency_record_failures_name_object_and_counts(self):
        valid = self.records
        cases = (
            (valid.replace('#deps 2', '#deps 0'),
             r'empty Ninja dependency record for selected\.o'),
            (valid.replace('#deps 2', '#deps 3'),
             r'Ninja dependency count mismatch for selected\.o: expected 3, parsed 2'),
            (valid.replace('selected.o:', 'unknown.o:'),
             r'unrepresented Ninja dependency object unknown\.o'),
        )
        for records, message in cases:
            self.records = records
            with self.subTest(message=message), self.assertRaisesRegex(ValueError, message):
                self.capture()
        self.records = valid

    def test_dependency_aliases_are_validated_and_deduplicated(self):
        alias = self.ndk / 'header-alias.h'
        alias.symlink_to(self.header)
        cases = (
            (self.cpp, self.header, alias),
            (self.cpp, self.header, self.header),
        )
        for dependencies in cases:
            self.records = (
                f'selected.o: #deps {len(dependencies)}, deps mtime 123 (VALID)\n'
                + ''.join(f'    {path}\n' for path in dependencies)
            )
            manifest = self.capture()[ninja_reads.OUTPUTS[0]]
            self.assertEqual(manifest.count('ndk/header.h'), 1)
            self.assertNotIn('header-alias.h', manifest)

    def test_v7_build_log_uses_supported_five_field_records(self):
        text = '# ninja log v7\n0\t1\t123\tselected.o\t0123456789abcdef\n'
        (self.build / '.ninja_log').write_text(text)
        outputs = self.capture()
        self.assertIn('source/selected.cpp', outputs[ninja_reads.OUTPUTS[0]])
        self.assertIn('represented: 1', outputs[ninja_reads.OUTPUTS[2]])

    def test_build_log_requires_every_actual_compiler_object(self):
        for text in ('', '# ninja log v6\n', '# ninja log v5\nmalformed',
                     '# ninja log v7\nmalformed', '# ninja log v5\n',
                     '# ninja log v5\n0\t1\t123\tunbuilt.o\t1234\n',
                     '# ninja log v5\n0\t1\t123\tunknown.o\t1234\n'):
            (self.build / '.ninja_log').write_text(text)
            with self.subTest(text=text), self.assertRaises(ValueError):
                self.capture()

    def test_dependency_alias_cannot_escape_scope(self):
        outside = self.root / 'outside.h'
        outside.write_text('outside')
        self.header.unlink()
        self.header.symlink_to(outside)
        with self.assertRaisesRegex(ValueError, 'outside'):
            self.capture()


if __name__ == '__main__':
    unittest.main()
