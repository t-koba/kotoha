"""POSIX-only external time/RSS watchdog for disposable hosted editor trials."""
import argparse
import math
import os
import signal
import subprocess
import sys
import tempfile
import time


class _ProfileCancelled(Exception):
    def __init__(self, signal_number):
        self.signal_number = signal_number


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
    try:
        return run(args, command)
    except _ProfileCancelled as cancelled:
        print(f'WATCHDOG cancelled profile: signal={cancelled.signal_number}', flush=True)
        return 128 + cancelled.signal_number


def run(args, command):
    process = None
    pending_signal = None
    previous_handlers = {}

    def handle_signal(signum, _frame):
        nonlocal pending_signal
        pending_signal = signum
        if process is not None:
            # Prevent a second cancellation signal from interrupting teardown.
            for handled in previous_handlers:
                signal.signal(handled, signal.SIG_IGN)
            raise _ProfileCancelled(signum)

    for signum in (signal.SIGINT, signal.SIGTERM):
        previous_handlers[signum] = signal.signal(signum, handle_signal)

    peak_kib = 0
    try:
        with tempfile.TemporaryDirectory(prefix='kotoha-profile-watch-') as scratch:
            try:
                if pending_signal is not None:
                    raise _ProfileCancelled(pending_signal)
                process = subprocess.Popen(command, start_new_session=True,
                                           env=dict(os.environ, TMPDIR=scratch))
                if pending_signal is not None:
                    raise _ProfileCancelled(pending_signal)
                start = time.monotonic()
                deadline = start + args.seconds
                last_rss_kib = None

                def stop_for_wall_budget():
                    observed = 'unavailable' if last_rss_kib is None else last_rss_kib
                    elapsed = time.monotonic() - start
                    print(f'WATCHDOG stopped profile: reason=wall-budget '
                          f'elapsed_seconds={elapsed:.2f} group_rss_kib={observed}', flush=True)
                    return 124

                while True:
                    status = process.poll()
                    if status is not None:
                        return status
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return stop_for_wall_budget()
                    try:
                        output = subprocess.check_output(
                            ['ps', '-axo', 'pgid=,rss='], text=True, timeout=remaining
                        )
                    except subprocess.TimeoutExpired:
                        status = process.poll()
                        if status is not None:
                            return status
                        return stop_for_wall_budget()
                    rss_kib = sum(
                        int(fields[1])
                        for line in output.splitlines()
                        if len(fields := line.split()) == 2 and int(fields[0]) == process.pid
                    )
                    peak_kib = max(peak_kib, rss_kib)
                    last_rss_kib = rss_kib
                    status = process.poll()
                    if status is not None:
                        return status
                    if rss_kib > args.rss_mib * 1024:
                        print(f'WATCHDOG stopped profile: reason=rss-budget '
                              f'seconds={time.monotonic() - (deadline - args.seconds):.2f} '
                              f'group_rss_kib={rss_kib}', flush=True)
                        return 124
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        return stop_for_wall_budget()
                    time.sleep(min(args.poll_seconds, remaining))
            finally:
                # Ignore repeated signals while killing and reaping the group.
                for signum in previous_handlers:
                    signal.signal(signum, signal.SIG_IGN)
                if process is not None:
                    try:
                        os.killpg(process.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    process.wait()
                print(f'WATCHDOG sampled_group_peak_kib={peak_kib}', flush=True)
    finally:
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)


if __name__ == '__main__':
    sys.exit(main())
