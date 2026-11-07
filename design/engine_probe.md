# Native-engine feasibility probe

This is **developer tooling only**, not product inference or distribution
approval. Flutter, memory-only drafts and app platform support are unchanged.
Windows x64 has retained native build/inference evidence. Android is the next
core feasibility target: **API 35, default x86_64 hosted emulator only**. Its job
and transport are implemented, but no exact-publication Android native run has
been observed yet. Neither probe adopts an engine into the app. Linux has no
application host; no ARM or physical-device coverage is inferred.

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

## Shared smoke and Windows invocation

On Windows x64 with CMake, MSVC, Python and the digest-named reviewed fixtures:

```powershell
cmake -S tools/engine_probe -B build/engine-probe -A x64
cmake --build build/engine-probe --config Release --target llama-simple --parallel 2
python tools/engine_probe/smoke.py --executable build/engine-probe/bin/Release/llama-simple.exe --timeout-seconds 180 --output-bytes 8192 --fixture-dir C:/reviewed-fixtures --accept-terms-sha256 832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e --tokens 16
```

`smoke.py` never downloads or discovers models. It reads the complete terms
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

`acquire.py` is explicit CI/developer tooling, never a product download path.
It acquires/verifies the complete pinned LICENSE and checks that invocation's
acceptance **before downloading, hashing or reading any weights**. Both native
runners recheck complete terms, card and model before engine use; consent is not
remembered. Fixtures live outside artifact globs, never in an APK or product.
Windows `always()` cleanup and the Android owner trap remove them; runner loss
or job cancellation ultimately relies on disposable runner teardown.

Windows defaults remain two build workers, 300 seconds/network I/O, 180 seconds/
call, 16 tokens, 8192 bytes per stdout/stderr tail, a 10-minute acquisition-step
deadline (step `timeout-minutes`) and a 15-minute job deadline. `ENGINE_DOWNLOAD_TIMEOUT_SECONDS`
remains per-I/O; the step deadline bounds the whole acquisition.
Android has the explicit configuration below. JSON escaping expands printed tails;
spool/build/emulator-log disk use and engine memory are **not hard capped**.
Artifacts retain selected audit inputs, not model weights or executables. Actions
retention applies; failed builds may retain partial raw evidence but cannot pass
capture or inference. Unit tests use synthetic files/transport/processes only.

## Android hosted-emulator invocation and evidence

The `android-cpu` job in `.github/workflows/engine-probe.yml` runs
`bash tools/engine_probe/android_ci.sh`. It reuses the app CI profile
`system-images;android-35;default;x86_64`, `pixel_2`, hardware acceleration and
headless/no-snapshot boot; it does not run or alter app instrumentation.
Pinned Flutter **3.47.9**, revision
`c197ca5199e9ee5661e865596c9c07294dfab51c`, declares NDK **28.2.13676358** in
`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt`. The script
checks that source default and cached version JSON without invoking Flutter CLI.
CMake uses that NDK's Android toolchain, API 35, `x86_64`, `c++_static`, Release
and Ninja. Engine libraries are static; Android system runtime libraries are not.
No extra engine, model, accelerator or third-party Python dependency is selected.

All settings below are required environment variables (workflow values are
documented defaults, not product limits); empty/invalid settings fail closed.
Changing the reviewed target/toolchain requires updating the explicit selection
checks, not silently falling back to a host compiler or latest NDK.

