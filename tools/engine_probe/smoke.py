#!/usr/bin/env python3
"""Exercise the real llama-simple loader; optionally run a user-supplied model.

No downloads, model discovery, or product integration. Output is temporary and
only its bounded tail is printed. Use synthetic/public prompts: CI logs persist.
"""
import argparse
import math
from pathlib import Path
import subprocess
import tempfile


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


def invoke(command, timeout, output_bytes, expected_code, load_failure=False):
    # A file avoids buffering potentially large engine output in Python memory.
    with tempfile.TemporaryFile() as output:
        timed_out = False
        try:
            result = subprocess.run(command, stdout=output, stderr=subprocess.STDOUT,
                                    timeout=timeout, check=False)
        except subprocess.TimeoutExpired:
            timed_out = True
        output.seek(0, 2)
        size = output.tell()
        output.seek(max(0, size - output_bytes))
        tail = output.read(output_bytes).decode("utf-8", errors="replace")
    if size > output_bytes:
        print(f"[output truncated: last {output_bytes} of {size} bytes]")
    print(tail)
    if timed_out:
        raise RuntimeError(f"engine exceeded {timeout}s; no success evidence")
    if result.returncode != expected_code:
        raise RuntimeError(f"expected exit {expected_code}, got {result.returncode}")
    if load_failure and "error: unable to load model" not in tail:
        raise RuntimeError("missing upstream model-load rejection diagnostic in output tail")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", required=True, type=Path)
    parser.add_argument("--timeout-seconds", required=True, type=positive_seconds,
                        help="per invocation watchdog; timeout is failure")
    parser.add_argument("--output-bytes", required=True, type=positive_int,
                        help="maximum combined output tail per invocation")
    parser.add_argument("--model", type=Path, help="explicit separately acquired REAL GGUF")
    parser.add_argument("--tokens", type=positive_int, help="required with --model")
    parser.add_argument("--prompt", help="required with --model; use public test text only")
    args = parser.parse_args()
    if args.model is not None:
        if args.tokens is None or not args.prompt:
            parser.error("--model requires --tokens and a nonempty --prompt")
        if not args.model.is_file():
            parser.error("--model must be an existing real model file")
    elif args.tokens is not None or args.prompt is not None:
        parser.error("--tokens/--prompt require --model; real inference is never implicit")
    if not args.executable.is_file():
        parser.error("--executable must be the built llama-simple executable")
    executable = str(args.executable.resolve())
    with tempfile.TemporaryDirectory(prefix="kotoha-engine-probe-") as directory:
        root = Path(directory)
        malformed = root / "truncated.gguf"
        # GGUF magic and version 3, but missing mandatory header fields.
        malformed.write_bytes(b"GGUF\x03\x00\x00\x00")
        for model in (root / "missing.gguf", malformed):
            print(f"Loader rejection: {model.name}", flush=True)
            invoke([executable, "-m", str(model), "-n", "1", "-ngl", "0", "probe"],
                   args.timeout_seconds, args.output_bytes, 1, load_failure=True)
        print("PASS: missing and malformed GGUF rejected by the real upstream loader")
    if args.model is None:
        print("REAL INFERENCE NOT RUN: no --model supplied; loader evidence only")
    else:
        print("Real-model invocation: unreviewed sample, NOT translation-quality evidence",
              flush=True)
        invoke([executable, "-m", str(args.model.resolve()), "-n", str(args.tokens),
                "-ngl", "0", args.prompt],
               args.timeout_seconds, args.output_bytes, 0)
        print("PASS: real-model invocation exited 0; inspect sample before drawing conclusions")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        raise SystemExit(f"FAIL: {error}") from error
