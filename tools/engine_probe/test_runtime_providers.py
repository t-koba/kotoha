"""Synthetic provider-classification tests; not loader or inference evidence.

Windows loader observation itself runs only in the exact Windows CI step;
these tests cover the privacy-safe pure logic (dumpbin parsing, ApiSet
contracts, root-relative classification, direct-import tying and absolute
leak rejection) plus workflow integration. No model fixture is read.
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import runtime_providers as rp


LINKAGE = """Dump of file llama-simple.exe

File Type: EXECUTABLE IMAGE

  Image has the following dependencies:

    KERNEL32.dll
    VCRUNTIME140.dll
    MSVCP140.dll
    api-ms-win-crt-runtime-l1-1-0.dll
    API-MS-WIN-CRT-HEAP-L1-1-0.DLL

  Image has the following delay load dependencies:

    OLE32.dll
"""

APP = r'C:\build\bin'
WINDOWS = r'C:\Windows'


def fake_info_factory(status='Valid', version='10.0.22621.3672'):
    def fake(absolute):
        base = rp._basename_lower(absolute)
        return {
            'sha256': hashlib.sha256(base.encode()).hexdigest(),
            'size': 1024 + len(base),
            'file_version': version,
            'product_version': version,
            'signer_status': status,
        }
    return fake


def assemble_simple(debug, linkage=LINKAGE, info=None, app=APP, windows=WINDOWS):
    return rp.assemble(
        exe_name='llama-simple.exe', exe_sha256='a' * 64, exe_size=999,
        exe_classified='app/llama-simple.exe', linkage_text=linkage,
        linkage_sha256='b' * 64, debug_paths=list(debug),
        file_info=info or fake_info_factory(), app_root=app, windows_root=windows)


class ParseTest(unittest.TestCase):
    def test_direct_delay_and_contracts(self):
        direct, delay = rp.parse_linkage_log(LINKAGE, 'llama-simple.exe')
        self.assertEqual(direct, ['api-ms-win-crt-heap-l1-1-0.dll',
                                  'api-ms-win-crt-runtime-l1-1-0.dll',
                                  'kernel32.dll', 'msvcp140.dll', 'vcruntime140.dll'])
        self.assertEqual(delay, ['ole32.dll'])
        self.assertTrue(rp.is_api_contract('api-ms-win-crt-runtime-l1-1-0.dll'))
        self.assertTrue(rp.is_api_contract('EXT-MS-WIN-ntuser-misc-l1-1-0.dll'.lower()))
        self.assertFalse(rp.is_api_contract('kernel32.dll'))

    def test_dll_name_rows_and_case(self):
        text = ('Dump of file llama-simple.exe\n'
                '  Image has the following dependencies:\n'
                '    Section contains the following imports:\n'
                '      DLL Name: KERNEL32.dll\n'
                '      DLL Name: kernel32.dll\n'
                '      kernel32.dll\n')
        direct, delay = rp.parse_linkage_log(text, 'llama-simple.exe')
        self.assertEqual(direct, ['kernel32.dll'])
        self.assertEqual(delay, [])

    def test_missing_or_empty_fails(self):
        for text in ('', 'no dependencies here\n', 'Dump of file llama-simple.exe\n'):
            with self.subTest(text=text[:20]), self.assertRaises(ValueError):
                rp.parse_linkage_log(text, 'llama-simple.exe')
        # Direct section present but no DLL rows.
        with self.assertRaises(ValueError):
            rp.parse_linkage_log('Dump of file llama-simple.exe\n  Image has the following dependencies:\n\n', 'llama-simple.exe')
        # Binary evidence is not text.
        with self.assertRaises(ValueError):
            rp.parse_linkage_log('a\x00b', 'llama-simple.exe')

    def test_linkage_must_name_exact_executable(self):
        cases = ((LINKAGE.replace('llama-simple.exe', 'other.exe'), 'exact executable'),
                 (LINKAGE.replace('Dump of file llama-simple.exe\n', ''), 'missing or ambiguous'),
                 (LINKAGE + 'Dump of file llama-simple.exe\n', 'missing or ambiguous'))
        for text, error in cases:
            with self.subTest(error=error), self.assertRaisesRegex(ValueError, error):
                rp.parse_linkage_log(text, 'llama-simple.exe')


class LinkagePathTest(unittest.TestCase):
    def test_reported_linkage_path_must_match_hashed_executable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            exe = root / 'llama-simple.exe'
            exe.write_bytes(b'probe executable')
            matching = LINKAGE.replace('Dump of file llama-simple.exe', 'Dump of file ' + str(exe))
            rp.validate_linkage_target(matching, exe)
            other = root / 'other' / 'llama-simple.exe'
            stale = LINKAGE.replace('Dump of file llama-simple.exe', 'Dump of file ' + str(other))
            with self.assertRaisesRegex(ValueError, 'another executable path'):
                rp.validate_linkage_target(stale, exe)


class ClassifyTest(unittest.TestCase):
    def test_app_windows_and_redacted(self):
        self.assertEqual(rp.classify_provider(r'C:\Windows\System32\ntdll.dll', APP, WINDOWS),
                         'windows/system32/ntdll.dll')
        self.assertEqual(rp.classify_provider('c:/WINDOWS/system32/KERNEL32.DLL', APP, WINDOWS),
                         'windows/system32/kernel32.dll')
        self.assertEqual(rp.classify_provider(r'C:\build\bin\vcruntime140.dll', APP, WINDOWS),
                         'app/vcruntime140.dll')
        self.assertEqual(rp.classify_provider(r'\\?\C:\Windows\System32\kernel32.dll', APP, WINDOWS),
                         'windows/system32/kernel32.dll')
        self.assertEqual(rp.classify_provider(r'C:\Program Files\AV\hook.dll', APP, WINDOWS),
                         'redacted/hook.dll')

    def test_most_specific_root_wins(self):
        # Nested app root under a broader prefix keeps app classification.
        app = r'C:\Windows\ side'.replace(' side', '') + r'\app'
        # Use synthetic distinct roots where app is nested under windows-like prefix.
        nested_app = WINDOWS + r'\Temp\app'
        path = nested_app + r'\side.dll'
        self.assertEqual(rp.classify_provider(path, nested_app, WINDOWS), 'app/side.dll')

    def test_non_absolute_traversal_and_distinct_roots_fail(self):
        with self.assertRaises(ValueError):
            rp.classify_provider(r'relative\kernel32.dll', APP, WINDOWS)
        with self.assertRaises(ValueError):
            rp.classify_provider(r'C:\Windows\..\evil.dll', APP, WINDOWS)
        with self.assertRaises(ValueError):
            rp.classify_provider(r'C:\Windows\System32\a.dll', WINDOWS, WINDOWS)
        with self.assertRaises(ValueError):
            rp._basename_lower(r'C:\Windows\System32\\')
        with self.assertRaises(ValueError):
            rp._basename_lower(r'C:\Windows\System32\BAD NAME!.dll')


class TieTest(unittest.TestCase):
    def debug(self):
        return [WINDOWS + r'\System32\kernel32.dll',
                WINDOWS + r'\System32\vcruntime140.dll',
                WINDOWS + r'\System32\msvcp140.dll',
                WINDOWS + r'\System32\ntdll.dll']

    def test_contracts_need_no_file_but_ordinary_do(self):
        manifest, summary = assemble_simple(self.debug())
        self.assertEqual(manifest['counts'], {'direct': 5, 'delay': 1, 'contracts': 2,
                                              'providers': 4, 'redacted': 0})
        self.assertEqual(manifest['signer_check'], rp.SIGNER_CHECK)
        self.assertEqual(manifest['contracts'], ['api-ms-win-crt-heap-l1-1-0.dll',
                                                 'api-ms-win-crt-runtime-l1-1-0.dll'])
        ties = {item['basename']: item['tie'] for item in manifest['providers']}
        self.assertEqual(ties['kernel32.dll'], 'direct')
        self.assertEqual(ties['ntdll.dll'], 'transitive')
        # Delay import present pre-entrypoint would tie as delay, not required.
        manifest2, _ = assemble_simple(self.debug() + [WINDOWS + r'\System32\ole32.dll'])
        ties2 = {item['basename']: item['tie'] for item in manifest2['providers']}
        self.assertEqual(ties2['ole32.dll'], 'delay')
        # Delay import absent pre-entrypoint is fine.
        self.assertNotIn('ole32.dll', ties)
        self.assertNotIn('C:', json.dumps(manifest))
        self.assertNotIn('\\', json.dumps(manifest))
        manifest_text = json.dumps(manifest, sort_keys=True, indent=2) + '\n'
        expected_digest = hashlib.sha256(manifest_text.encode('utf-8')).hexdigest()
        self.assertIn('Manifest SHA256: ' + expected_digest, summary)

    def test_missing_ordinary_fails_closed(self):
        with self.assertRaisesRegex(ValueError, 'without loader resolution'):
            assemble_simple([WINDOWS + r'\System32\kernel32.dll'])

    def test_duplicate_empty_and_unsafe_fail(self):
        with self.assertRaises(ValueError):
            assemble_simple([])
        # Repeated loader events for the same case-insensitive path represent
        # one provider and must not inflate the manifest or cause ambiguity.
        manifest, _ = assemble_simple([
            WINDOWS + r'\System32\kernel32.dll',
            WINDOWS + r'\System32\KERNEL32.DLL',
            WINDOWS + r'\System32\vcruntime140.dll',
            WINDOWS + r'\System32\msvcp140.dll',
        ])
        self.assertEqual(
            [item['basename'] for item in manifest['providers']],
            ['kernel32.dll', 'msvcp140.dll', 'vcruntime140.dll'])
        # Distinct paths with the same basename remain ambiguous. Only the
        # sanitized basename is reported; neither absolute path may escape.
        first = WINDOWS + r'\System32\msvcp140.dll'
        second = APP + r'\msvcp140.dll'
        with self.assertRaisesRegex(
            ValueError,
            'Ambiguous provider basename msvcp140[.]dll; closure incomplete') as error:
            assemble_simple([
                WINDOWS + r'\System32\kernel32.dll',
                WINDOWS + r'\System32\vcruntime140.dll', first, second,
            ])
        self.assertNotIn(first, str(error.exception))
        self.assertNotIn(second, str(error.exception))
        with self.assertRaises(ValueError):
            assemble_simple([WINDOWS + r'\System32\kernel32.dll',
                              WINDOWS + r'\System32\vcruntime140.dll',
                              WINDOWS + r'\System32\msvcp140.dll'],
                             linkage='  Image has the following dependencies:\n')
        # Unsafe basename from loader observation fails.
        with self.assertRaises(ValueError):
            assemble_simple([WINDOWS + r'\System32\kernel32.dll',
                              WINDOWS + r'\System32\vcruntime140.dll',
                              WINDOWS + r'\System32\msvcp140.dll',
                              WINDOWS + r'\System32\bad name.dll'])

    def test_redacted_is_safe_but_counted(self):
        debug = self.debug() + [r'C:\Program Files\AV\hook.dll']
        manifest, summary = assemble_simple(debug)
        self.assertEqual(manifest['counts']['redacted'], 1)
        hook = [item for item in manifest['providers'] if item['basename'] == 'hook.dll'][0]
        self.assertEqual(hook['classified_path'], 'redacted/hook.dll')
        self.assertEqual(hook['tie'], 'transitive')
        self.assertNotIn('Program Files', json.dumps(manifest))
        self.assertNotIn('Program Files', summary)

    def test_bad_hash_version_signer_fail(self):
        base_debug = self.debug()
        for mutate in ('sha', 'version', 'signer'):
            def bad(absolute, _mutate=mutate):
                info = fake_info_factory()(absolute)
                if _mutate == 'sha':
                    info['sha256'] = 'ZZZ'
                elif _mutate == 'version':
                    info['file_version'] = 'no-version'
                else:
                    info['signer_status'] = 'Signed(?)'
                return info
            with self.subTest(mutate=mutate), self.assertRaises(ValueError):
                assemble_simple(base_debug, info=bad)
        # Unavailable version and NotSigned are representable, not failures.
        def unsigned(absolute):
            info = fake_info_factory()(absolute)
            info['file_version'] = 'unavailable'
            info['product_version'] = 'unavailable'
            info['signer_status'] = 'NotSigned'
            return info
        manifest, _ = assemble_simple(base_debug, info=unsigned)
        self.assertEqual(manifest['providers'][0]['signer_status'], 'NotSigned')

    def test_count_limits_are_configurable_and_bounded(self):
        with self.assertRaisesRegex(ValueError, 'Loader observation'):
            rp.assemble(exe_name='llama-simple.exe', exe_sha256='a' * 64, exe_size=999,
                        exe_classified='app/llama-simple.exe', linkage_text=LINKAGE,
                        linkage_sha256='b' * 64, debug_paths=self.debug(),
                        file_info=fake_info_factory(), app_root=APP, windows_root=WINDOWS,
                        max_providers=3)
        with self.assertRaisesRegex(ValueError, 'Import count exceeds bound'):
            rp.parse_linkage_log(LINKAGE, 'llama-simple.exe', max_imports=4)
        for value in ('0', '-1', '1.5', 'not-a-count'):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                rp.positive_count(value)
        self.assertEqual(rp.positive_count('4097'), 4097)
        self.assertEqual(rp.positive_seconds('601'), 601.0)

    def test_kotoha_command_metadata_has_no_arguments(self):
        self.assertEqual(rp.COMMANDS['llama-simple.exe'], ['llama-simple.exe', '--help'])
        self.assertEqual(rp.COMMANDS['kotoha.exe'], ['kotoha.exe'])
        linkage = LINKAGE.replace('llama-simple.exe', 'kotoha.exe')
        manifest, summary = rp.assemble(
            exe_name='kotoha.exe', exe_sha256='a' * 64, exe_size=999,
            exe_classified='app/kotoha.exe', linkage_text=linkage,
            linkage_sha256='b' * 64, debug_paths=self.debug(),
            file_info=fake_info_factory(), app_root=APP, windows_root=WINDOWS)
        self.assertEqual(manifest['command'], ['kotoha.exe'])
        self.assertIn('command kotoha.exe\n', summary)
        self.assertIn('Windows 11 behavior and runtime redistribution entitlement are not claimed.', summary)
        llama_manifest, llama_summary = rp.assemble(
            exe_name='llama-simple.exe', exe_sha256='a' * 64, exe_size=999,
            exe_classified='app/llama-simple.exe', linkage_text=LINKAGE,
            linkage_sha256='b' * 64, debug_paths=self.debug(),
            file_info=fake_info_factory(), app_root=APP, windows_root=WINDOWS)
        self.assertEqual(llama_manifest['command'], ['llama-simple.exe', '--help'])
        self.assertNotIn('Windows 11 behavior', llama_summary)
        self.assertIn('No model fixture reads, no DLL copies, no redistribution or licensing approval.', llama_summary)

    def test_unexpected_executable_fails(self):
        with self.assertRaisesRegex(ValueError, 'capture target is not configured'):
            rp.assemble(exe_name='other.exe', exe_sha256='a' * 64, exe_size=999,
                        exe_classified='app/other.exe', linkage_text=LINKAGE,
                        linkage_sha256='b' * 64, debug_paths=self.debug(),
                        file_info=fake_info_factory(), app_root=APP, windows_root=WINDOWS)

    def test_exe_outside_app_root_fails(self):
        with self.assertRaises(ValueError):
            rp.assemble(exe_name='llama-simple.exe', exe_sha256='a' * 64, exe_size=999,
                        exe_classified='windows/llama-simple.exe', linkage_text=LINKAGE,
                        linkage_sha256='b' * 64, debug_paths=self.debug(),
                        file_info=fake_info_factory(), app_root=APP, windows_root=WINDOWS)


class NoAbsoluteTest(unittest.TestCase):
    def test_drive_backslash_unc_and_runner_markers_rejected(self):
        for leak in ('C:\\Windows\\x', 'c:/users/runner/x', '\\\\server\\share\\x',
                     '//server/share/x', '/home/runner/x', '/opt/private/module.dll', 'a users/test',
                     'program files/test', 'x/../y'):
            # 'x/../y' is only a leak when it appears as a path segment; the
            # summary never contains it, so craft a direct check.
            with self.subTest(leak=leak), self.assertRaises(ValueError):
                rp.verify_no_absolute('prefix ' + leak + ' suffix')
        # Safe classified records pass.
        rp.verify_no_absolute('windows/system32/kernel32.dll redacted/hook.dll app/x.dll')


class CliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.exe = self.base / 'llama-simple.exe'
        self.exe.write_bytes(b'synthetic exe')
        self.linkage = self.base / 'linkage.log'
        self.linkage.write_text(LINKAGE, encoding='utf-8')
        self.output = self.base / 'output'

    def run_cli(self, *extra):
        args = [sys.executable, str(Path(__file__).with_name('runtime_providers.py')),
                '--executable', str(self.exe), '--linkage-log', str(self.linkage),
                '--output', str(self.output), *extra]
        return subprocess.run(args, capture_output=True, text=True)

    def test_non_windows_fails_closed_and_clears_stale(self):
        for name in (rp.PROVIDERS_JSON, rp.SUMMARY):
            (self.output / name).parent.mkdir(parents=True, exist_ok=True)
            (self.output / name).write_text('old passing evidence', encoding='utf-8')
        result = self.run_cli()
        # This host is POSIX, so the Windows-only capture must refuse rather
        # than synthesize loader evidence.
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('audit evidence incomplete', result.stderr)
        self.assertEqual(list(self.output.iterdir()), [])
        # Missing linkage evidence also clears stale outputs without Windows.
        (self.output / rp.PROVIDERS_JSON).write_text('old', encoding='utf-8')
        self.linkage.unlink()
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(self.output.iterdir()), [])
        # Missing executable likewise fails closed.
        self.linkage.write_text(LINKAGE, encoding='utf-8')
        self.exe.unlink()
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)

    def test_no_model_or_copy_flags(self):
        source = Path(__file__).with_name('runtime_providers.py').read_text(encoding='utf-8')
        for token in ('fixture-dir', 'ENGINE_MODEL_DIR', 'Copy-Item', 'xcopy', '.gguf', 'acquire'):
            self.assertNotIn(token, source)


class DebugTerminationTest(unittest.TestCase):
    def test_request_termination_before_releasing_debug_event(self):
        calls = []

        class FakeKernel32:
            def TerminateProcess(self, handle, code):
                calls.append(('terminate', handle, code))
                return True

            def ContinueDebugEvent(self, pid, tid, status):
                calls.append(('continue', pid, tid, status))
                return True

        rp._terminate_before_continuing_event(FakeKernel32(), 'process', 7, 8, 9)
        self.assertEqual(calls, [('terminate', 'process', 1), ('continue', 7, 8, 9)])

    def test_failed_termination_does_not_release_event(self):
        calls = []

        class FakeKernel32:
            def TerminateProcess(self, handle, code):
                calls.append('terminate')
                return False

            def ContinueDebugEvent(self, pid, tid, status):
                calls.append('continue')
                return True

        with self.assertRaisesRegex(ValueError, 'Could not terminate'):
            rp._terminate_before_continuing_event(FakeKernel32(), 'process', 7, 8, 9)
        self.assertEqual(calls, ['terminate'])


class WorkflowTest(unittest.TestCase):
    def test_release_provider_capture_wiring(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / '.github/workflows/ci.yml').read_text(encoding='utf-8')
        self.assertIn('Capture sanitized Release runner imports', workflow)
        self.assertIn('Capture sanitized Release runtime providers before entrypoint', workflow)
        self.assertIn('dumpbin /HEADERS /DEPENDENTS $exe', workflow)
        self.assertIn('runtime_providers.py --executable $exe --linkage-log $linkage', workflow)
        self.assertIn('windows-release-runtime-providers', workflow)
        self.assertIn('runtime-providers.json', workflow)
        self.assertIn('runtime-summary.txt', workflow)
        capture = workflow[workflow.index('Capture sanitized Release runtime providers'):]
        self.assertIn('kotoha-release-linkage.txt', capture)
        self.assertIn('finally {', capture)
        upload = capture[capture.index('Retain sanitized Release runtime provider evidence'):]
        self.assertNotIn('kotoha-release-linkage.txt', upload)

    def test_windows_step_captures_pre_entrypoint_without_model(self):
        root = Path(__file__).resolve().parents[2]
        workflow = (root / '.github/workflows/engine-probe.yml').read_text(encoding='utf-8')
        self.assertIn('runtime_providers.py --executable', workflow)
        self.assertIn('--linkage-log', workflow)
        self.assertIn('--output build/engine-probe', workflow)
        self.assertIn('ENGINE_RUNTIME_DEBUG_SECONDS', workflow)
        self.assertIn('ENGINE_RUNTIME_MAX_PROVIDERS', workflow)
        self.assertIn('ENGINE_RUNTIME_MAX_IMPORTS', workflow)
        self.assertIn('build/engine-probe/runtime-providers.json', workflow)
        self.assertIn('build/engine-probe/runtime-summary.txt', workflow)
        # The new capture must not read model fixtures, copy DLLs, or grant approval.
        capture = workflow[workflow.index('runtime_providers.py') - 800: workflow.index('runtime_providers.py') + 800]
        self.assertNotIn('ENGINE_MODEL_DIR', capture)
        self.assertNotIn('Copy-Item', capture)
        self.assertNotIn('approved', capture.lower())
        self.assertNotIn('granted', capture.lower())


if __name__ == '__main__':
    unittest.main()
