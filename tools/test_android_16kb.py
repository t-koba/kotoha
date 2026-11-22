"""Regression tests for the offline Android 16 KB artifact preflight."""
import io
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stdout
from pathlib import Path

from tools.android_16kb import PAGE_SIZE, ElfError, check_elf, inspect, main

PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
PF_R = 4
PF_W = 2
PF_RW = PF_R | PF_W


def _segment(p_type, flags, vaddr, memsz, align):
    return (p_type, flags, 0, vaddr, vaddr, memsz, memsz, align)


def _load(vaddr, memsz, align, flags=PF_RW):
    return _segment(PT_LOAD, flags, vaddr, memsz, align)


def _relro(vaddr, memsz, flags=PF_R):
    return _segment(PT_GNU_RELRO, flags, vaddr, memsz, PAGE_SIZE)


def _elf64(segments, *, magic=b"\x7fELF", elf_class=2, encoding=1,
           ident_version=1, version=1, phoff=64, phentsize=56, phnum=None):
    """Tiny synthetic ELF64 object: ELF header plus program headers only."""
    header = bytearray(64)
    header[0:4] = magic
    header[4] = elf_class
    header[5] = encoding
    header[6] = ident_version
    struct.pack_into(
        "<HHIQQQIHHHHHH", header, 16,
        3, 183, version, 0, phoff, 0, 0, 64, phentsize,
        len(segments) if phnum is None else phnum, 64, 0, 0,
    )
    return bytes(header) + b"".join(
        struct.pack("<IIQQQQQQ", *segment) for segment in segments
    )


def _archive(directory, name, entries):
    path = Path(directory) / name
    with zipfile.ZipFile(path, "w") as archive:
        for entry_name, data in entries.items():
            archive.writestr(entry_name, data)
    return path


