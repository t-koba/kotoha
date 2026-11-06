"""POSIX-only external time/RSS watchdog for disposable hosted editor trials."""
import argparse
import math
import os
import signal
import subprocess
import sys
import time
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--seconds', type=float, required=True)
    parser.add_argument('--rss-mib', type=float, required=True)
    parser.add_argument('--poll-seconds', type=float, required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    budgets = (args.seconds, args.rss_mib, args.poll_seconds)
    if os.name != 'posix' or not all(math.isfinite(n) and n > 0 for n in budgets) or not command:
        parser.error('POSIX, positive budgets, and a command are required')
    # Own the child's synthetic fixtures too, including on watchdog termination.
    with tempfile.TemporaryDirectory(prefix='kotoha-profile-watch-') as scratch:
        return run(args, command, dict(os.environ, TMPDIR=scratch))


def run(args, command, environment):
    process = subprocess.Popen(command, start_new_session=True, env=environment)
    start = time.monotonic()
    peak_kib = 0
    try:
        while process.poll() is None:
            # Observe the entire process group, including flutter_tester. A
            # sampled sum is a safety estimate, not a process high-water metric.
            output = subprocess.check_output(
                ['ps', '-axo', 'pgid=,rss='], text=True, timeout=args.seconds
            )
            rss_kib = sum(int(rss) for group, rss in
                          (line.split() for line in output.splitlines())
                          if int(group) == process.pid)
            peak_kib = max(peak_kib, rss_kib)
            if time.monotonic() - start >= args.seconds or rss_kib > args.rss_mib * 1024:
                print(f'WATCHDOG stopped profile: seconds={time.monotonic() - start:.2f} '
                      f'group_rss_kib={rss_kib}', flush=True)
                return 124
            time.sleep(args.poll_seconds)
        return process.returncode
    finally:
        # Kill all descendants on success, failure, or an observation error.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait()
        print(f'WATCHDOG sampled_group_peak_kib={peak_kib}', flush=True)


if __name__ == '__main__':
    sys.exit(main())
