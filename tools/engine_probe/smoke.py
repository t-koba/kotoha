#!/usr/bin/env python3
"""Developer-only real llama-simple probe. No downloads or product integration.

Only the exact separately acquired public fixtures are accepted. Inputs are read
in place; public prompt/output and review metadata persist in CI logs.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import struct
import subprocess
import tempfile


MANIFEST = Path(__file__).parent / "model" / "fixtures.json"
MODEL = "qwen2.5-0.5b-instruct-q4_k_m.gguf"
PROMPT = (
    "<|im_start|>system\n"
    "Translate the user's English text into French. Reply only with the translation."
    "<|im_end|>\n<|im_start|>user\nHello.<|im_end|>\n<|im_start|>assistant\n"
)


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("must be finite and positive")
    return seconds


def positive_int(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def verify_file(path, pin, gguf=False):
    # Reject link/reparse paths, including directory aliases. This is a developer
    # path check, NOT a race-free product broker or immutable inference handle.
    path = path.absolute()
    for component in (path, *path.parents):
        info = component.lstat()
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise RuntimeError(f"symlink/reparse path refused: {component}")
    if not stat.S_ISREG(path.lstat().st_mode):
        raise RuntimeError(f"not a regular file: {path}")
    digest = hashlib.sha256()
    size = 0
    header = b""
    with path.open("rb") as source:
        if not stat.S_ISREG(os.fstat(source.fileno()).st_mode):
            raise RuntimeError(f"not a regular file: {path}")
        while block := source.read(1024 * 1024):
            if not size:
                header = block[:24]
            size += len(block)
            digest.update(block)
    if size != pin["size"] or digest.hexdigest() != pin["sha256"]:
        raise RuntimeError(f"size/SHA256 mismatch: {path.name}")
    if gguf:
        if len(header) != 24:
            raise RuntimeError("truncated GGUF v3 header")
        magic, version, tensors, metadata = struct.unpack("<4sIQQ", header)
        if magic != b"GGUF" or version != 3 or not tensors or not metadata:
            raise RuntimeError("invalid GGUF v3 model header")


def verify_fixtures(directory, acceptance):
    pins = {item["url"].rsplit("/", 1)[-1]: item
            for item in json.loads(MANIFEST.read_text(encoding="utf-8"))["files"]}
    for name in ("LICENSE", "README.md", MODEL):
        pin = pins[name]
        verify_file(directory / pin["sha256"], pin, gguf=name == MODEL)
        print(f"Verified {name}: {json.dumps(pin, sort_keys=True)}", flush=True)
        # Refuse before reading the large weights when terms are not accepted.
        if name == "LICENSE":
            if acceptance != pin["sha256"]:
                raise RuntimeError("explicit per-invocation acceptance must equal verified LICENSE SHA256")
            print(f"Developer-test-only terms acceptance: {acceptance}", flush=True)
    return directory / pins[MODEL]["sha256"]


def invoke(command, timeout, output_bytes, expected_code, load_failure=False):
    # Files avoid unbounded Python memory; printed tails are policy-bounded.
    # Disk use and engine memory are NOT bounded by this output budget.
    with tempfile.TemporaryFile() as stdout, tempfile.TemporaryFile() as stderr:
        timed_out = False
        try:
            result = subprocess.run(command, stdout=stdout, stderr=stderr,
                                    timeout=timeout, check=False)
        except subprocess.TimeoutExpired:
            timed_out = True
        tails = []
        sizes = []
        for label, stream in (("stdout", stdout), ("stderr", stderr)):
            size = stream.seek(0, 2)
            stream.seek(max(0, size - output_bytes))
            tail = stream.read(output_bytes)
            sizes.append(size)
            tails.append(tail)
            # JSON escaping keeps even rejection diagnostics printable.
            print(f"{label} ({size} bytes, last {output_bytes} max): "
                  f"{json.dumps(tail.decode('utf-8', errors='replace'), ensure_ascii=True)}")
    if timed_out:
        raise RuntimeError(f"engine exceeded {timeout}s; no success evidence")
    if result.returncode != expected_code:
        raise RuntimeError(f"expected exit {expected_code}, got {result.returncode}")
    if load_failure and b"error: unable to load model" not in tails[1]:
        raise RuntimeError("missing upstream model-load rejection diagnostic in stderr tail")
    return tails[0], tails[1], sizes[0] > output_bytes


def generated_sample(stdout, stderr, truncated):
    if truncated:
        raise RuntimeError("stdout truncated; cannot establish prompt/output boundary")
    # Pinned simple.cpp echoes tokens before generation. Qwen's ChatML echo must
    # match exactly; do not search a mixed prompt/output stream for the answer.
    # The Windows CRT expands printf newlines to CRLF in stdout text mode.
    text = stdout.decode("utf-8").replace("\r\n", "\n")
    if not text.startswith(PROMPT):
        raise RuntimeError("unexpected prompt echo; no generated-output evidence")
    generated = text[len(PROMPT):].strip()
    if not re.search(rb"(?m)^main: decoded [1-9][0-9]* tokens", stderr):
        raise RuntimeError("no positive decoded-token diagnostic")
    if not re.search(r"\bBonjour\b", generated, re.IGNORECASE):
        raise RuntimeError("generated output did not meet narrow 'Bonjour' smoke expectation")
    return generated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--timeout-seconds", required=True, type=positive_seconds,
                        help="per invocation watchdog; timeout is failure")
    parser.add_argument("--output-bytes", required=True, type=positive_int,
                        help="maximum printed bytes from EACH stdout/stderr tail (JSON escaped)")
    parser.add_argument("--fixture-dir", type=Path,
                        help="opt in to real inference; files named by manifest SHA256")
    parser.add_argument("--accept-terms-sha256", help="per-run developer-only LICENSE acceptance")
    parser.add_argument("--tokens", type=positive_int, help="required with --fixture-dir")
    args = parser.parse_args()
    model = None
    if args.fixture_dir is not None:
        if args.tokens is None:
            parser.error("--fixture-dir requires --tokens")
        model = verify_fixtures(args.fixture_dir, args.accept_terms_sha256)
    elif args.tokens is not None or args.accept_terms_sha256 is not None:
        parser.error("--tokens/--accept-terms-sha256 require --fixture-dir")
    if not args.executable.is_file():
        parser.error("--executable must be the built llama-simple executable")
    executable = str(args.executable.resolve())
    with tempfile.TemporaryDirectory(prefix="kotoha-engine-probe-") as directory:
        root = Path(directory)
        malformed = root / "truncated.gguf"
        # GGUF magic and version 3, but missing mandatory header fields.
        malformed.write_bytes(b"GGUF\x03\x00\x00\x00")
        for invalid in (root / "missing.gguf", malformed):
            print(f"Loader rejection: {invalid.name}", flush=True)
            invoke([executable, "-m", str(invalid), "-n", "1", "-ngl", "0", "probe"],
                   args.timeout_seconds, args.output_bytes, 1, load_failure=True)
        print("PASS: missing and malformed GGUF rejected by the real upstream loader")
    if model is None:
        print("REAL INFERENCE NOT RUN: no --fixture-dir supplied; loader evidence only")
    else:
        print("Real-model public synthetic sample, NOT language/quality coverage", flush=True)
        output = invoke([executable, "-m", str(model.absolute()), "-n", str(args.tokens),
                         "-ngl", "0", PROMPT],
                        args.timeout_seconds, args.output_bytes, 0)
        sample = generated_sample(*output)
        print(f"PASS: generated-only narrow smoke sample: {json.dumps(sample, ensure_ascii=True)}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, UnicodeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