| Workflow configuration | Default / meaning |
| --- | --- |
| `ENGINE_NDK_VERSION`, `ENGINE_API`, `ENGINE_ABI`, `ENGINE_SYSTEM_IMAGE` | `28.2.13676358`, `35`, `x86_64`, `system-images;android-35;default;x86_64`; exact selected profile |
| `ENGINE_AVD_DEVICE`, `ENGINE_EMULATOR_PORT` | `pixel_2`, `5554`; port must be even, within emulator protocol range 5554–5682, and unused |
| `ENGINE_BUILD_ROOT`, `ENGINE_TEMP_ROOT` | `build/engine-probe-android` (must not exist), runner temp base; fresh exclusive temp child owns fixtures and AVD data |
| `ENGINE_DEVICE_ROOT` | `/data/local/tmp`; canonical, existing non-aliased directory, optionally beneath it with alphanumeric/underscore/hyphen components |
| `ENGINE_BUILD_JOBS` | `2`, positive integer |
| `ENGINE_BOOT_SECONDS`, `ENGINE_BOOT_POLL_SECONDS` | `180`, `2`, finite positive boot deadline/poll interval |
| `ENGINE_ADB_SECONDS`, `ENGINE_PROBE_SECONDS` | `30`, `180`, finite positive transport allowance / per-engine device deadline |
| `ENGINE_DOWNLOAD_SECONDS` | `300`, finite positive network-I/O and total Android acquisition deadline; no download retry |
| `ENGINE_OUTPUT_BYTES`, `ENGINE_TOKENS` | `8192` per stream tail, `16` generated-token budget, positive integers |
| `ENGINE_ACCEPT_TERMS_SHA256` | Complete LICENSE digest above, explicit developer-test-only acceptance |
| `ANDROID_HOME`, `FLUTTER_ROOT` | Supplied SDK roots, required; no SDK installation is assumed locally |

The Android job deadline is 25 minutes. `android.py --help` documents the matching
explicit transport CLI: executable/fixture/ADB paths, serial, unique owned AVD
name, device root, acceptance, token, output, engine and ADB budgets are required.
It is **only** for an exclusively owned disposable emulator, never for attaching
to a user's device. The CI script creates a unique AVD name; transport verifies
that name, emulator property, API, ABI and nonempty build fingerprint. Every ADB
operation selects the exact serial. No PTY is allocated, preserving separate
stdout/stderr and remote exit codes; shell arguments use explicit POSIX quoting.

After consent, a unique exclusive device directory receives the real binary,
truncated GGUF and model. SHA-256 verifies every transfer, including binary and
malformed fixture. The shared smoke invokes both real loader rejections and the
same generated-only translation check, with no duplicate prompt/output logic.
Android toybox `timeout -s KILL` watches **the device process**, with the host ADB
timeout adding the transport allowance. Nonzero commands, timeouts, truncated
control evidence, missing diagnostics/providers/hashes and cleanup errors fail.
Device files are removed on success and failure. On any exit the outer CI trap
kills/waits for **only its own session/process group** (`setsid` plus negative-PID
kill) and deletes its exclusive AVD/fixture directory, even if ADB or remote
cleanup fails. The kill ends the wrapper and descendants retaining its group;
wait reaps the wrapper, and the host reaper collects orphaned children. Detached
helpers, untrappable cancellation and runner loss rely on disposable runner
teardown; no broad process-name kill or blind retry is used.

