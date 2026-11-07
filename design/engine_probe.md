# Native-engine feasibility probe

This is **developer tooling only**, not product inference or distribution
approval. Flutter, memory-only drafts and app platform support are unchanged.
Windows x64 is the first engine candidate: it already has an app host, CMake and
explicit copy/export. Linux has no application host. Native compilation and real
inference still require exact-publication Windows CI evidence.

## Pinned inputs and review

`tools/engine_probe/fixtures.json` pins llama.cpp b12183, commit
`31424b7cf14604ca65a9195123da1413f31c4472`, and its 39,104,147-byte source archive,
SHA-256 `541aeea240dbceb48de352122b30a26ac32ec5fd936c62442037bf04310a0270`.
CMake verifies it before extraction. The acquired archive is available for local
read-only inspection; no local C++ build or inference is claimed.

`tools/engine_probe/model/fixtures.json` owns the exact model pins, all separately
acquired from `Qwen/Qwen2.5-0.5B-Instruct-GGUF`, immutable revision
`9217f5db79a29953eb74d5343926648285ec7e67`:

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 491400032 | `74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db` |
| `LICENSE` | 11343 | `832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e` |
| `README.md` | 4856 | `fa1fede7f775a20f111cc098c00900092020572ce78976970a5b0ad9ca211999` |

All three were independently hash/size-checked and passed local in-place probe
validation, including the model's GGUF v3 header. The complete LICENSE is
Apache-2.0, copyright 2024 Alibaba Cloud, without added restrictions: permissive
copyright/patent grants, redistribution/license/notice obligations, no trademark
grant or warranty. This authorizes the separate unmodified developer experiment,
not model bundling. The card's multilingual/0.49B description is upstream
information, not measured quality or language coverage.

## Running the experiment

On Windows x64 with CMake, MSVC, Python and the digest-named reviewed fixtures:

```powershell
cmake -S tools/engine_probe -B build/engine-probe -A x64
cmake --build build/engine-probe --config Release --target llama-simple --parallel 2
python tools/engine_probe/smoke.py --executable build/engine-probe/bin/Release/llama-simple.exe --timeout-seconds 180 --output-bytes 8192 --fixture-dir C:/reviewed-fixtures --accept-terms-sha256 832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e --tokens 16
```

The script never downloads or discovers models. It reads the complete terms
first and requires their exact SHA-256 as explicit acceptance **on each run**,
then streams/verifies the card and weights. Missing/nonregular/link/reparse paths,
size/hash mismatches and invalid 24-byte GGUF v3 headers fail before engine use.
Inputs are read-only, without cache copies or remembered consent. These path
checks are not a race-free product broker: the executable reopens the path, so
fixtures must remain under developer/isolated-runner control.

Missing and truncated GGUFs must be rejected by the actual upstream executable
with exit 1 and the model-load diagnostic on stderr; crashes/timeouts do not pass.
Without `--fixture-dir`, the script explicitly reports that inference was not run.
With fixtures, a fixed public ChatML prompt requests the French translation of
`Hello.` using CPU `-ngl 0`. Exit 0, nonzero decoded-token diagnostics, an exact
prompt echo and generated-only `Bonjour` are required. Stdout/stderr are separate;
CRLF is normalized, and truncated stdout/unexpected echoes fail. Prompt or stderr
matches cannot pass. This is one synthetic smoke expectation, not a quality,
performance, language-coverage or privacy evaluation.

## CI, resource policy and evidence

`Native engine probe` runs on path-scoped reviewed `mizu` pushes or manual
dispatch; observe its exact publication SHA. It builds only upstream
`llama-simple` and static CPU dependencies, independently of Flutter. Common,
other tools/examples, server/app/UI, model-download/network helpers, dynamic
backends, host ISA detection, AVX-family/FMA/F16C/SSE4.2/BMI2, accelerators,
OpenMP/BLAS and optional CPU providers are disabled. Generated compile/link inputs,
not cache booleans alone, must establish the selected closure.

Only CI acquires the three pinned public test files, verifies their size/hash and
passes explicit developer-only terms acceptance. They live in runner temp outside
artifact globs, are removed by `always()` cleanup, and are never uploaded or
bundled with the app; abrupt runner loss relies on disposable-runner teardown.
Workflow policy sets two build workers, 300 seconds per download, 180 seconds per
engine call, 16 tokens, 8192 bytes per stdout/stderr tail and a 15-minute job
deadline. These are experiment settings, not product limits. JSON escaping may
expand printed tails; spooled-output disk use and engine memory are not capped.

`windows-x64-engine-probe` retains scripts/manifests, configure/build/smoke logs,
CMake/file-API/MSBuild inputs, source hashes/notices, executable hash and dumpbin
headers/imports—not weights or executables. Actions retention governs evidence;
failed builds may provide only partial inputs. Lightweight Python tests protect
validation, consent, echo separation and failure handling using tiny synthetic
files/processes, never simulated inference.

## Product adoption remains gated

Root MIT terms were read (SHA-256
`94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`), but full
selected-file/runtime closure is not complete. Source inspection also found an
MIT-attributed section in `ggml-cpu/ops.cpp` and Unicode tables whose generator
uses the moving UCD `latest` URL plus Python `unicodedata`; provenance/notices must
be settled, not inferred from the root license. Windows runtime linkage and user-
accessible notice delivery also require review. Product brokering/session-only
consent, model/language reporting, cancellation/resource failures, verified
no-network/no-text-persistence behavior and Flutter integration remain separate
gates. The watchdog is not cancellation evidence. Draft persistence retains its
existing security/recovery gates.
