"""Small subprocess safety regressions; no Flutter or large payloads."""
import os
from pathlib import Path
import re
import select
import signal
import subprocess
import sys
import unittest

WATCH = Path(__file__).with_name('watch_import_profile.py')


@unittest.skipUnless(os.name == 'posix', 'The editor watchdog is POSIX-only')
class WatchdogTest(unittest.TestCase):
    def run_profile(self, code, *, seconds='5', rss='128', poll='0.02'):
        return subprocess.run(
            [sys.executable, str(WATCH), '--seconds', seconds, '--rss-mib', rss,
             '--poll-seconds', poll, '--', sys.executable, '-c', code],
            capture_output=True, text=True, timeout=10,
        )

    def test_exit_code_and_fixture_cleanup(self):
        result = self.run_profile(
            'import pathlib,tempfile,sys; '
            'p=pathlib.Path(tempfile.gettempdir())/"synthetic.txt"; '
            'p.write_text("fixture"); print(p,flush=True); sys.exit(7)'
        )
        self.assertEqual(result.returncode, 7, result.stderr)
        self.assertFalse(Path(result.stdout.splitlines()[0]).parent.exists())

    def test_time_and_rss_budgets_stop_and_clean_fixture(self):
        for budgets in [{'seconds': '0.2'}, {'rss': '1'}]:
            with self.subTest(budgets=budgets):
                result = self.run_profile(
                    'import pathlib,tempfile,time; '
                    'p=pathlib.Path(tempfile.gettempdir())/"synthetic.txt"; '
                    'p.write_text("fixture"); print(p,flush=True); time.sleep(30)',
                    **budgets,
                )
                self.assertEqual(result.returncode, 124, result.stderr)
                self.assertIn('WATCHDOG stopped profile', result.stdout)
                # The RSS ceiling can stop the interpreter before it prints.
                first = result.stdout.splitlines()[0]
                if not first.startswith('WATCHDOG'):
                    self.assertFalse(Path(first).parent.exists())

    def test_poll_interval_is_limited_by_remaining_wall_time(self):
        result = self.run_profile(
            'import time; time.sleep(30)', seconds='0.2', rss='128', poll='2'
        )
        self.assertEqual(result.returncode, 124, result.stderr)
        match = re.search(
            r'WATCHDOG stopped profile: reason=wall-budget elapsed_seconds=([0-9.]+)',
            result.stdout,
        )
        self.assertIsNotNone(match, result.stdout)
        self.assertLess(float(match.group(1)), 1.0, result.stdout)

    def test_sigterm_kills_child_and_cleans_its_fixture(self):
        code = (
            'import os,pathlib,tempfile,time; '
            'p=pathlib.Path(tempfile.gettempdir())/"synthetic.txt"; '
            'p.write_text("fixture"); print(os.getpid(),p,flush=True); time.sleep(30)'
        )
        process = subprocess.Popen(
            [sys.executable, str(WATCH), '--seconds', '10', '--rss-mib', '128',
             '--poll-seconds', '0.02', '--', sys.executable, '-c', code],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1,
        )
        child_pid = None
        fixture = None
        try:
            readable, _, _ = select.select([process.stdout], [], [], 5)
            self.assertTrue(readable, 'profile child did not create its fixture')
            child_pid_text, fixture_text = process.stdout.readline().strip().split(' ', 1)
            child_pid = int(child_pid_text)
            fixture = Path(fixture_text)
            self.assertTrue(fixture.is_file())

            process.send_signal(signal.SIGTERM)
            output, error = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 128 + signal.SIGTERM, error)
            self.assertIn('WATCHDOG cancelled profile', output)
            self.assertFalse(fixture.exists())
            self.assertFalse(fixture.parent.exists())
            with self.assertRaises(ProcessLookupError):
                os.kill(child_pid, 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(timeout=5)
            if child_pid is not None:
                try:
                    os.killpg(child_pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            if fixture is not None:
                import shutil
                shutil.rmtree(fixture.parent, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
