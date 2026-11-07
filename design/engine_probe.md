# Native-engine feasibility probe

This is **developer tooling only**, not product inference or distribution
approval. Flutter, memory-only drafts and app platform support are unchanged.
Windows x64 is the first engine candidate: it already has an app host, CMake and
explicit copy/export. Linux has no application host. Native compilation and one
public synthetic inference smoke passed exact Windows CI; adoption is blocked.

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

## CI and resource policy

`Native engine probe` runs on path-scoped `mizu` pushes or manual dispatch,
independently of Flutter. Common/tools/server/UI/network helpers, dynamic
backends, native ISA detection, AVX-family/FMA/F16C/SSE4.2/BMI2, accelerators,
OpenMP/BLAS and optional CPU providers are disabled. Actual generated inputs,
not cache booleans alone, determine the selected closure below.

Only CI acquires the pinned public test files with explicit developer-only
terms acceptance. They live outside artifact globs in runner temp, are removed
by `always()` cleanup, and are never bundled; runner loss relies on teardown.
Workflow settings are two build workers, 300 seconds/download, 180 seconds/call,
16 tokens, 8192 bytes per stdout/stderr tail and a 15-minute deadline, not
product limits. JSON escaping can expand tails; spool disk and engine memory
are not capped. Artifacts retain scripts/manifests, logs, generated build inputs,
source hashes/notices and executable hash/imports, not weights/executables.
Actions retention applies; failures can leave partial inputs. Lightweight Python
tests use synthetic files/processes for validation and failure boundaries, not
simulated inference.

## Selected-source and runtime audit

**Not approved for product distribution.** This review applies
[dependency_policy.json](specs/dependency_policy.json), not just root MIT.

### Exact experiment and selected inputs

