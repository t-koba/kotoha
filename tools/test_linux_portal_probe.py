"""Regression tests for the portal probe's sanitized child-stage channel."""
import errno
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tools.linux_portal_probe import (
    CLIENT_STARTED_MARKER,
    ProbeFailure,
    PYTHON_PREFLIGHT_MARKER,
    SANDBOX_PREFLIGHT_EXECUTABLE,
    SANDBOX_PYTHON_EXECUTABLE,
    _run_sandbox_preflight,
    _sandbox_bwrap_failure_stage,
    _sandbox_client_prefix,
    _sandbox_client_failure_stage,
    _sandbox_client_started,
    _sandbox_failure_stage,
)


class SandboxPrefixTest(unittest.TestCase):
    def test_private_root_exposes_only_client_inputs_without_fixture(self):
        app_info_fd = 11
        script = Path("/home/runner/work/kotoha/kotoha/tools/linux_portal_probe.py")
        mountpoint = "/tmp/kotoha-portal-runtime/doc"
        fixture = Path("/home/runner/work/_temp/probe/fixture.md")
        dbus_address = "unix:path=/tmp/kotoha-portal-runtime/bus"
        runtime = Path("/tmp/kotoha-portal-runtime")
        prefix, stages = _sandbox_client_prefix(
            app_info_fd, script, mountpoint, dbus_address, fixture, runtime
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
                "sandbox-bwrap-base-runtime-failed",
                "sandbox-bwrap-run-mask-failed",
                "sandbox-bwrap-tmp-mask-failed",
                "sandbox-bwrap-proc-bind-failed",
                "sandbox-bwrap-dev-bind-failed",
                "sandbox-bwrap-app-info-bind-failed",
                "sandbox-bwrap-client-script-bind-failed",
                "sandbox-bwrap-runtime-bind-failed",
                "sandbox-bwrap-documents-bind-failed",
                "sandbox-bwrap-home-mask-failed",
                "sandbox-bwrap-environment-failed",
                "sandbox-bwrap-root-remount-failed",
            ],
        )
        self.assertEqual(
            stages[0],
            (
                "sandbox-bwrap-base-runtime-failed",
                [
                    "--tmpfs", "/",
                    "--ro-bind", "/usr", "/usr",
                    "--ro-bind", "/lib", "/lib",
                    "--ro-bind", "/lib64", "/lib64",
                    "--ro-bind", "/etc", "/etc",
                ],
            ),
        )
        self.assertEqual(
            stages[1], ("sandbox-bwrap-run-mask-failed", ["--tmpfs", "/run"])
        )
        self.assertEqual(SANDBOX_PREFLIGHT_EXECUTABLE, "/usr/bin/true")
        self.assertEqual(SANDBOX_PYTHON_EXECUTABLE, "/usr/bin/python3")
        self.assertTrue(os.access(SANDBOX_PREFLIGHT_EXECUTABLE, os.X_OK))
        self.assertTrue(os.access(SANDBOX_PYTHON_EXECUTABLE, os.X_OK))
        self.assertNotIn(["--bind", "/", "/"], [options for _, options in stages])
        self.assertNotIn(["--ro-bind", "/", "/"], [options for _, options in stages])
        self.assertEqual(
            stages[-1],
            ("sandbox-bwrap-root-remount-failed", ["--remount-ro", "/"]),
        )
        home_mask = next(
            index
            for index in range(len(prefix) - 1)
            if prefix[index:index + 2] == ["--tmpfs", "/home"]
        )
        app_info_arg = prefix.index(str(app_info_fd))
        self.assertEqual(prefix[app_info_arg - 1], "--ro-bind-data")
        self.assertEqual(prefix[app_info_arg + 1], "/.flatpak-info")
        app_info_bind = prefix.index("--ro-bind-data")
        root_remount = prefix.index("--remount-ro")
        self.assertLess(app_info_bind, root_remount)
        self.assertEqual(prefix[root_remount + 1], "/")
        self.assertLess(prefix.index(str(script)), home_mask)
        self.assertLess(prefix.index(str(runtime)), home_mask)
        self.assertLess(prefix.index(mountpoint), home_mask)
        self.assertNotIn("/home/runner/work/_temp/probe/flatpak-info", prefix)
        self.assertEqual(prefix.count(str(fixture)), 1)
        self.assertEqual(
            prefix[prefix.index(str(fixture)) - 1], "KOTOHA_PORTAL_FIXTURE_PATH"
        )


