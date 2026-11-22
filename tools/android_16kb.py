#!/usr/bin/env python3
"""Offline first-party 16 KB ELF preflight for a built APK or AAB archive.

This checks packaged shared objects against the documented first-party ELF
alignment criteria only. It is not an Android compliance, release, emulator,
model-load, license or quality gate.
"""

from __future__ import annotations

import struct
import sys
import zipfile
from pathlib import Path

PAGE_SIZE = 16384
PT_LOAD = 1
PT_GNU_RELRO = 0x6474E552
PF_W = 2
ELF64_HEADER_SIZE = 64
ELF64_PHDR_SIZE = 56
PN_XNUM = 0xFFFF


class ElfError(ValueError):
    """The bytes are not a parseable ELF64 little-endian object."""


def check_elf(data: bytes, label: str) -> list[str]:
    """Return alignment findings for one ELF64 object; raise on untrusted bytes."""
    if len(data) < ELF64_HEADER_SIZE:
        raise ElfError(
            f"{label}: truncated ELF header ({len(data)} bytes, "
            f"need {ELF64_HEADER_SIZE})"
        )
    if data[:4] != b"\x7fELF":
        raise ElfError(f"{label}: not an ELF file (bad magic)")
    if data[4] != 2:
        raise ElfError(
            f"{label}: unsupported ELF class {data[4]} (need ELF64 class 2; "
            "ELF32 is not checked)"
        )
    if data[5] != 1:
        raise ElfError(
            f"{label}: unsupported ELF data encoding {data[5]} "
            "(need little-endian 1)"
        )
    if data[6] != 1:
        raise ElfError(
            f"{label}: unsupported ELF ident version {data[6]} (need 1)"
        )

    (_, _, version, _, phoff, _, _, _, phentsize, phnum, _, _, _) = struct.unpack_from(
        "<HHIQQQIHHHHHH", data, 16
    )
    if version != 1:
        raise ElfError(f"{label}: unsupported ELF version {version} (need 1)")
    if phnum == 0:
        raise ElfError(f"{label}: no program headers (e_phnum=0)")
    if phnum == PN_XNUM:
        raise ElfError(f"{label}: unsupported extended e_phnum={phnum}")
    if phentsize < ELF64_PHDR_SIZE:
        raise ElfError(
            f"{label}: invalid e_phentsize={phentsize} "
            f"(need at least {ELF64_PHDR_SIZE})"
        )
    if phoff < ELF64_HEADER_SIZE:
        raise ElfError(f"{label}: invalid e_phoff={phoff} (overlaps ELF64 header)")
    if phoff + phnum * phentsize > len(data):
        raise ElfError(
            f"{label}: truncated program headers (e_phoff={phoff}, "
            f"e_phnum={phnum}, e_phentsize={phentsize}, "
            f"file={len(data)} bytes)"
        )

    segments = []
    for index in range(phnum):
        p_type, p_flags, _, p_vaddr, _, _, p_memsz, p_align = struct.unpack_from(
            "<IIQQQQQQ", data, phoff + index * phentsize
        )
        segments.append((index, p_type, p_flags, p_vaddr, p_memsz, p_align))

    loads = [segment for segment in segments if segment[1] == PT_LOAD]
    if not loads:
        raise ElfError(f"{label}: no PT_LOAD segments in ELF64 object")

    findings = []
    for index, p_type, _, _, _, p_align in segments:
        if p_type == PT_LOAD and p_align < PAGE_SIZE:
            findings.append(
                f"PT_LOAD[{index}] p_align={p_align} (0x{p_align:x}) "
                f"< {PAGE_SIZE}"
            )

    for _, p_type, _, relro_start, relro_size, _ in segments:
        if p_type != PT_GNU_RELRO:
            continue
        relro_end = relro_start + relro_size
        containing = [
            segment for segment in loads
            if segment[2] & PF_W
            and segment[3] <= relro_start < segment[3] + segment[4]
        ]
        if not containing:
            continue  # The rule is conditional; no writable LOAD, no finding.
        for index, _, _, load_start, load_size, _ in containing:
            load_end = load_start + load_size
            if load_end > relro_end and relro_end % PAGE_SIZE:
                findings.append(
                    f"PT_GNU_RELRO start={relro_start} memsz={relro_size} "
                    f"end={relro_end} (0x{relro_end:x}) is not {PAGE_SIZE}-aligned; "
                    f"writable PT_LOAD[{index}] vaddr={load_start} "
                    f"memsz={load_size} end={load_end} continues past RELRO end"
                )
    return findings


def inspect(path: str) -> list[str]:
    """Return one report line per packaged .so, or one explicit failure line."""
    try:
        with zipfile.ZipFile(path) as archive:
            entries = [
                info for info in archive.infolist()
                if info.filename.endswith(".so") and not info.is_dir()
            ]
            if not entries:
                return [f"FAIL {path}: no .so entries found; nothing was checked"]

            lines = []
            for info in entries:
                label = f"{path}::{info.filename}"
                try:
                    data = archive.read(info)
                except (OSError, zipfile.BadZipFile, RuntimeError, NotImplementedError) as exc:
                    lines.append(f"FAIL {label}: cannot read .so entry ({exc})")
                    continue
                try:
                    findings = check_elf(data, label)
                except ElfError as exc:
                    lines.append(f"FAIL {label}: {exc}")
                    continue
                if findings:
                    lines.append(f"FAIL {label}: " + "; ".join(findings))
                else:
                    lines.append(
                        f"PASS {label}: PT_LOAD p_align >= {PAGE_SIZE}; "
                        "PT_GNU_RELRO conditional check satisfied"
                    )
            return lines
    except (OSError, zipfile.BadZipFile) as exc:
        return [f"FAIL {path}: cannot open APK/AAB ZIP ({exc})"]


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("Usage: python3 tools/android_16kb.py PATH_TO_APK_OR_AAB")
        return 1
    path = args[0]
    if not Path(path).is_file():
        print(f"FAIL {path}: file not found; provide a built APK or AAB")
        return 1
    lines = inspect(path)
    for line in lines:
        print(line)
    return 0 if lines and all(line.startswith("PASS ") for line in lines) else 1


if __name__ == "__main__":
    sys.exit(main())