The `android-api35-x86_64-engine-probe` artifact retains raw compile commands,
verbose build log, Ninja commands/link inputs/log/dependency database, NDK version,
compiler version/tool hashes, ELF headers/interpreter/NEEDED entries, executable
hash, Unity units and generated `llama-version.h`/`ggml-version.h`. On-device
linker `--list` output and hashes record the resolved system/APEX providers
alongside runtime fingerprint in `smoke.log`. Pinned Android 15
[`linker_main.cpp`](https://raw.githubusercontent.com/aosp-mirror/platform_bionic/android-15.0.0_r1/linker/linker_main.cpp)
(sha256 `cf65df734b5e8235e6394e8556f74b2cd97ddec2779186a31ccdb6476be4688d`,
lines 807-810 set `g_is_ldd`, 489-492 exit before constructors) and
[`linker.cpp`](https://raw.githubusercontent.com/aosp-mirror/platform_bionic/android-15.0.0_r1/linker/linker.cpp)
(sha256 `d19c5ace78827e3c12b3238778beacb51fe789768251726df3b4cc56b04ae62b`,
lines 3336-3338 emit each non-main library as `\t<soname> => <realpath> (<base>)`)
define the record syntax. A strict parser requires nonempty output, unique
soname/path identities, canonical `/apex/` or `/system/` paths and no skipped
rows; every represented provider is retained and hashed, and
incomplete/unknown/malformed/truncated evidence fails. No mandatory library
names are inferred from link flags (a host `--as-needed -ldl -lm` build can
retain only `libc.so.6`, which warns against that inference without proving
Android closure). These are runtime loader resolution evidence, **not live
process mappings, all dlopen paths, static members or legal closure**.

`ninja_reads.py` matches **actual built** valid Ninja dependency records to unique
configured Clang object commands, cross-checks compiled outputs in the clean
Ninja v5 build log, and requires each compiled source in its own read set. It
rejects missing/empty/stale/malformed/unrepresented/colliding records,
missing or non-file inputs, parent traversal, aliases escaping roots and unknown
providers. Most-specific configured `source`, `generated`, `ndk`, `probe` roots
produce sorted UTF-8/LF SHA-256 manifests (`android-selected-sha256.txt`,
`android-compiled-sha256.txt`) and counts (`android-compiler-summary.txt`). POSIX
case is preserved; Windows tlogs and case folding are not reused. Configured but
unbuilt targets are not included in selected-read membership. Raw evidence remains
available if strict capture fails. The script still attempts independent native
smoke, but returns failure for incomplete capture, never inferred closure.

**Pending native evidence:** exact-publication Android build, real loader and
inference execution, ADB exit/stream behavior, device watchdog and cleanup, and
Android-specific dependency/provider review. A tiny host Clang/Ninja experiment
and synthetic tests validate capture/orchestration only. Header/source read hashes
are not compiled/surviving binary closure, static runtime provenance or legal
approval. Static archive membership, intrinsic branch applicability, full selected
terms and notices, generated Unicode provenance and user-accessible notice delivery
remain adoption gates on each platform independently. This probe establishes no
Android app integration, ARM/physical-device, memory/disk cap, quality, performance,
no-network/privacy, cancellation-in-app or release claim.

## Selected-source and runtime audit

**Not approved for product distribution.** This review applies
[dependency_policy.json](specs/dependency_policy.json), not just root MIT.

### Exact experiment and selected inputs

[Windows CPU probe](https://github.com/t-koba/kotoha/actions/runs/42362657964/job/128374088969)
at published SHA `5553a4a6d749ffdc4d8e30b227bfacb3d0c32143` built the candidate.
`smoke.log` verifies three fixture pins, both loader rejections and generated-only
`Bonjour.`; feasibility only.
Executable SHA-256:
`c4ea7c3feb2f220c7387c247810f287c896929aa2af77156f9d8ee0c5b9c1e9f`.

Artifacts under `windows-x64-engine-probe/build/engine-probe/` at that SHA:
`build.log` and file-API `target-llama-simple-Release-41f60bf4e9c1988c2228.json`
select static `llama`, `ggml`, `ggml-cpu`, `ggml-base` and `examples/simple/simple.cpp`,
not vendor-hash/common/optional backend libraries or configured-but-unlinked targets.
MSVC 14.51.36231: `/MD` (dynamic CRT). Import-library defaults
`kernel32 user32 gdi32 winspool shell32 ole32 oleaut32 uuid comdlg32 advapi32`
do not prove DLL imports.

| Target | Actual compiled translation units / archive source projection |
| --- | --- |
| `llama` | 33 `src/` core files enumerated by `LLAMA_CORE_SOURCES` in pinned `src/CMakeLists.txt`, plus 11 generated `src/CMakeFiles/llama.dir/Unity/unity_{0..10}_cxx.cxx` units. The CMake glob registers all 176 pinned `src/models/*.cpp`, not only Qwen2. Complete Unity inclusion review remains open. |
| `ggml-base` | 9 under `ggml/src/`: `ggml.c`, `ggml.cpp`, `ggml-alloc.c`, `ggml-quants.c`, `ggml-backend.cpp`, `ggml-backend-meta.cpp`, `ggml-opt.cpp`, `ggml-threading.cpp`, `gguf.cpp` |
| `ggml-cpu` | 16 under `ggml/src/ggml-cpu/`: `ggml-cpu.c`, `ggml-cpu.cpp`, `repack.cpp`, `quants.c`, `hbm.cpp`, `traits.cpp`, `binary-ops.cpp`, `unary-ops.cpp`, `vec.cpp`, `ops.cpp`, `amx/amx.cpp`, `amx/mmq.cpp`, `tiled/tiled.cpp`, `tiled/tiled-kernel.cpp`, `arch/x86/quants.c`, `arch/x86/repack.cpp` |
| `ggml` | `ggml/src/ggml-backend-dl.cpp`, `ggml/src/ggml-backend-reg.cpp` (compiled even with dynamic backends disabled) |
| `llama-simple` | `examples/simple/simple.cpp` |

72 actual compile units project to **237 intended archive files**, not header or
binary-member closure. AMX/HBM/tiled compiled conditionally; cache booleans cannot
exclude them. The projection matches retained file-API/MSBuild commands to the
pinned archive. Set SHA-256 `97c258eaed98d7f95ba8b67c123136da6e54008efeaab4f79d804aa04a8cfb10`
uses sorted archive-relative `<lowercase SHA-256>  <path>\n`, UTF-8/LF.
A lexical scan's 84 extra quoted includes are a superset, not selected reads.

[Windows capture](https://github.com/t-koba/kotoha/actions/runs/42365199694/job/128381686713)
`f7fe5b270e533902acef493f34aa8e9c5b417de0`; fully read files:

| Retained file | Observed content | SHA-256 |
| --- | --- | --- |
| `unity_0_cxx.cxx` | 16 model includes, afmoe through clef | `6007c5e57ce9b7b2c24c36aadb0a997417705a402a6f5ce1dfa200a396fe64d2` |
| `llama-version.h` | `LLAMA_VERSION 0.9.0-dev`, `LLAMA_COMMIT f7fe5b2` | `b9e4c5390266e46488e48ad05eb93d7ae12ae85a3f09c4dc9ba508610d64c692` |
| `ggml-version.h` | `GGML_VERSION 0.29.0`, `GGML_COMMIT f7fe5b2` | `839c6d923428164b617e02b2c81400850f75ebef0cfc2072bcef513507734b6f` |

Macros name the workspace, **not upstream**. The 1,000-byte preview of
`llama.dir/Release/llama.tlog/CL.read.1.tlog.txt` shows source/MSVC 14.51.36231/SDK
10.0.26100.0 headers. The 600,419-byte log (SHA-256
`e72a83ac2112285c565d1e8ac3f8544ec96b61e2dad0eaa09f0f85b3ddacf76d`) remains
unparsed. This neither verifies the projection nor rebinds older inference/executable evidence.

`compiler_reads.py` hashes keys (`^source1|source2`) and reads in retained UTF-8
`CL.read.*.tlog.txt`, including source-only keys (pinned `ggml/src/ggml-cpu/hbm.cpp`,
`GGML_USE_CPU_HBM` off). Missing/empty/malformed logs, reads before keys and
missing/non-file/relative/traversing/escaping/unmapped inputs fail closed.
Key-only records may be valid or truncated; record shape cannot prove whole-build completeness.
Roots: source, generated, MSVC (`vswhere`), SDK (Windows Kits registry),
`--windows` (actual `$env:SystemRoot`; no blank/cwd/drive fallback).
Canonical most-specific roots; sorted UTF-8/LF:
`<lowercase SHA-256>  <lowercase path>\n`, no private paths.

Outputs `*-sha256.txt`: `source` (selected archive-relative), `generated`
(build-relative), `toolchain` (`msvc/`, `sdk/`, `windows/`), `compiler-tracking`
(build-relative log hashes). `compiler-summary.txt`: source-key/input and
source/model/header counts, manifest/key hashes (`label/path` keys).
OS reads (sortdefault.nls/tzres.dll) need not be code; labels are provenance,
not legal approval. Native capture, Unity/read-set, provider terms and binary-member closure remain open.

### Terms, provenance and notices

Scope: prospective Windows engine/helper and generated code, not current app
distribution. Models stay separately user-acquired. Unknown AND terms fail closed.
The complete selected MIT branches reviewed below grant unrestricted
use/copy/modify/merge/publish/distribute/sublicense/sell, require copyright and
permission notices in all copies/substantial portions, and include the full
AS-IS warranty/liability disclaimer, without additional restrictions/exceptions.
Retain each full original notice alongside ggml MIT for prospective distribution.

| Component / selected terms | Classification from available full evidence; required notice or missing evidence |
| --- | --- |
| Root `LICENSE`, MIT; copyright 2023–2026 The ggml authors | **permissive** from complete MIT text. SHA-256 `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`. Retain full text; this does not settle adaptations/data below. |
| YaRN in [`ggml/src/ggml-cpu/ops.cpp:6169–6208`](https://github.com/ggml-org/llama.cpp/blob/31424b7cf14604ca65a9195123da1413f31c4472/ggml/src/ggml-cpu/ops.cpp#L6169-L6208), declared MIT, copyright 2023 Jeffrey Quesnelle and Bowen Peng | **permissive MIT origin terms** from the complete reviewed YaRN license below. Retain `Copyright (c) 2023 Jeffrey Quesnelle and Bowen Peng` and the full permission/warranty notice. Compared origin correction dim/range, linear ramp, log magnitude scaling, interpolation/extrapolation mix and cos/sin with pinned `ops.cpp:6164–6186` and `ggml.c:4528–4546`; not an identical whole-file translation. |
| BPE in [`src/llama-vocab.cpp:242–245`](https://github.com/ggml-org/llama.cpp/blob/31424b7cf14604ca65a9195123da1413f31c4472/src/llama-vocab.cpp#L242-L245), declared MIT, adapted from `cmp-nct/ggllm.cpp` | **permissive MIT origin terms** from the complete reviewed ggllm license below. Retain both copyright lines: `Copyright (c) 2023 https://github.com/cmp-nct`; `This project includes work that is Copyright (c) 2023 by Georgi Gerganov`. Retain the full permission/warranty notice. Origin `libfalcon.cpp:2590–2620,2622–2752,2755–2776` matches the rank/left tie-break, symbol merge/outdated-bigram check and linked neighbors in pinned `llama-vocab.cpp:265–279,741–771,827–850`; later regex/tokenizer extensions remain unresolved. |
| Z-algorithm in `src/llama-sampler.cpp:3485–3539`, attributed to Ivan Yurchenko | **public-domain**, selected Unlicense: complete origin terms dedicate all copyright to the public domain in perpetuity for public benefit and permit anyone to copy/modify/publish/use/compile/sell/distribute source or binary for any commercial/noncommercial purpose, by any means, with full AS-IS warranty/liability disclaimer and no added conditions. No legal notice-retention requirement; project notice policy will retain the complete text and existing attribution. Origin `z_algorithm.py` matches the lt/rt Z-box bounds and inside/outside cases, adapted for reversed tokens and range limits, not an identical whole file. |
| Arm exponential adaptation in `ggml/src/ggml-cpu/vec.h:1320–1348` (SSE2 branch at 1306/1316) | **permissive MIT origin terms**, selecting only MIT from `MIT OR Apache-2.0 WITH LLVM-exception`. Retain root `Copyright (c) 1999-2022, Arm Limited.` and originating file `Copyright (c) 2019-2023, Arm Limited.` with the complete MIT permission/warranty notice. Origin `math/aarch64/v_expf.c` matches five exact polynomial coefficients, `0x1.8p23f` rounding shift, split ln2 range reduction, exponent construction, 126/192 bounds and special-scale biases. This is an attributed intrinsic-algorithm adaptation, not an Arm library/header dependency; no unrelated Arm EULA or glibc copy is selected. **MSVC branch applicability remains unverified**: disabled Arm/AVX flags do not establish `__SSE2__` selection/exclusion; actual compiler/preprocessor evidence is required. |
| Generated `src/unicode-data.cpp` and generator `scripts/gen-unicode-data.py` | **Reference-data terms permissive; selected redistribution/provenance closure open.** All eight numeric tables are semantically matched to immutable Unicode 16.0/15.1 audit references below, not byte-identically regenerated. The generator mixes moving UCD `latest/ucd/UnicodeData.txt` and Python `unicodedata`; original production-host inputs and exact historical generator/Python provenance remain unverified. Root MIT and the app's UCD 17 bidi notice do not establish these data terms. |

**Unicode audit references and equivalence.**
[Audit fixture manifest](fixtures/engine_unicode/fixtures.json) pins five inputs'
immutable URLs, SHA-256 hashes and byte sizes at official `unicode-org/unicodetools`
commit `addf0c992050b10a0bfe8647f90fcc8fdbfe71fc`, tag `final-16.0-20240912`:
Unicode 16 data under `unicodetools/data/ucd/dev`, 15.1 under `ucd/15.1.0`,
and root `LICENSE`. The revision's [README](https://raw.githubusercontent.com/unicode-org/unicodetools/addf0c992050b10a0bfe8647f90fcc8fdbfe71fc/README.md) says contents use `LICENSE` but explicitly warns
against production use of this repository's data and points to unicode.org.
These are **audit references, not replacement product data**.

A reviewed strict comparison parsed the complete selected 288,635-byte C++ file
(hash below) and semantically reconstructed all eight numeric initializers:
- Unicode 16: canonical CCC 934, raw decomposition 2,081, composition 961
  (excluding 1,120 `Full_Composition_Exclusion` entries); whitespace exactly 25
  entries, independently matched to 16 `PropList.txt`.
- Unicode 15.1: aggregate flags over all 1,114,112 code points, lowercase 1,433,
  uppercase 1,450, first-codepoint NFD 13,233; exact ordered compressed flags
  2,273 rows including terminal sentinel, NFD 1,828 including initial dummy sentinel.

The legacy flags differ from Unicode 16 at 5,185 code points; each case map lacks
27 keys and NFD lacks 20, so the normalization comment cannot label the whole file.
Different generator/output containers mean semantic equality, **not** byte-identical
full regeneration, original generation history or supported-tokenization correctness.

Complete root `LICENSE` (2,033 bytes; pinned in manifest) is **permissive Unicode-3.0**,
`Copyright © 2001-2024 Unicode, Inc.`: unrestricted use/copy/modify/merge/publish/distribute/sell
and permission for recipients; retain copyright/permission in copies **or** associated
docs; full AS-IS warranty/liability disclaimer; no holder-name advertising/promotion
without prior written authorization. Reviewed ancestor listings also found
[`unicodetools/license.html`](https://raw.githubusercontent.com/unicode-org/unicodetools/addf0c992050b10a0bfe8647f90fcc8fdbfe71fc/unicodetools/license.html), complete permissive ICU4J 1.3.1+ terms, © 1995–2002 IBM
and others, SHA-256 `eccd9d05b25e26a29b6b868c777b73b1c6399ca318d857e606c2e06a90527f4c`:
retain copyright/permission in copies **and** supporting docs, full AS-IS/nonendorsement.
This is not an OR alternative for UnicodeData or evidence of an ICU4J dependency;
ancestor-notice applicability remains open, not presumed overridden. Before adoption,
resolve selected redistribution terms and deliver full applicable Unicode notices
through the user-accessible license action below; none is claimed already shipped.

Reviewed immutable origin evidence (not proof of the exact historical adaptation
revision):

| Origin file | SHA-256 |
| --- | --- |
| [YaRN LICENSE at 995db5b575e75230b3384d658f8b944c9662f775](https://raw.githubusercontent.com/jquesnelle/yarn/995db5b575e75230b3384d658f8b944c9662f775/LICENSE) | `c3ec00ded224ebaaa673373961babc2d79f3081914897f3325cb7927a76234c1` |
| [YaRN scaled_rope/LlamaYaRNScaledRotaryEmbedding.py at the same revision](https://raw.githubusercontent.com/jquesnelle/yarn/995db5b575e75230b3384d658f8b944c9662f775/scaled_rope/LlamaYaRNScaledRotaryEmbedding.py) | `fa097066e5792239ff4375dd84ed65d6c01bce8a2b6f1083dd4504151210a4af` |
| [ggllm LICENSE at 0dc65eb735f90f82143ead9dedb66e73fa25d114](https://raw.githubusercontent.com/cmp-nct/ggllm.cpp/0dc65eb735f90f82143ead9dedb66e73fa25d114/LICENSE) | `03871befb92d000a22dd5d5fe89381afe4ae461a219d2d4f79912dfdb5e56a23` |
| [ggllm libfalcon.cpp at the same revision](https://raw.githubusercontent.com/cmp-nct/ggllm.cpp/0dc65eb735f90f82143ead9dedb66e73fa25d114/libfalcon.cpp) | `eb8c6af6bbfcba7b217abde03d42c2da6fc4cb867481b1d93d50af8843e9597a` |
| [string-algorithms LICENSE at 70a15fdbb1705250891479b0f3f52ca2afffd48b](https://raw.githubusercontent.com/ivanyu/string-algorithms/70a15fdbb1705250891479b0f3f52ca2afffd48b/LICENSE) | `7e12e5df4bae12cb21581ba157ced20e1986a0508dd10d0e8a4ab9a4cf94e85c` |
| [string-algorithms z_algorithm.py at the same revision](https://raw.githubusercontent.com/ivanyu/string-algorithms/70a15fdbb1705250891479b0f3f52ca2afffd48b/z_algorithm.py) | `b67658546b153e0fe7eec1abf43b6ed1e5680966fd9b6d2f9254d60977d58f2c` |
| [optimized-routines LICENSE at 7999fd9f7ed482dc663befc16f56321344c0de1d](https://raw.githubusercontent.com/ARM-software/optimized-routines/7999fd9f7ed482dc663befc16f56321344c0de1d/LICENSE) | `650afbf29f214451e02241adc42534e82c9d6ae2b38e2444b92b5a1ffcaf9346` |
| [optimized-routines math/aarch64/v_expf.c at the same revision](https://raw.githubusercontent.com/ARM-software/optimized-routines/7999fd9f7ed482dc663befc16f56321344c0de1d/math/aarch64/v_expf.c) | `ee23ed7c8589559bf875e14ff46127d0dbf707fea6e35f414d00dcace7471ada` |

For the four algorithm origins above, complete terms, relevant routines and
directory listings were reviewed; no additional applicable notices were found. `libfalcon.cpp` declares MIT;
`v_expf.c` declares the dual terms above. The Arm origin is a matching preexisting
2023-06-15 revision, not a proven historical adaptation revision. These comparisons
settle origin terms, not later tokenizer extensions, exact historical provenance
or selected binary applicability. Root MIT does not replace origin notices;
all other closure and user-accessible notice-delivery gates remain open.

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