class ElfFixtureTest(unittest.TestCase):
    def test_aligned_load_segments_pass(self):
        data = _elf64([
            _load(0, 0x20000, PAGE_SIZE),
            _load(0x20000, 0x4000, 0x10000, PF_R),
        ])
        self.assertEqual(check_elf(data, "lib/libx.so"), [])

    def test_small_load_alignment_fails_with_path_and_numbers(self):
        data = _elf64([_load(0, 0x20000, 4096)])
        findings = check_elf(data, "lib/arm64-v8a/libx.so")
        self.assertEqual(len(findings), 1)
        self.assertIn("PT_LOAD[0]", findings[0])
        self.assertIn("p_align=4096", findings[0])
        self.assertIn("16384", findings[0])

    def test_relro_overlap_with_unaligned_end_fails(self):
        data = _elf64([
            _load(0, 0x30000, PAGE_SIZE),
            _relro(0x20000, 0x1000),
        ])
        findings = check_elf(data, "lib/libx.so")
        self.assertEqual(len(findings), 1)
        self.assertIn("PT_GNU_RELRO", findings[0])
        self.assertIn("end=135168", findings[0])
        self.assertIn("0x21000", findings[0])
        self.assertIn("PT_LOAD[0]", findings[0])
        self.assertIn("end=196608", findings[0])

    def test_relro_overlap_with_aligned_end_passes(self):
        data = _elf64([
            _load(0, 0x30000, PAGE_SIZE),
            _relro(0x20000, 0x4000),
        ])
        self.assertEqual(check_elf(data, "lib/libx.so"), [])

    def test_load_ending_exactly_at_relro_end_passes(self):
        data = _elf64([
            _load(0, 0x21000, PAGE_SIZE),
            _relro(0x20000, 0x1000),
        ])
        self.assertEqual(check_elf(data, "lib/libx.so"), [])

    def test_every_relro_segment_is_checked_in_both_orders(self):
        load = _load(0, 0x50000, PAGE_SIZE)
        aligned = _relro(0x10000, 0x4000)
        violating = _relro(0x30000, 0x1000)
        for name, segments in (
            ("violating last", [load, aligned, violating]),
            ("violating first", [load, violating, aligned]),
        ):
            with self.subTest(case=name):
                findings = check_elf(_elf64(segments), "lib/arm64-v8a/libx.so")
                self.assertEqual(len(findings), 1, findings)
                self.assertIn("PT_GNU_RELRO", findings[0])
                self.assertIn("end=200704", findings[0])
                self.assertIn("0x31000", findings[0])

    def test_absent_relro_passes(self):
        self.assertEqual(check_elf(_elf64([_load(0, 0x20000, PAGE_SIZE)]), "x.so"), [])

    def test_conditional_relro_without_containing_writable_load_passes(self):
        cases = {
            "read-only containing load": [
                _load(0, 0x30000, PAGE_SIZE, PF_R),
                _relro(0x20000, 0x1000),
            ],
            "writable load outside relro range": [
                _load(0, 0x10000, PAGE_SIZE),
                _relro(0x20000, 0x1000),
            ],
        }
        for name, segments in cases.items():
            with self.subTest(case=name):
                self.assertEqual(check_elf(_elf64(segments), "lib/libx.so"), [])

    def test_malformed_or_unsupported_elf_fails_closed(self):
        valid = [_load(0, 0x20000, PAGE_SIZE)]
        cases = {
            "empty input": (b"", "truncated ELF header"),
            "short header": (b"\x7fEL", "truncated ELF header"),
            "bad magic": (_elf64(valid, magic=b"NOPE"), "bad magic"),
            "ELF32 class": (_elf64(valid, elf_class=1), "ELF64 class 2"),
            "big endian": (_elf64(valid, encoding=2), "little-endian"),
            "bad ident version": (_elf64(valid, ident_version=2), "ident version"),
            "bad ELF version": (_elf64(valid, version=2), "ELF version 2"),
            "no program headers": (_elf64(valid, phnum=0), "no program headers"),
            "extended phnum": (_elf64(valid, phnum=0xFFFF), "extended e_phnum"),
            "short program header entry": (
                _elf64(valid, phentsize=8), "e_phentsize=8"
            ),
            "phoff in header": (_elf64(valid, phoff=32), "e_phoff=32"),
            "truncated program headers": (_elf64(valid, phoff=4096), "truncated"),
            "no PT_LOAD": (
                _elf64([_relro(0, 0x1000)]), "no PT_LOAD segments"
            ),
        }
        for name, (data, expected) in cases.items():
            with self.subTest(case=name):
                with self.assertRaises(ElfError) as caught:
                    check_elf(data, "lib/libx.so")
                self.assertIn("lib/libx.so", str(caught.exception))
                self.assertIn(expected, str(caught.exception))


