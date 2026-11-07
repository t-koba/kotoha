"""Synthetic orchestration only. These tests cannot establish native feasibility."""
import argparse
import contextlib
import io
import json
import os
import sys
from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import acquire
import android
import smoke
from test_smoke import HEADER, DECODED, pin


class TransportTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.entries = []
        for name, data in (('LICENSE', b'terms'), ('README.md', b'card'), (smoke.MODEL, HEADER)):
            entry = {**pin(data), 'url': 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/'
                     '9217f5db79a29953eb74d5343926648285ec7e67/' + name}
            (self.root / entry['sha256']).write_bytes(data)
            self.entries.append(entry)
        manifest = self.root / 'manifest.json'
        manifest.write_text(json.dumps({'files': self.entries}))
        self.patch = patch.object(smoke, 'MANIFEST', manifest)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.exe = self.root / 'binary with spaces'
        self.exe.write_bytes(b'synthetic executable identity')
        self.args = argparse.Namespace(executable=self.exe, fixture_dir=self.root,
            accept_terms_sha256=pin(b'terms')['sha256'], adb=Path('/synthetic adb'),
            serial='emulator-5554', avd_name='kotoha-engine-unique', device_root='/data/local/tmp',
            adb_timeout_seconds=5, timeout_seconds=2.5, output_bytes=1024, tokens=16)
        self.calls, self.pushed = [], {}
        self.silent = contextlib.redirect_stdout(io.StringIO())
        self.silent.__enter__()
        self.addCleanup(self.silent.__exit__, None, None, None)

    def fake(self, command, timeout, budget, code, load_failure=False):
        self.calls.append((command, timeout, budget, code, load_failure))
        self.assertEqual(command[:3], [str(self.args.adb), '-s', 'emulator-5554'])
        if command[3] == 'emu':
            return b'kotoha-engine-unique\r\nOK\r\n', b'', False
        if command[3] == 'push':
            self.pushed[command[5]] = Path(command[4]).read_bytes()
            return b'1 file pushed', b'', False
        self.assertEqual(command[4], '-T')
        shell = shlex.split(command[5])
        self.assertEqual(shell[:2], ['sh', '-c'])
        script = shell[2]
        outputs = {'getprop ro.kernel.qemu': b'1', 'getprop ro.build.version.sdk': b'35',
                   'getprop ro.product.cpu.abi': b'x86_64', 'getprop ro.build.fingerprint': b'synthetic-profile',
                   'readlink -f /data/local/tmp': b'/data/local/tmp'}
        if script in outputs:
            return outputs[script], b'', False
        args = shlex.split(script)
        if args[0] == 'sha256sum' and args[1].startswith(('/system/', '/apex/')):
            return '\n'.join('0' * 64 + '  ' + p for p in args[1:]).encode(), b'', False
        if args[0] == 'sha256sum':
            return (pin(self.pushed[args[1]])['sha256'] + '  ' + args[1]).encode(), b'', False
        if args[0] == '/system/bin/linker64':
            return (b'\tlibc.so => /system/lib64/libc.so (0x71234567)\n'
                    b'\tlibm.so => /system/lib64/libm.so (0x71234568)\n'
                    b'\tlibdl.so => /apex/com.android.runtime/lib64/bionic/libdl.so (0x71234569)'), b'', False
        if args[:2] == ['/system/bin/toybox', 'timeout'] and '-m' in args:
            self.assertEqual(args[:5], ['/system/bin/toybox', 'timeout', '-s', 'KILL', '3'])
            self.assertEqual(timeout, 8)
            self.assertEqual(args[-1], 'probe' if load_failure else smoke.PROMPT)
            if load_failure:
                self.assertEqual(code, 1)
                return b'', b'error: unable to load model', False
            return smoke.PROMPT.encode() + b'Bonjour.\n', DECODED, False
        return b'', b'', False

    def test_consent_before_any_transport_or_weight_read(self):
        self.args.accept_terms_sha256 = '0' * 64
        with patch.object(smoke, 'invoke') as invoke, patch.object(smoke, 'verify_file', wraps=smoke.verify_file) as verify:
            with self.assertRaisesRegex(RuntimeError, 'acceptance'):
                android.run(self.args)
            invoke.assert_not_called()
            self.assertEqual([c.args[0].name for c in verify.call_args_list], [pin(b'terms')['sha256']])

    def test_exact_target_quoted_prompt_real_case_commands_and_identity(self):
        with patch.object(smoke, 'invoke', side_effect=self.fake):
            android.run(self.args)
        engines = [c for c in self.calls if '-m ' in c[0][-1]]
        self.assertEqual(len(engines), 3)
        self.assertIn('missing.gguf', engines[0][0][-1])
        self.assertIn('truncated.gguf', engines[1][0][-1])
        self.assertTrue(any(data == b'GGUF\x03\0\0\0' for data in self.pushed.values()))
        self.assertIn('rm -r', self.calls[-1][0][-1])
        self.assertIn('test ! -e', self.calls[-1][0][-1])

    def test_unrecognized_provider_record_fail_closed(self):
        def bad(command, *args, **kwargs):
            result = self.fake(command, *args, **kwargs)
            if 'linker64' in command[-1]:
                return result[0] + b'\nUNRECOGNIZED PROVIDER RECORD', result[1], result[2]
            return result
        with patch.object(smoke, 'invoke', side_effect=bad):
            with self.assertRaisesRegex(RuntimeError, 'unknown/malformed'):
                android.run(self.args)

    def test_linker_records_strict_unique_canonical_nonempty(self):
        valid = ('\tlinux-vdso.so.1 => [vdso] (0x71234566)\n'
                 '\tlibc.so => /system/lib64/libc.so (0x71234567)\n'
                 '\tlibm.so => /apex/com.android.runtime/lib64/bionic/libm.so (0x71234568)')
        self.assertEqual(android.parse_linker_providers(valid),
                         ['/apex/com.android.runtime/lib64/bionic/libm.so',
                          '/system/lib64/libc.so'])
        for raw in ('', '   \n',
                    valid + '\nUNRECOGNIZED PROVIDER RECORD',
                    valid + '\n\tlibm.so => /apex/com.android.runtime/lib64/bionic/libm.so (0x71234568)',
                    valid + '\n\tlinux-vdso.so.1 => [vdso] (0x71234569)',
                    valid.replace('/system/lib64/libc.so', '/system/lib64/libc.so '),
                    valid.replace('/apex/com.android.runtime/lib64/bionic/libm.so', '/data/local/tmp/libm.so'),
                    valid.replace('/apex/com.android.runtime/lib64/bionic/libm.so', '/system/../libm.so'),
                    'libc.so => /system/lib64/libc.so (0x71234567)',
                    '\tlinux-vdso.so.1 => [vdso] (0x71234566)',
                    '\tlinux-vdso.so.1 => [vdso] (0x71234566)\n'
                    '\tlinux-vdso.so.1 => [vdso] (0x71234567)'):
            with self.subTest(raw=raw), self.assertRaises(RuntimeError):
                android.parse_linker_providers(raw)

    def test_failure_timeout_bad_hash_and_cleanup_fail_closed(self):
        for trigger in ('push', 'engine', 'timeout', 'hash', 'cleanup', 'providers', 'truncated'):
            self.calls.clear()
            def failing(command, *args, **kwargs):
                result = self.fake(command, *args, **kwargs)
                text = command[-1]
                if ((trigger == 'push' and command[3] == 'push')
                    or (trigger == 'engine' and '-m ' in text)
                    or (trigger == 'cleanup' and 'rm -r' in text)):
                    raise RuntimeError('synthetic command failure')
                if trigger == 'timeout' and '-m ' in text:
                    raise subprocess.TimeoutExpired(command, 1)
                if trigger == 'hash' and 'sha256sum' in text:
                    return b'wrong hash', b'', False
                if trigger == 'providers' and 'linker64' in text:
                    return b'', b'', False
                if trigger == 'truncated' and 'sha256sum' in text:
                    return b'hash', b'', True
                return result
            with self.subTest(trigger=trigger), patch.object(smoke, 'invoke', side_effect=failing):
                with self.assertRaises((RuntimeError, subprocess.TimeoutExpired)):
                    android.run(self.args)
                self.assertIn('rm -r', self.calls[-1][0][-1])

    def test_adb_no_pty_and_real_stream_validation(self):
        device = android.Android(self.args.adb, self.args.serial, self.args.avd_name,
                                 self.args.device_root, 5, 1024)
        command = [str(device.root / 'llama-simple'), '-m', str(device.root / 'missing.gguf')]
        def process(argv, stdout, stderr, **kwargs):
            self.assertEqual(argv[3:5], ['shell', '-T'])
            self.assertEqual(shlex.split(shlex.split(argv[-1])[2])[-3:], command)
            stdout.write(b'error: unable to load model')
            return subprocess.CompletedProcess(argv, 1)
        with patch.object(smoke.subprocess, 'run', side_effect=process):
            with self.assertRaisesRegex(RuntimeError, 'stderr'):
                device.invoke(command, 1, 100, 1, load_failure=True)
        with patch.object(smoke.subprocess, 'run', side_effect=subprocess.TimeoutExpired(command, 1)):
            with self.assertRaisesRegex(RuntimeError, 'exceeded'):
                device.invoke(command, 1, 100, 1, load_failure=True)

    @unittest.skipUnless(sys.platform.startswith('linux'), 'Linux/KVM owned-emulator lifetime shell')
    def test_outer_owner_trap_success_failure_and_timeout(self):
        import ctypes
        import signal
        try:
            libc = ctypes.CDLL('libc.so.6', use_errno=True)
        except OSError:
            self.skipTest('Linux child subreaper unavailable on this host')
        PR_SET_CHILD_SUBREAPER = 36
        PR_GET_CHILD_SUBREAPER = 37
        previous = ctypes.c_int()
        if libc.prctl(PR_GET_CHILD_SUBREAPER, ctypes.byref(previous), 0, 0, 0) != 0:
            self.skipTest('Linux child subreaper unavailable on this host')
        had_subreaper = previous.value
        if libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
            self.skipTest('Linux child subreaper unavailable on this host')
        try:
            script = (Path(android.__file__).parent / 'android_ci.sh').read_text()
            cleanup = script[script.index('cleanup() {'):script.index('export ANDROID_AVD_HOME')]
            outsider = subprocess.Popen(['sleep', '30'])
            try:
                for ending, expected in (('exit 0', 0), ('exit 7', 7), ('timeout 0.1s sleep 30', 124)):
                    owner = self.root / 'owned'
                    owner.mkdir()
                    (self.root / 'emulator.log').write_text('bounded synthetic emulator log')
                    # Owned wrapper in its own session with one descendant; FIFO
                    # readiness avoids startup polling. Group kill must end both
                    # while an unrelated process survives. SIGKILL can terminate
                    # the parent and child concurrently, so a supervisor may reap
                    # the child before this subreaper can wait for it; check /proc
                    # for a live survivor and assert SIGKILL whenever waitable.
                    inner = ('sleep 30 & echo $! > ' + shlex.quote(str(owner / 'child'))
                             + '; echo > ' + shlex.quote(str(owner / 'ready')) + '; wait')
                    command = ('set -e; owner=' + shlex.quote(str(owner))
                               + '; build=' + shlex.quote(str(self.root))
                               + '; ENGINE_OUTPUT_BYTES=64'
                               + '; mkfifo ' + shlex.quote(str(owner / 'ready'))
                               + '; setsid bash -c ' + shlex.quote(inner)
                               + ' & emulator_pid=$!; echo "$emulator_pid";\n'
                               + 'cat ' + shlex.quote(str(owner / 'ready'))
                               + ' > /dev/null; child=$(cat ' + shlex.quote(str(owner / 'child'))
                               + '); echo "$child";\n'
                               + cleanup + '\n' + ending)
                    output = b''
                    try:
                        try:
                            result = subprocess.run(['bash', '-c', command], capture_output=True, timeout=10)
                        except subprocess.TimeoutExpired as error:
                            output = error.stdout or b''
                            raise
                        output = result.stdout
                        lines = output.splitlines()
                        pid, child = int(lines[0]), int(lines[1])
                        self.assertEqual(result.returncode, expected, result.stderr)
                        # Direct wrapper was waited by the outer shell; it is gone.
                        with self.assertRaises(ProcessLookupError):
                            os.kill(pid, 0)
                        import time
                        deadline = time.monotonic() + 2
                        while True:
                            try:
                                reaped, status = os.waitpid(child, os.WNOHANG)
                            except ChildProcessError:
                                reaped, status = 0, None
                            if reaped == child:
                                self.assertTrue(os.WIFSIGNALED(status), status)
                                self.assertEqual(os.WTERMSIG(status), signal.SIGKILL)
                                break
                            try:
                                stat = Path(f'/proc/{child}/stat').read_text()
                            except FileNotFoundError:
                                break
                            state = stat[stat.rfind(')') + 2:].split()[0]
                            if state == 'Z':
                                break
                            if time.monotonic() >= deadline:
                                self.fail(f'owned descendant {child} survived process-group cleanup')
                            time.sleep(0.01)
                        try:
                            os.kill(child, 0)
                        except ProcessLookupError:
                            pass
                        else:
                            # A zombie is not executing; a different reaper may
                            # own it after concurrent SIGKILL delivery.
                            try:
                                stat = Path(f'/proc/{child}/stat').read_text()
                            except FileNotFoundError:
                                pass
                            else:
                                self.assertEqual(stat[stat.rfind(')') + 2:].split()[0], 'Z')
                        self.assertFalse(owner.exists())
                        self.assertIsNone(outsider.poll())
                    finally:
                        # A failed assertion/outer timeout must not leak the test
                        # group. Its PID is printed before the readiness barrier.
                        if output:
                            group = int(output.splitlines()[0])
                            try:
                                os.killpg(group, signal.SIGKILL)
                            except ProcessLookupError:
                                pass
                            while True:
                                try:
                                    os.waitpid(-group, 0)
                                except ChildProcessError:
                                    break
            finally:
                outsider.kill()
                outsider.wait()
        finally:
            self.assertEqual(libc.prctl(PR_SET_CHILD_SUBREAPER, had_subreaper, 0, 0, 0), 0)

    def test_invalid_targets_and_roots(self):
        for target in ('', 'device', 'emulator-5554;id', '-s'):
            with self.assertRaises(argparse.ArgumentTypeError):
                android.serial(target)
        for root in ('/', '/sdcard', '/data/local/tmp/../other', '/data/local/tmp/', '/data/local/tmp/a;b'):
            with self.assertRaises(argparse.ArgumentTypeError):
                android.device_root(root)
        with patch.object(smoke, 'invoke', return_value=(b'other-avd\nOK', b'', False)):
            with self.assertRaisesRegex(RuntimeError, 'owned AVD'):
                android.run(self.args)

    def test_acquisition_exact_fixtures_and_transfer_failure(self):
        contents = {entry['url']: (self.root / entry['sha256']).read_bytes() for entry in self.entries}
        calls = []
        def download(url, **kwargs):
            calls.append(url)
            return io.BytesIO(contents[url])
        with patch.object(acquire.urllib.request, 'urlopen', side_effect=download):
            directory = self.root / 'acquired'
            acquire.acquire(directory, self.args.accept_terms_sha256, 1)
            self.assertEqual(calls, [entry['url'] for entry in self.entries])
            smoke.verify_fixtures(directory, self.args.accept_terms_sha256)
        with patch.object(acquire.urllib.request, 'urlopen', side_effect=OSError('synthetic transfer failure')):
            with self.assertRaisesRegex(OSError, 'transfer failure'):
                acquire.acquire(self.root / 'failed', self.args.accept_terms_sha256, 1)

    def test_acquisition_refuses_before_weight_network_read(self):
        calls = []
        def download(url, **kwargs):
            calls.append(url)
            return io.BytesIO(b'terms')
        with patch.object(acquire.urllib.request, 'urlopen', side_effect=download):
            with self.assertRaisesRegex(RuntimeError, 'acceptance'):
                acquire.acquire(self.root / 'acquired', '0' * 64, 1)
        self.assertEqual(calls, [self.entries[0]['url']])


if __name__ == '__main__':
    unittest.main()
