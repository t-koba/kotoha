"""Synthetic tracking files: no compiler, SDK or inference required."""

import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from compiler_reads import capture, identity, MANIFESTS, SUMMARY


class CompilerReadsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.source = self.base / 'source'
        # Exercise most-specific-root mapping even under the source tree.
        self.generated = self.source / 'build'
        self.msvc, self.sdk = self.base / 'msvc', self.base / 'sdk'
        self.roots = self.source, self.generated, self.msvc, self.sdk
        for root in self.roots:
            root.mkdir(parents=True, exist_ok=True)
        self.cpp = self.put(self.source / 'src/a.cpp', 'source')
        self.header = self.put(self.source / 'src/a.h', 'header')
        self.unity = self.put(self.generated / 'unity/u.cxx', 'unity')
        self.version = self.put(self.generated / 'version.h', 'version')
        self.tool = self.put(self.msvc / 'v/include/tool.h', 'tool')
        self.win = self.put(self.sdk / 'include/v/windows.h', 'sdk')
        self.log = self.generated / 'target/release/CL.read.1.tlog.txt'

    def put(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding='utf-8')
        return path

    def test_selected_union_and_deterministic_manifests(self):
        self.put(self.source / 'unused.cpp', 'not selected')
        # BOM, CRLF, composite roots and repeated reads. Uppercase spelling only
        # where the filesystem is case-insensitive (Windows); portable hosts use
        # native case to honor real filesystem semantics.
        text = f'^{self.cpp}|{self.unity}\n{self.header}\n{self.version}\n{self.tool}\n{self.win}\n'
        if os.name == 'nt':
            text = text.upper()
        self.log.parent.mkdir(parents=True)
        self.log.write_bytes(('\ufeff' + text.replace('\n', '\r\n')).encode())
        other = self.put(self.generated / 'other/CL.read.2.tlog.txt',
                         f'^{self.cpp}\n{self.header}\n{self.win}\n')
        outputs = capture(*self.roots)
        def row(path, key):
            return f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {key}\n'
        self.assertEqual(outputs['source-sha256.txt'], row(self.cpp, 'src/a.cpp') + row(self.header, 'src/a.h'))
        self.assertEqual(outputs['generated-sha256.txt'], row(self.unity, 'unity/u.cxx') + row(self.version, 'version.h'))
        self.assertEqual(outputs['toolchain-sha256.txt'], row(self.tool, 'msvc/v/include/tool.h') + row(self.win, 'sdk/include/v/windows.h'))
        self.assertEqual(outputs['compiler-tracking-sha256.txt'], row(other, 'other/cl.read.2.tlog.txt') + row(self.log, 'target/release/cl.read.1.tlog.txt'))
        source_keys = row(self.unity, 'generated/unity/u.cxx') + row(self.cpp, 'source/src/a.cpp')
        fingerprint = hashlib.sha256(source_keys.encode()).hexdigest()
        self.assertIn(f'Compiler source-key manifest SHA256: {fingerprint}\n', outputs[SUMMARY])
        self.assertIn('Unique compiler source keys: 2\n', outputs[SUMMARY])
        self.assertIn('Unique compiler inputs (keys plus dependencies): 6\n', outputs[SUMMARY])
        self.assertNotIn(str(self.base), ''.join(outputs.values()))
        # Reordering/repeating records changes raw evidence, not selected hashes.
        self.put(self.log, f'^{self.unity}|{self.cpp}\n{self.win}\n{self.tool}\n{self.version}\n{self.header}\n{self.header}\n')
        repeated = capture(*self.roots)
        for name in MANIFESTS[:3]:
            self.assertEqual(outputs[name], repeated[name])
        self.assertNotEqual(outputs[MANIFESTS[3]], repeated[MANIFESTS[3]])
        self.assertEqual(identity(r'C:\SOURCE\src\A.cpp'), 'c:/source/src/a.cpp')

    def test_canonical_alias_resolves_to_configured_root(self):
        # Native filesystem alias: logged spelling differs lexically but names the
        # same file; capture must compare canonical identities (bounded native evidence).
        alias = self.base / 'alias_source'
        try:
            alias.symlink_to(self.source, target_is_directory=True)
        except (OSError, NotImplementedError) as error:
            self.skipTest(f'symlink alias unavailable: {error}')
        alias_cpp = alias / 'src/a.cpp'
        self.assertNotEqual(identity(str(alias_cpp)), identity(str(self.cpp)))
        self.assertTrue(alias_cpp.is_file())
        self.put(self.log, f'^{alias_cpp}\n{self.header}\n')
        outputs = capture(*self.roots)
        def row(path, key):
            return f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {key}\n'
        self.assertEqual(outputs['source-sha256.txt'], row(self.cpp, 'src/a.cpp') + row(self.header, 'src/a.h'))
        # A genuinely outside canonical target must still fail closed.
        outside = self.put(self.base / 'outside/evil.h', 'evil')
        escape = self.source / 'escape.h'
        escape.symlink_to(outside)
        self.put(self.log, f'^{alias_cpp}\n{escape}\n')
        with self.assertRaises(ValueError):
            capture(*self.roots)

    def test_mocked_short_spelling_canonicalization(self):
        # Mocked 8.3-style alias: no filesystem alias required (mock evidence only).
        # Simulates Windows short spelling expanding to the canonical file.
        short = self.base / 'SHORT~1/src/a.cpp'
        real_resolve = Path.resolve
        def fake_resolve(path, strict=False):
            if str(path).lower() == str(short).lower():
                return real_resolve(self.cpp, strict=strict)
            return real_resolve(path, strict=strict)
        with mock.patch.object(Path, 'resolve', fake_resolve):
            self.put(self.log, f'^{short}\n{self.header}\n')
            outputs = capture(*self.roots)
        def row(path, key):
            return f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {key}\n'
        self.assertEqual(outputs['source-sha256.txt'], row(self.cpp, 'src/a.cpp') + row(self.header, 'src/a.h'))

    def test_missing_malformed_and_unmapped_evidence_fails(self):
        with self.assertRaises(ValueError):
            capture(*self.roots)
        for text in ('', '\n', '^\n', f'{self.header}\n', f'^{self.cpp}\n',
                     f'^{self.cpp}|\n{self.header}\n',
                     f'^{self.cpp}\nrelative.h\n',
                     f'^{self.cpp}\n{self.source}/../outside.h\n',
                     f'^{self.cpp}\n{self.base}/outside.h\n',
                     f'^{self.cpp}\n{self.source}/missing.h\n',
                     f'^{self.source}/missing.cpp\n{self.header}\n'):
            with self.subTest(text=text):
                self.put(self.log, text)
                with self.assertRaises((ValueError, OSError)):
                    capture(*self.roots)
        self.put(self.log, f'^{self.cpp}\n{self.header}\n')
        with self.assertRaises(ValueError):
            capture(self.source, self.generated, self.source, self.sdk)

    def test_cli_clears_stale_outputs_on_failure(self):
        output = self.base / 'output'
        for name in (*MANIFESTS, SUMMARY):
            self.put(output / name, 'old passing evidence')
        args = [sys.executable, str(Path(__file__).with_name('compiler_reads.py'))]
        for label, root in zip(('source', 'generated', 'msvc', 'sdk', 'output'), (*self.roots, output)):
            args += ['--' + label, str(root)]
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('audit evidence incomplete', result.stderr)
        self.assertEqual(list(output.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