[Windows CPU probe](https://github.com/t-koba/kotoha/actions/runs/42362657964/job/128374088969)
at published SHA `5553a4a6d749ffdc4d8e30b227bfacb3d0c32143` built the candidate.
Retained `smoke.log` verifies all three fixture pins, both loader rejections and
prompt-separated `Bonjour.`; this remains developer feasibility only.
Executable SHA-256:
`c4ea7c3feb2f220c7387c247810f287c896929aa2af77156f9d8ee0c5b9c1e9f`.

Artifact paths below are relative to
`windows-x64-engine-probe/build/engine-probe/` at that SHA. Actual `build.log`
commands and file-API `target-llama-simple-Release-41f60bf4e9c1988c2228.json`
select four static engine libraries: `llama`, `ggml`, `ggml-cpu`, `ggml-base`,
plus `examples/simple/simple.cpp`; no vendor-hash/common/optional backend library.
MSVC 14.51.36231 uses `/MD` (dynamic CRT). Default Windows import-library inputs
are `kernel32 user32 gdi32 winspool shell32 ole32 oleaut32 uuid comdlg32 advapi32`;
these are not all surviving DLL imports. Configured-but-unlinked targets do not
belong to this link closure.

| Target | Actual compiled translation units / archive source projection |
| --- | --- |
| `llama` | 33 `src/` core files enumerated by `LLAMA_CORE_SOURCES` in pinned `src/CMakeLists.txt`, plus 11 generated `src/CMakeFiles/llama.dir/Unity/unity_{0..10}_cxx.cxx` units. The CMake glob registers all 176 pinned `src/models/*.cpp`, not only Qwen2. Unity inclusion contents remain unverified. |
| `ggml-base` | 9 under `ggml/src/`: `ggml.c`, `ggml.cpp`, `ggml-alloc.c`, `ggml-quants.c`, `ggml-backend.cpp`, `ggml-backend-meta.cpp`, `ggml-opt.cpp`, `ggml-threading.cpp`, `gguf.cpp` |
| `ggml-cpu` | 16 under `ggml/src/ggml-cpu/`: `ggml-cpu.c`, `ggml-cpu.cpp`, `repack.cpp`, `quants.c`, `hbm.cpp`, `traits.cpp`, `binary-ops.cpp`, `unary-ops.cpp`, `vec.cpp`, `ops.cpp`, `amx/amx.cpp`, `amx/mmq.cpp`, `tiled/tiled.cpp`, `tiled/tiled-kernel.cpp`, `arch/x86/quants.c`, `arch/x86/repack.cpp` |
| `ggml` | `ggml/src/ggml-backend-dl.cpp`, `ggml/src/ggml-backend-reg.cpp` (compiled even with dynamic backends disabled) |
| `llama-simple` | `examples/simple/simple.cpp` |

This is 72 actual compile units and an **intended 237-file archive-source
projection**, not a complete preprocessed/header or binary-member closure.
AMX/HBM/tiled filenames must not be discarded based on cache booleans: they
were compiled with conditional implementations. SHA-256 of the projected set is
`97c258eaed98d7f95ba8b67c123136da6e54008efeaab4f79d804aa04a8cfb10`:
serialize sorted archive-relative paths as `<lowercase file SHA-256>  <path>\n`,
UTF-8/LF. This compact fingerprint binds the table's projection without copying
the unrelated whole-archive manifest.

The source projection comes from retained file-API/MSBuild inputs and actual
build commands, matched against the pinned archive. A lexical scan found 84
additional quoted includes: a conditional superset, not selected-header evidence.

The completed artifact inventory lacks Unity contents, configured
`llama-version.h`/`ggml-version.h`, and compiler header-read sets. The current
workflow requests these files and UTF-8 conversions of built targets' MSBuild
`*.read.1.tlog` (MSBuild writes UTF-16). That additional retention needs a new
Windows run. Review actual Unity includes/read sets against the archive, not a
reconstruction claimed as historical evidence. SDK/MSVC inputs still need
provider evidence; static linking does not identify surviving library members.

### Terms, provenance and notices

Scope: prospective Windows engine/helper and generated code, not current app
distribution. Models stay separately user-acquired. Unknown AND terms fail closed.

| Component / selected terms | Classification from available full evidence; required notice or missing evidence |
| --- | --- |
| Root `LICENSE`, MIT; copyright 2023–2026 The ggml authors | **permissive** from full text: unrestricted use/copy/modify/merge/publish/distribute/sublicense/sell with copyright/permission notice retention and AS-IS warranty/liability disclaimer. SHA-256 `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`. Retain full text; this does not settle adaptations/data below. |
| YaRN in `ggml/src/ggml-cpu/ops.cpp:6169–6170`, declared MIT, copyright 2023 Jeffrey Quesnelle and Bowen Peng; source points to `jquesnelle/yarn` / `LlamaYaRNScaledRotaryEmbedding.py` | Preserve attribution with root notice. **Unknown closure**: archive has an MIT declaration, not full origin notice. Obtain immutable origin revision and complete applicable MIT text/copyright. |
| BPE in `src/llama-vocab.cpp:244`, declared MIT, adapted from `cmp-nct/ggllm.cpp` | **Unknown closure**: moving repository pointer only. Preserve attribution; obtain immutable origin and complete terms/copyright. |
| Z-algorithm in `src/llama-sampler.cpp:3485–3486`, declared public domain, points to `ivanyu/string-algorithms/blob/master/z_algorithm.py` | **unknown**: comment alone is not a complete dedication. Obtain immutable origin and complete dedication/applicable terms. |
| `ggml/src/ggml-cpu/vec.h`, “adapted from arm limited optimized routine” (including SSE2 branch at 1306/1316) | **unknown**: disabling Arm/KleidiAI does not exclude this x86 branch. Establish branch selection for MSVC from compiler/preprocessor evidence; if selected identify originating routine/revision and full terms/notices, not a guessed Arm license. |
| Generated `src/unicode-data.cpp` and generator `scripts/gen-unicode-data.py` | **unknown**. Output labels canonical normalization Unicode **16.0.0**, not the other tables. Generator combines moving UCD `latest/ucd/UnicodeData.txt` with Python `unicodedata` (NFD/normalization), without exact UCD/Python pins. Generator/output container declarations differ: regeneration is not established byte-identical. Obtain immutable UCD/Python data/tool provenance and full applicable notices, or reviewed pinned regeneration with equivalence validation. The app's UCD 17 bidi notice does not establish these inputs' terms. |

Immutable evidence for these intrinsic declarations is the source commit/archive
above, not the moving URLs in comments. Relevant file SHA-256 values:

| Archive-relative path | SHA-256 |
| --- | --- |
| `ggml/src/ggml-cpu/ops.cpp` | `071c64257e4b625abd22e7c4670290d8477e220c8e684871b8d9c16abf867a73` |
| `ggml/src/ggml-cpu/vec.h` | `6afaaa70b626987e15dc37594e434a0cec28437b02391e8f72367239654ec768` |
| `src/llama-vocab.cpp` | `ac6fd43eca27c67a213a98e27b87e8ca1f26d8d82a63e79543a06ca64ef10a95` |
| `src/llama-sampler.cpp` | `6313214bf0a4146036f3d62846299cba4fa9804757c353140a04de52130cf496` |
| `src/unicode-data.cpp` | `5c80b44db0958e673a1940e2a602a5eea2725916ff67bbaeb48ecc7634f84f29` |
| `scripts/gen-unicode-data.py` | `a3ac72675619833115058e33a03d0102205fb3b7c4e8e6d79e18ff2ec86dba55` |

### Windows runtime and delivery gate

Retained `linkage.log` (SHA-256
`739a4c820e2493d1f958f6cd6d9e43ad3abcf664757360c5085ece9fc65683ab`)
identifies x64 PE direct imports:
`KERNEL32.dll`, `ADVAPI32.dll`, `MSVCP140.dll`, `VCRUNTIME140.dll`,
`VCRUNTIME140_1.dll`, and `api-ms-win-crt-` contracts for runtime, stdio, locale,
convert, string, heap, math, environment and utility. This is **dynamic** CRT
linkage despite static engine libraries. It neither identifies all transitive
providers/versions nor authorizes redistribution.

KERNEL32/ADVAPI32 and UCRT contracts require supported-Windows provider and
applicable-terms review. VC C++/vcruntime DLLs are **not assumed OS-provided**.
Obtain exact provider binary identities, matching MSVC/Windows SDK full license
and permitted redistributable list; determine whether the platform supplies them
or separately licensed installation is required. Record policy's provider,
linkage, redistribution, applicable terms and approval. Do not ship runner DLLs
or infer redistribution permission from dumpbin.

Before adoption: close generated/header and selected-term gaps above, then ship
complete selected notices alongside the engine and expose them through the app's
existing license action (including all intrinsic attributions and applicable
data/runtime notices). CI logs or this audit are not user-accessible notice
delivery. No engine notices/assets are added to the app before selection is
approved. Product brokering/session-only consent, model/language reporting,
cancellation/resource failures, verified no-network/no-text-persistence behavior
and Flutter integration remain separate gates. The watchdog is not cancellation
evidence. Draft persistence retains its existing security/recovery gates.
