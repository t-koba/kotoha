"""Regression tests for the portal probe's sanitized child-stage channel."""
import subprocess
import sys
import unittest
from unittest.mock import patch

from tools.linux_portal_probe import (
    CLIENT_STARTED_MARKER,
    ProbeFailure,
    PYTHON_PREFLIGHT_MARKER,
    _run_sandbox_preflight,
    _sandbox_client_failure_stage,
    _sandbox_client_started,
    _sandbox_failure_stage,
)


class SandboxFailureStageTest(unittest.TestCase):
    def test_forwards_only_short_allowlisted_stage_codes(self):
        self.assertEqual(
            _sandbox_failure_stage(
                "debug output\nLinux portal probe failed: filechooser-response-timeout\n"
            ),
            "filechooser-response-timeout",
        )
        invalid = (
            "/tmp/private",
            "file:///home/user/document.md",
            "stage_with_underscore",
            "UPPERCASE",
            "a" * 65,
        )
        for value in invalid:
            with self.subTest(value=value[:24]):
                self.assertIsNone(
                    _sandbox_failure_stage(f"Linux portal probe failed: {value}\n")
                )

    def test_ignores_diagnostics_outside_bounded_tail(self):
        stderr = "Linux portal probe failed: stage\n" + "x" * 8192
        self.assertIsNone(_sandbox_failure_stage(stderr))

    def test_requires_exact_marker(self):
        self.assertIsNone(_sandbox_failure_stage("prefix Linux portal probe failed: stage\n"))
        self.assertIsNone(_sandbox_failure_stage("ordinary client failure\n"))

    def test_distinguishes_started_client_from_launch_failure(self):
        self.assertTrue(_sandbox_client_started(f"{CLIENT_STARTED_MARKER}\n"))
        self.assertFalse(_sandbox_client_started("bwrap setup failed\n"))

    def test_preflight_classifies_bwrap_failure_without_forwarding_output(self):
        private = "/home/private/path: noisy diagnostic"
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 1, "", private)
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"])
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-setup-failed")
        self.assertNotIn(private, str(caught.exception))
        run.assert_called_once()

    def test_preflight_classifies_python_failure_and_missing_marker(self):
        private = "secret stderr /tmp/private"
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, "startup noise", private),
            ]
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"])
        self.assertEqual(caught.exception.stage, "sandbox-python-startup-failed")
        self.assertNotIn(private, str(caught.exception))

    def test_preflight_timeout_is_fixed_bwrap_setup_failure(self):
        private = "/private/timeout output"
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = subprocess.TimeoutExpired("private command", 5, stderr=private)
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"])
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-setup-failed")
        self.assertNotIn(private, str(caught.exception))

    def test_python_preflight_timeout_is_classified_as_python_startup(self):
        private = "/private/python timeout output"
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.TimeoutExpired("private command", 5, stderr=private),
            ]
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"])
        self.assertEqual(caught.exception.stage, "sandbox-python-startup-failed")
        self.assertNotIn(private, str(caught.exception))

    def test_preflight_uses_same_prefix_for_both_fixed_checks(self):
        prefix = ["bwrap", "--ro-bind", "/", "/", "--"]
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 0, PYTHON_PREFLIGHT_MARKER + "\n", ""),
            ]
            _run_sandbox_preflight(prefix)
        commands = [entry.args[0] for entry in run.call_args_list]
        self.assertEqual(commands[0], prefix + ["/bin/true"])
        self.assertEqual(commands[1][:len(prefix)], prefix)
        self.assertEqual(commands[1][len(prefix):len(prefix) + 2], [sys.executable, "-c"])

    def test_client_startup_failure_stage_never_forwards_child_output(self):
        private = "python traceback at /home/private/Project"
        self.assertEqual(
            _sandbox_client_failure_stage(private),
            "sandbox-client-script-startup-failed",
        )
        self.assertEqual(
            _sandbox_client_failure_stage(f"{CLIENT_STARTED_MARKER}\n{private}"),
            "sandbox-client-failed",
        )
        self.assertEqual(
            _sandbox_client_failure_stage(
                f"{CLIENT_STARTED_MARKER}\n"
                "Linux portal probe failed: filechooser-response-timeout\n"
            ),
            "sandbox-client-filechooser-response-timeout",
        )

    def test_start_marker_survives_diagnostics_beyond_stage_tail(self):
        stderr = CLIENT_STARTED_MARKER + "\n" + "GLib warning\n" * 700
        self.assertTrue(_sandbox_client_started(stderr))
        self.assertIsNone(_sandbox_failure_stage(stderr))


if __name__ == "__main__":
    unittest.main()
