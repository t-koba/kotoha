"""Small subprocess safety regressions; no Flutter or large payloads."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

WATCH = Path(__file__).with_name('watch_import_profile.py')


@unittest.skipUnless(os.name == 'posix', 'The editor watchdog is POSIX-only')
class WatchdogTest(unittest.TestCase):
    def run_profile(self, code, *, seconds='5', rss='128'):
        return subprocess.run(
            [sys.executable, str(WATCH), '--seconds', seconds, '--rss-mib', rss,
             '--poll-seconds', '0.02', '--', sys.executable, '-c', code],
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


if __name__ == '__main__':
    unittest.main()