class ArchivePreflightTest(unittest.TestCase):
    def test_passing_apk_reports_one_line_per_library_and_exits_zero(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = _archive(temporary, "release.apk", {
                "lib/arm64-v8a/libone.so": _elf64([_load(0, 0x20000, PAGE_SIZE)]),
                "lib/x86_64/libtwo.so": _elf64([
                    _load(0, 0x30000, PAGE_SIZE),
                    _relro(0x20000, 0x4000),
                ]),
                "classes.dex": b"not a shared object",
            })
            output = io.StringIO()
            with redirect_stdout(output):
                code = main([str(path)])
            lines = output.getvalue().splitlines()
            self.assertEqual(code, 0)
            self.assertEqual(len(lines), 2)
            self.assertEqual(len(inspect(path)), 2)
            self.assertTrue(all(line.startswith(f"PASS {path}::") for line in lines))
            self.assertIn("libone.so", lines[0])
            self.assertIn("libtwo.so", lines[1])
            self.assertTrue(all("16384" in line for line in lines))

    def test_bad_alignment_fails_with_actionable_findings(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = _archive(temporary, "release.apk", {
                "lib/arm64-v8a/libgood.so": _elf64([_load(0, 0x20000, PAGE_SIZE)]),
                "lib/arm64-v8a/libbad.so": _elf64([_load(0, 0x20000, 4096)]),
            })
            output = io.StringIO()
            with redirect_stdout(output):
                code = main([str(path)])
            lines = output.getvalue().splitlines()
            self.assertEqual(code, 1)
            self.assertEqual(len(lines), 2)
            self.assertTrue(lines[0].startswith(f"PASS {path}::"))
            self.assertIn(f"FAIL {path}::lib/arm64-v8a/libbad.so", lines[1])
            self.assertIn("p_align=4096", lines[1])

    def test_no_shared_object_fails_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = _archive(temporary, "release.aab", {
                "classes.dex": b"dex",
                "assets/data.txt": b"text",
            })
            output = io.StringIO()
            with redirect_stdout(output):
                code = main([str(path)])
            self.assertEqual(code, 1)
            self.assertEqual(
                output.getvalue(),
                f"FAIL {path}: no .so entries found; nothing was checked\n",
            )

    def test_malformed_shared_objects_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = _archive(temporary, "release.apk", {
                "lib/arm64-v8a/lib32.so": _elf64(
                    [_load(0, 0x20000, PAGE_SIZE)], elf_class=1
                ),
                "lib/x86/libbroken.so": b"\x7fELF short",
            })
            output = io.StringIO()
            with redirect_stdout(output):
                code = main([str(path)])
            lines = output.getvalue().splitlines()
            self.assertEqual(code, 1)
            self.assertEqual(len(lines), 2)
            self.assertIn("ELF64 class 2", lines[0])
            self.assertIn("truncated ELF header", lines[1])

    def test_aab_archive_is_checked_the_same_way(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = _archive(temporary, "release.aab", {
                "base/lib/arm64-v8a/libx.so": _elf64([_load(0, 0x20000, PAGE_SIZE)]),
            })
            output = io.StringIO()
            with redirect_stdout(output):
                code = main([str(path)])
            self.assertEqual(code, 0)
            self.assertIn("release.aab::base/lib/arm64-v8a/libx.so", output.getvalue())

    def test_missing_or_invalid_archive_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            missing = Path(temporary) / "missing.apk"
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(main([str(missing)]), 1)
            self.assertIn("file not found", output.getvalue())

            invalid = Path(temporary) / "invalid.apk"
            invalid.write_bytes(b"not a ZIP archive")
            output = io.StringIO()
            with redirect_stdout(output):
                self.assertEqual(main([str(invalid)]), 1)
            self.assertIn("cannot open APK/AAB ZIP", output.getvalue())

    def test_cli_process_exit_codes_and_usage(self):
        script = Path(__file__).resolve().with_name("android_16kb.py")
        root = script.parent.parent
        with tempfile.TemporaryDirectory() as temporary:
            good = _archive(temporary, "good.apk", {
                "lib/arm64-v8a/libx.so": _elf64([_load(0, 0x20000, PAGE_SIZE)]),
            })
            bad = _archive(temporary, "bad.apk", {
                "lib/arm64-v8a/libx.so": _elf64([
                    _load(0, 0x30000, PAGE_SIZE),
                    _relro(0x20000, 0x1000),
                ]),
            })
            for archive, expected in ((good, 0), (bad, 1)):
                with self.subTest(archive=archive.name):
                    result = subprocess.run(
                        [sys.executable, str(script), str(archive)],
                        cwd=root, capture_output=True, text=True, check=False,
                    )
                    self.assertEqual(result.returncode, expected)
                    self.assertEqual(len(result.stdout.splitlines()), 1)
                    self.assertEqual(result.stderr, "")
            result = subprocess.run(
                [sys.executable, str(script)],
                cwd=root, capture_output=True, text=True, check=False,
            )
            self.assertEqual(result.returncode, 1)
            self.assertIn("PATH_TO_APK_OR_AAB", result.stdout)


if __name__ == "__main__":
    unittest.main()
