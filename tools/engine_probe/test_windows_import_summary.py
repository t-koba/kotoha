"""Tests for the privacy-safe Windows Release import summary."""

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock

from windows_import_summary import capture, make_summary


class WindowsImportSummaryTest(unittest.TestCase):
    def test_summary_binds_hash_without_retaining_path(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'kotoha.exe'
            contents = b'bounded synthetic PE placeholder'
            executable.write_bytes(contents)
            summary = make_summary(executable, ['kernel32.dll'], ['ole32.dll'])
            encoded = json.dumps(summary)
            self.assertEqual(summary['sha256'], hashlib.sha256(contents).hexdigest())
            self.assertEqual(summary['size'], len(contents))
            self.assertEqual(summary['exe'], 'kotoha.exe')
            self.assertNotIn(directory, encoded)

    def test_summary_rejects_path_like_import_names(self):
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / 'kotoha.exe'
            executable.write_bytes(b'bounded synthetic PE placeholder')
            with self.assertRaises(ValueError):
                make_summary(executable, [r'C:\Windows\System32\bad.dll'], [])

    def test_capture_writes_only_sanitized_summary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'kotoha.exe'
            executable.write_bytes(b'bounded synthetic PE placeholder')
            dumpbin = root / 'dumpbin.exe'
            dumpbin.write_bytes(b'fake tool placeholder')
            output = root / 'summary.json'
            dump = f'''Dump of file {executable}
8664 machine (x64)
  Image has the following dependencies:
    KERNEL32.dll
    VCRUNTIME140.dll
  Image has the following delay load dependencies:
    OLE32.dll
'''
            with mock.patch('windows_import_summary.subprocess.run',
                            return_value=SimpleNamespace(returncode=0, stdout=dump, stderr='')):
                capture(executable, output, dumpbin)
            encoded = output.read_text(encoding='utf-8')
            summary = json.loads(encoded)
            self.assertEqual(summary['direct_imports'], ['kernel32.dll', 'vcruntime140.dll'])
            self.assertEqual(summary['delay_imports'], ['ole32.dll'])
            self.assertNotIn(directory, encoded)
            self.assertNotIn(str(executable), encoded)

    def test_capture_failure_does_not_write_summary_or_echo_tool_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            executable = root / 'kotoha.exe'
            executable.write_bytes(b'bounded synthetic PE placeholder')
            dumpbin = root / 'dumpbin.exe'
            dumpbin.write_bytes(b'fake tool placeholder')
            output = root / 'summary.json'
            with mock.patch('windows_import_summary.subprocess.run',
                            return_value=SimpleNamespace(returncode=1,
                                                         stdout=str(executable),
                                                         stderr='raw tool error')):
                with self.assertRaises(ValueError):
                    capture(executable, output, dumpbin)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
