"""Small synthetic files test boundaries, NOT actual inference evidence."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch

import smoke


HEADER = struct.pack("<4sIQQ", b"GGUF", 3, 1, 1)
DECODED = b"main: decoded 2 tokens in 1.00 s, speed: 2.00 t/s\n"


def pin(data):
    return {"size": len(data), "sha256": hashlib.sha256(data).hexdigest()}


class ValidationTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.file = self.root / "input"
        self.file.write_bytes(HEADER)
        self.silent = contextlib.redirect_stdout(io.StringIO())
        self.silent.__enter__()
        self.addCleanup(self.silent.__exit__, None, None, None)

    def test_read_only_stream_and_digest_size_header_rejections(self):
        original_open = Path.open
        modes = []

        def read_only(path, mode="r", *args, **kwargs):
            modes.append(mode)
            self.assertEqual(mode, "rb")
            return original_open(path, mode, *args, **kwargs)

        before = self.file.stat().st_mtime_ns
        with patch.object(Path, "open", read_only):
            smoke.verify_file(self.file, pin(HEADER), gguf=True)
        self.assertEqual(modes, ["rb"])
        self.assertEqual(self.file.stat().st_mtime_ns, before)
        self.assertEqual(self.file.read_bytes(), HEADER)
        for incorrect in ({**pin(HEADER), "size": 1}, pin(HEADER[:-1] + b"x")):
            with self.subTest(pin=incorrect), self.assertRaisesRegex(RuntimeError, "mismatch"):
                smoke.verify_file(self.file, incorrect)
        for data in (b"GGUF\x03\0\0\0", HEADER.replace(b"GGUF", b"BAD!"),
                     struct.pack("<4sIQQ", b"GGUF", 2, 1, 1),
                     struct.pack("<4sIQQ", b"GGUF", 3, 0, 1)):
            self.file.write_bytes(data)
            with self.subTest(data=data), self.assertRaisesRegex(RuntimeError, "header"):
                smoke.verify_file(self.file, pin(data), gguf=True)

    def test_missing_directory_and_symlink_rejected(self):
        with self.assertRaises(FileNotFoundError):
            smoke.verify_file(self.root / "missing", pin(HEADER))
        with self.assertRaisesRegex(RuntimeError, "regular"):
            smoke.verify_file(self.root, pin(HEADER))
        link = self.root / "link"
        try:
            link.symlink_to(self.file)
        except OSError as error:
            self.skipTest(f"symlink creation unavailable on this host: {error}")
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            smoke.verify_file(link, pin(HEADER))
        link.unlink()
        link.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            smoke.verify_file(link / "input", pin(HEADER))

    def fixtures(self, terms):
        entries = []
        for name, data in (("LICENSE", terms), ("README.md", b"card"), (smoke.MODEL, HEADER)):
            entry = {**pin(data), "url": f"https://example.invalid/{name}"}
            (self.root / entry["sha256"]).write_bytes(data)
            entries.append(entry)
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps({"files": entries}), encoding="utf-8")
        return manifest

    def test_consent_bound_to_verified_complete_terms_and_card(self):
        terms = b"complete test terms"
        manifest = self.fixtures(terms)
        acceptance = pin(terms)["sha256"]
        with patch.object(smoke, "MANIFEST", manifest):
            for missing_or_wrong in (None, "", "0" * 64):
                with patch.object(smoke, "verify_file", wraps=smoke.verify_file) as verify:
                    with self.assertRaisesRegex(RuntimeError, "acceptance"):
                        smoke.verify_fixtures(self.root, missing_or_wrong)
                    self.assertEqual([call.args[0].name for call in verify.call_args_list],
                                     [acceptance])
            model = smoke.verify_fixtures(self.root, acceptance)
            self.assertEqual(model.read_bytes(), HEADER)
            # The complete LICENSE and card, not filenames/ack alone, are checked.
            for data in (terms, b"card", HEADER):
                file = self.root / pin(data)["sha256"]
                file.write_bytes(data[:-1] + b"!")
                with self.assertRaisesRegex(RuntimeError, "mismatch"):
                    smoke.verify_fixtures(self.root, acceptance)
                file.write_bytes(data)
            # A newly reviewed terms digest cannot inherit the previous acceptance.
            self.fixtures(terms + b" changed")
            with self.assertRaisesRegex(RuntimeError, "acceptance"):
                smoke.verify_fixtures(self.root, acceptance)


class ExecutionTest(unittest.TestCase):
    def test_generated_output_not_echo_or_stderr(self):
        echo = smoke.PROMPT.encode()
        self.assertNotIn(b"Bonjour", echo)
        self.assertEqual(smoke.generated_sample(echo + b"Bonjour.\n", DECODED, False),
                         "Bonjour.")
        self.assertEqual(smoke.generated_sample((echo + b"Bonjour.\n").replace(b"\n", b"\r\n"),
                                                DECODED, False), "Bonjour.")
        cases = ((echo, DECODED + b"Bonjour", False),
                 (b"Bonjour", DECODED, False),
                 (echo + b"Bonjour", b"main: decoded 0 tokens", False),
                 (echo + b"Bonjour", DECODED, True))
        for case in cases:
            with self.subTest(case=case), self.assertRaises(RuntimeError):
                smoke.generated_sample(*case)
        # Even an expectation present in a future prompt cannot count as generation.
        with patch.object(smoke, "PROMPT", smoke.PROMPT + "Bonjour"):
            with self.assertRaises(RuntimeError):
                smoke.generated_sample(echo + b"Bonjour\n", DECODED, False)

    def test_subprocess_exit_timeout_separate_streams_and_budget(self):
        with contextlib.redirect_stdout(io.StringIO()):
            command = [sys.executable, "-c", "import os; os.write(1, b'out\\n'); os.write(2, b'err\\n')"]
            self.assertEqual(smoke.invoke(command, 5, 100, 0), (b"out\n", b"err\n", False))
            self.assertEqual(smoke.invoke(command, 5, 2, 0), (b"t\n", b"r\n", True))
            with self.assertRaisesRegex(RuntimeError, "expected exit"):
                smoke.invoke([sys.executable, "-c", "raise SystemExit(2)"], 5, 100, 0)
            with self.assertRaisesRegex(RuntimeError, "exceeded"):
                smoke.invoke([sys.executable, "-c", "import time; time.sleep(30)"], 0.1, 100, 0)
            with self.assertRaisesRegex(RuntimeError, "stderr"):
                smoke.invoke([sys.executable, "-c", "print('error: unable to load model')"],
                             5, 100, 0, load_failure=True)
            smoke.invoke([sys.executable, "-c", "import sys; print('error: unable to load model', "
                          "file=sys.stderr); sys.exit(1)"], 5, 100, 1, load_failure=True)


if __name__ == "__main__":
    unittest.main()
