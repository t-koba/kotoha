"""Regression tests for the portal probe's sanitized child-stage channel."""
import unittest

from tools.linux_portal_probe import (
    CLIENT_STARTED_MARKER,
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
        self.assertFalse(_sandbox_client_started(CLIENT_STARTED_MARKER + "x" * 8192))


if __name__ == "__main__":
    unittest.main()
