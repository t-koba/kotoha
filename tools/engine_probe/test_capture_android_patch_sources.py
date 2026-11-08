"""Synthetic Git-object tests for exact Android patch-source capture."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

from capture_android_patch_sources import _PATCH_BASENAMES, fetch_and_capture


@unittest.skipUnless(shutil.which("git"), "git is required by the audit capture")
class CaptureAndroidPatchSourcesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.repository = self.root / "source"
        self.repository.mkdir()
        self._git("init", "--quiet")
        self._git("config", "user.name", "Kotoha audit test")
        self._git("config", "user.email", "audit-test@example.invalid")
        self.contents = {}
        self.paths = {}
        for index, basename in enumerate(_PATCH_BASENAMES):
            relative = f"patches/{'cherry/' if index else ''}{basename}"
            path = self.repository / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            content = f"synthetic pinned patch {index}\n".encode("ascii")
            path.write_bytes(content)
            self.contents[relative] = content
            self.paths[basename] = relative
        self.revision = self._commit()

    def tearDown(self):
        self.temporary.cleanup()

    def _git(self, *arguments):
        result = subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if result.returncode:
            self.fail("synthetic Git setup failed")
        return result.stdout.decode("ascii").strip()

    def _commit(self):
        self._git("add", "--all")
        self._git("commit", "--quiet", "-m", "synthetic patch source")
        return self._git("rev-parse", "HEAD")

    def test_records_exact_commit_blobs_and_bytes(self):
        output = self.root / "captured"
        manifest = fetch_and_capture(
            self.repository.as_uri(), self.revision, output, max_bytes=4096, timeout_seconds=10,
        )
        self.assertEqual(manifest["revision"], self.revision)
        self.assertEqual(
            [record["path"] for record in manifest["files"]],
            [self.paths[name] for name in _PATCH_BASENAMES],
        )
        self.assertIn("four selected patch blobs", manifest["capture_scope"])
        self.assertEqual(len(manifest["files"]), len(_PATCH_BASENAMES))
        self.assertEqual(manifest["patch_bytes"], sum(record["bytes"] for record in manifest["files"]))
        self.assertEqual(manifest["total_bytes"], manifest["tree_index_bytes"] + manifest["patch_bytes"])
        for record in manifest["files"]:
            content = self.contents[record["path"]]
            self.assertEqual(record["bytes"], len(content))
            self.assertEqual(record["sha256"], hashlib.sha256(content).hexdigest())
            self.assertEqual(len(record["git_blob_id"]), 40)
            self.assertFalse((output / record["path"]).exists())
        stored = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
        self.assertEqual(stored["tree"], manifest["tree"])
        self.assertEqual(stored["files"], [
            {key: record[key] for key in ("path", "git_blob_id", "bytes", "sha256")}
            for record in manifest["files"]
        ])
        self.assertNotIn("content", stored["files"][0])
        self.assertEqual(
            stored["files"][-1]["path"],
            "patches/cherry/e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch",
        )

    def test_rejects_an_unavailable_revision_without_output(self):
        output = self.root / "captured"
        with self.assertRaises(RuntimeError):
            fetch_and_capture(
                self.repository.as_uri(), "0" * 40, output, max_bytes=4096, timeout_seconds=10,
            )
        self.assertFalse(output.exists())

    def test_wrong_exact_patch_path_fails_without_partial_output(self):
        selected = self.repository / self.paths[_PATCH_BASENAMES[-1]]
        content = selected.read_bytes()
        selected.unlink()
        wrong = self.repository / "patches" / "other" / _PATCH_BASENAMES[-1]
        wrong.parent.mkdir(parents=True)
        wrong.write_bytes(content)
        revision = self._commit()
        output = self.root / "captured"
        with self.assertRaises(RuntimeError):
            fetch_and_capture(self.repository.as_uri(), revision, output, max_bytes=4096, timeout_seconds=10)
        self.assertFalse(output.exists())

    def test_duplicate_patch_basename_fails_closed(self):
        duplicate = self.repository / "patches" / "duplicate" / _PATCH_BASENAMES[0]
        duplicate.parent.mkdir(parents=True)
        duplicate.write_bytes(b"second patch with ambiguous name\n")
        revision = self._commit()
        output = self.root / "captured"
        with self.assertRaises(RuntimeError):
            fetch_and_capture(self.repository.as_uri(), revision, output, max_bytes=4096, timeout_seconds=10)
        self.assertFalse(output.exists())

    def test_byte_bound_fails_without_partial_output(self):
        output = self.root / "captured"
        with self.assertRaises(RuntimeError):
            fetch_and_capture(self.repository.as_uri(), self.revision, output, max_bytes=2, timeout_seconds=10)
        self.assertFalse(output.exists())

    def test_rejects_short_revision(self):
        output = self.root / "captured"
        with self.assertRaises(ValueError):
            fetch_and_capture(self.repository.as_uri(), self.revision[:7], output, max_bytes=4096, timeout_seconds=10)
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