class RealBwrapPreflightTest(unittest.TestCase):
    @unittest.skipUnless(
        os.environ.get("KOTOHA_RUN_BWRAP_INTEGRATION") == "1"
        and shutil.which("bwrap") is not None,
        "real bwrap preflight is enabled only by the Ubuntu portal job",
    )
    def test_private_root_runs_bound_executables(self):
        _, stages = _sandbox_client_prefix(
            11,
            Path("/tmp/portal-probe.py"),
            "/tmp/kotoha-runtime/doc",
            "unix:path=/tmp/kotoha-runtime/bus",
            Path("/tmp/fixture.md"),
            Path("/tmp/kotoha-runtime"),
        )
        base_runtime = stages[0][1]
        prefix = [
            "bwrap", "--die-with-parent", "--unshare-all",
            *base_runtime,
            "--tmpfs", "/run",
            "--tmpfs", "/tmp",
            "--proc", "/proc",
            "--dev", "/dev",
            "--remount-ro", "/", "--",
        ]
        _run_sandbox_preflight(prefix)


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
                "bwrap: Can't create tmpfile for /home/private/.flatpak-info",
                "sandbox-bwrap-bind-file-tempfile-failed",
            ),
            (
                "bwrap: Can't set mode 444 on file to be used for "
                "/tmp/private/.flatpak-info",
                "sandbox-bwrap-bind-file-mode-failed",
            ),
            (
                "bwrap: Can't write data to file /home/private/.flatpak-info",
                "sandbox-bwrap-bind-file-copy-failed",
            ),
            (
                "bwrap: Can't create file at /tmp/private/.flatpak-info",
                "sandbox-bwrap-bind-file-target-failed",
            ),
            (
                "bwrap: Can't bind mount /bindfile/private on "
                "/home/private/.flatpak-info: Operation not permitted",
                "sandbox-bwrap-bind-file-mount-failed",
            ),
            ("bwrap: Invalid fd: 3", "sandbox-bwrap-data-fd-invalid"),
            (
                "bwrap: --ro-bind-data takes two arguments",
                "sandbox-bwrap-data-arguments-invalid",
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
                for private_path in ("/home/private", "/tmp/private", "/bindfile/private"):
                    self.assertNotIn(private_path, stage)

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
            "sandbox-bwrap-bind-file-tempfile-failed",
            "sandbox-bwrap-bind-file-mode-failed",
            "sandbox-bwrap-bind-file-copy-failed",
            "sandbox-bwrap-bind-file-target-failed",
            "sandbox-bwrap-bind-file-mount-failed",
            "sandbox-bwrap-data-fd-invalid",
            "sandbox-bwrap-data-arguments-invalid",
            "sandbox-bwrap-operation-not-permitted",
            "sandbox-bwrap-permission-denied",
            "sandbox-bwrap-base-runtime-failed",
            "sandbox-bwrap-run-mask-failed",
            "sandbox-bwrap-tmp-mask-failed",
            "sandbox-bwrap-proc-bind-failed",
            "sandbox-bwrap-dev-bind-failed",
            "sandbox-bwrap-app-info-bind-failed",
            "sandbox-bwrap-client-script-bind-failed",
            "sandbox-bwrap-runtime-bind-failed",
            "sandbox-bwrap-documents-bind-failed",
            "sandbox-bwrap-home-mask-failed",
            "sandbox-bwrap-environment-failed",
            "sandbox-bwrap-root-remount-failed",
            "sandbox-bwrap-data-fd-failed",
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
        base_runtime = [
            "--tmpfs", "/",
            "--ro-bind", "/usr", "/usr",
            "--ro-bind", "/lib", "/lib",
            "--ro-bind", "/lib64", "/lib64",
            "--ro-bind", "/etc", "/etc",
        ]
        prefix = ["bwrap", "--die-with-parent", "--unshare-all", *base_runtime, "--"]
        stages = [
            ("sandbox-bwrap-base-runtime-failed", base_runtime),
            ("sandbox-bwrap-run-mask-failed", ["--tmpfs", "/run"]),
        ]
        with tempfile.TemporaryFile(mode="w+b") as data:
            data.write(b"[Application]\nname=org.kotoha.portalprobe\n")
            data.flush()
            data.seek(4)
            data_fd = data.fileno()
            with patch("tools.linux_portal_probe.subprocess.run") as run:
                run.side_effect = [
                    subprocess.CompletedProcess([], 1, "", private),
                    subprocess.CompletedProcess([], 0, "", ""),
                    subprocess.CompletedProcess([], 1, "", private),
                ]
                with self.assertRaises(ProbeFailure) as caught:
                    _run_sandbox_preflight(prefix, stages, (data_fd,))
            self.assertEqual(data.tell(), 0)
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-run-mask-failed")
        self.assertNotIn(private, str(caught.exception))
        self.assertTrue(
            all(call.kwargs["pass_fds"] == (data_fd,) for call in run.call_args_list)
        )
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                [*prefix, SANDBOX_PREFLIGHT_EXECUTABLE],
                [*prefix[:3], *base_runtime, "--", SANDBOX_PREFLIGHT_EXECUTABLE],
                [
                    *prefix[:3], *base_runtime, "--tmpfs", "/run", "--",
                    SANDBOX_PREFLIGHT_EXECUTABLE,
                ],
            ],
        )

    def test_preflight_rejects_unseekable_metadata_fd_without_forwarding_error(self):
        with patch("tools.linux_portal_probe.subprocess.run") as run:
            with self.assertRaises(ProbeFailure) as caught:
                _run_sandbox_preflight(["bwrap", "--", "prefix"], pass_fds=(-1,))
        self.assertEqual(caught.exception.stage, "sandbox-bwrap-data-fd-failed")
        run.assert_not_called()

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
        self.assertEqual(commands[0], prefix + [SANDBOX_PREFLIGHT_EXECUTABLE])
        self.assertEqual(commands[1][:len(prefix)], prefix)
        self.assertEqual(commands[1][len(prefix):len(prefix) + 2], [SANDBOX_PYTHON_EXECUTABLE, "-c"])

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
