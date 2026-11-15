"""Regression tests for the portal probe's sanitized child-stage channel."""
import errno
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.linux_portal_probe import (
    CLIENT_STARTED_MARKER,
    ProbeFailure,
    PYTHON_PREFLIGHT_MARKER,
    _run_sandbox_preflight,
    _sandbox_bwrap_failure_stage,
    _sandbox_client_prefix,
    _sandbox_client_failure_stage,
    _sandbox_client_started,
    _sandbox_failure_stage,
)


class SandboxPrefixTest(unittest.TestCase):
    def test_binds_host_sources_before_masking_home_without_exposing_fixture(self):
        app_info = Path("/home/runner/work/_temp/probe/flatpak-info")
        script = Path("/home/runner/work/kotoha/kotoha/tools/linux_portal_probe.py")
        mountpoint = "/tmp/kotoha-portal-runtime/doc"
        fixture = Path("/home/runner/work/_temp/probe/fixture.md")
        dbus_address = "unix:path=/tmp/bus"
        runtime = Path("/tmp/kotoha-portal-runtime")
        prefix, stages = _sandbox_client_prefix(
            app_info, script, mountpoint, dbus_address, fixture, runtime
        )
        self.assertEqual(
            prefix,
            [
                "bwrap", "--die-with-parent", "--unshare-all",
                *(option for _, options in stages for option in options),
                "--",
            ],
        )
        self.assertEqual(
            [stage for stage, _ in stages],
            [
                "sandbox-bwrap-core-setup-failed",
                "sandbox-bwrap-run-mask-failed",
                "sandbox-bwrap-proc-bind-failed",
                "sandbox-bwrap-dev-bind-failed",
                "sandbox-bwrap-app-info-bind-failed",
                "sandbox-bwrap-client-script-bind-failed",
                "sandbox-bwrap-documents-bind-failed",
                "sandbox-bwrap-home-mask-failed",
                "sandbox-bwrap-environment-failed",
            ],
        )
        home_mask = next(
            index
            for index in range(len(prefix) - 1)
            if prefix[index:index + 2] == ["--tmpfs", "/home"]
        )
        self.assertLess(prefix.index(str(app_info)), home_mask)
        self.assertLess(prefix.index(str(script)), home_mask)
        self.assertLess(prefix.index(mountpoint), home_mask)
        self.assertEqual(prefix.count(str(fixture)), 1)
        self.assertEqual(
            prefix[prefix.index(str(fixture)) - 1], "KOTOHA_PORTAL_FIXTURE_PATH"
        )


class SandboxFailureStageTest(unittest.TestCase):
    def test_classifies_common_bwrap_failures_without_host_paths(self):
        cases = (
            (
                "bwrap: No permissions to create a new namespace at /home/private",
                "sandbox-bwrap-namespace-failed",
            ),
            (
                "bwrap: Creating new namespace failed: Operation not permitted",
                "sandbox-bwrap-namespace-failed",
            ),
            (
                "bwrap: Can't find source path /home/private/script.py",
                "sandbox-bwrap-source-path-missing",
            ),
            (
                "bwrap: Can't make /tmp/private: Operation not permitted",
                "sandbox-bwrap-operation-not-permitted",
            ),
            ("unexpected /tmp/private diagnostic", "sandbox-bwrap-setup-failed"),
        )
        for diagnostic, expected in cases:
            with self.subTest(expected=expected):
                stage = _sandbox_bwrap_failure_stage(diagnostic)
                self.assertEqual(stage, expected)
                self.assertNotIn("/home/private", stage)
                self.assertNotIn("/tmp/private", stage)

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

    def test_forwards_fixed_bwrap_preflight_codes(self):
        for stage in (
            "sandbox-bwrap-setup-failed",
            "sandbox-bwrap-namespace-failed",
            "sandbox-bwrap-source-path-missing",
            "sandbox-bwrap-operation-not-permitted",
            "sandbox-bwrap-permission-denied",
            "sandbox-bwrap-core-setup-failed",
            "sandbox-bwrap-run-mask-failed",
            "sandbox-bwrap-proc-bind-failed",
            "sandbox-bwrap-dev-bind-failed",
            "sandbox-bwrap-app-info-bind-failed",
            "sandbox-bwrap-client-script-bind-failed",
            "sandbox-bwrap-documents-bind-failed",
            "sandbox-bwrap-home-mask-failed",
            "sandbox-bwrap-environment-failed",
            "sandbox-bwrap-prefix-inconsistent",
            "sandbox-bwrap-timeout",
            "sandbox-bwrap-executable-missing",
            "sandbox-bwrap-exec-failed",
        ):
            with self.subTest(stage=stage):
                self.assertEqual(
                    _sandbox_failure_stage(f"Linux portal probe failed: {stage}\n"),
                    stage,
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

    def test_unknown_preflight_failure_is_localized_by_cumulative_setup_stage(self):
        private = "/home/private/unclassified"
        prefix = [
            "bwrap", "--die-with-parent", "--unshare-all",
            "--ro-bind", "/", "/", "--tmpfs", "/run", "--",
        ]
        stages = [
            ("sandbox-bwrap-core-setup-failed", ["--ro-bind", "/", "/"]),
            ("sandbox-bwrap-run-mask-failed", ["--tmpfs", "/run"]),
        ]
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = [
                subprocess.CompletedProcess([], 1, "", private),
                subprocess.CompletedProcess([], 0, "", ""),
                subprocess.CompletedProcess([], 1, "", private),
            ]
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(prefix, stages)
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-run-mask-failed")
        self.assertNotIn(private, str(caught.exception))
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                [*prefix, "/bin/true"],
                [*prefix[:3], "--ro-bind", "/", "/", "--", "/bin/true"],
                [
                    *prefix[:3], "--ro-bind", "/", "/", "--tmpfs", "/run",
                    "--", "/bin/true",
                ],
            ],
        )

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

    def test_preflight_classifies_bwrap_timeout_without_forwarding_output(self):
        private = "/private/timeout output"
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            run.side_effect = subprocess.TimeoutExpired("private command", 5, stderr=private)
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"])
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-timeout")
        self.assertNotIn(private, str(caught.exception))

    def test_preflight_classifies_bwrap_exec_errors_without_forwarding_paths(self):
        failures = (
            (
                FileNotFoundError(errno.ENOENT, "missing executable", "/private/bwrap"),
                "sandbox-bwrap-executable-missing",
            ),
            (
                PermissionError(errno.EACCES, "execution denied", "/private/bwrap"),
                "sandbox-bwrap-exec-failed",
            ),
        )
        for failure, expected_stage in failures:
            with self.subTest(stage=expected_stage):
                with patch("tools.linux_portal_probe.subprocess.run") as run:
                    run.side_effect = failure
                    with self.assertRaises(ProbeFailure) as caught:
                        _run_sandbox_preflight(["bwrap", "--", "prefix"])
                self.assertEqual(caught.exception.stage, expected_stage)
                self.assertNotIn("/private/bwrap", str(caught.exception))

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
