# Native-engine feasibility probe

This is **developer tooling only**, not product inference or distribution
approval. Flutter, memory-only drafts and app platform support are unchanged.
The latest exact native probe is publication
`788dba8903ab7a69988a6b2d575984d4a453553bf3bdfe6cfe7bc4ac30497f40` at SHA
`6e082a6587a7f718b9137a4c0b0b520511981ae5` (code digest
`964a31ce8d07eb3cb3054c04ddab81c374a316b1da785311a815a7e41c720287`, source
commit `e08721f846a6c3d695d47062e8ad649b8f365c97`). Android API 35 x86_64 job
`128511407263` and Windows x64 job `128511407372` passed. Android recorded 72
actual compiled objects, 1,435 unique selected compiler inputs, the exact
link-map archive/member manifest, and a bounded installed-NDK record capture for
`28.2.13676358` (r28c). The owned Android 15/API 35 x86_64 emulator rejected
missing/truncated GGUF and generated the narrow synthetic `Bonjour.` sample
using the explicitly accepted, pinned developer fixture. This is probe evidence
only, not app integration, distribution approval, quality, ARM or physical-device
coverage.

The exact `android-api35-x86_64-engine-probe` artifact includes the map and a
link-map-bound archive manifest. The complete manifest is 5,417 bytes and its
locally verified artifact SHA-256 is
`0025215e4aa2935b70d7a532c549640bb99177a6cd4e006d40fc138c5668b238`
(`vcs-read/55e65c98f20b4ee2a532a4b35e8a8dda`). Its declared map size/hash
(4,660,773 bytes; SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`) matches
the exact publication's 96-byte sidecar (`vcs-read/b2094d1e511b425c871e98763f989025`).
This confirms internal manifest/sidecar agreement, not an independent re-hash
of the 4.66 MB raw map, which has not been fully assembled here.

The manifest records the following archive files and exact build hashes:

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| `libggml-base.a` | 10,016,748 | `344edbad2736ace0222452ca5b9490592cb1e258146a5ac6d43bc3902f67398c` |
| `libggml-cpu.a` | 8,072,970 | `303132d570d054729a74ec1d1c7023ecacc31e0c52779d527e4c9002e2544110` |
| `libggml.a` | 823,710 | `c05c0b4b2a4880e613862fdafe5d79080f1f760587509f11792c74fedd895be4` |
| `libllama.a` | 83,403,538 | `665926e6210e5b33d291e9e7efd5b2114204d58552616295f8168c04eabeab43` |
| NDK `libclang_rt.builtins-x86_64-android.a` | 303,678 | `82419d3e4735288342b2042c7418c3f49e352a721f43ce3966918a835580326a` |
| NDK `libunwind.a` | 94,182 | `a1d9a8a7242c22c32c1ce57108f2c4f6687f4af5c0526b207e394f2099e8482a` |
| NDK `libc++_static.a` | 14,336,094 | `893dc67b8c7eef4000af6e582421a14ea7e5fdec97249496005fc3a48f7d7099` |
| NDK `libc++abi.a` | 2,792,306 | `11ff6729a881f3d1a2e72c2a9c4bd2c096e02c5dfb3858d942405e0514b7b95c` |

The manifest identifies selected members, including both `libc++_static.a` and
`libc++abi.a`; the four NDK archives name 47 members (1 compiler-rt builtin,
5 libunwind, 26 libc++, 15 libc++abi). Neither the manifest nor archive hashes
prove which linked sections survive or close licensing.

### NDK archive-member source terms (partial)

The exact manifest's four NDK archives name 47 members: one compiler-rt builtin,
five libunwind objects, 26 libc++ objects, and 15 libc++abi objects. Mapping each
member basename into its component's source directory at the compiler-reported
LLVM commit `97a699bf4812a18fb657c2779f5296a4ab2694d2` identifies candidate
source files (`compiler-rt/lib/builtins/emutls.c`, `libunwind/src/`,
`libcxx/src/` including `filesystem/`, and `libcxxabi/src/`). The fetched source
headers at that immutable revision declare
`SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception`; under
[dependency_policy.json](specs/dependency_policy.json), this is a permissive
branch. The archive and member names/hashes are from the exact Android link-map
manifest; a member-name-to-source path match alone does not prove the compiled
object bytes or surviving sections correspond to those unmodified source files.

The full upstream terms were read at that same revision, including each
component's own `LICENSE.TXT` (SHA-256 values are whole-file digests):

| Upstream record | SHA-256 |
| --- | --- |
| LLVM `LICENSE.TXT` | `8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee` |
| `compiler-rt/LICENSE.TXT` | `1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d` |
| `libunwind/LICENSE.TXT` | `b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d` |
| `libcxx/LICENSE.TXT` | `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b` |
| `libcxxabi/LICENSE.TXT` | `e2b35be49f7284a45b7baca8fc7b3ab7440e7902392b2528a457816b5bb2a15c` |

The Apache 2.0 text plus LLVM exception classifies as permissive; the exception
specifically relaxes Apache sections 4(a), 4(b) and 4(d) for portions embedded
in object form. Some component `LICENSE.TXT` files also retain legacy UIUC/NCSA and MIT
license text, so this source-level classification does not imply that every
other file, included header, generated input, notice or linked section shares
it. Exact package-record capture and member-to-input/section closure remain
necessary. No product adoption or notice set is approved by this partial result.

### Exact installed-NDK capture (partial)

The corrected capture ran in the exact successful publication above. Its bounded
manifest (`ndk-terms/manifest.json`, 2,735 bytes, SHA-256
`6a92040adc41f19068e0e621c0e0b17ff00f6d55d77423312cb7edc61740bff8`;
`vcs-read/2682820f207946d5a86e7c75534c20ed`) records 10 files totaling
1,988,532 bytes under its 64-file/16-MiB limits. Its declared capture scope is
package metadata plus matching root-level and host LLVM-toolchain license/notice/
copying/copyright files, not a complete package inventory or legal classification.
`source.properties` identifies
NDK 28.2.13676358 / r28c (108 bytes, SHA-256
`c00aa236fdb205e9be9edd9e2169763e48aca52735efff4e16f34205d49783b5`;
`vcs-read/f845b129ad87496a82bd46bc886cf4db`). `package.xml` records the same
package revision and `uses-license ref="android-sdk-license"` (18,351 bytes,
manifest SHA-256 `1d901b6452ef3f759a7d7a09b0c3ea5d745a60a8ae9a5be06db24b893ebf8a9a`).
The manifest also identifies the following broad candidate notices; their
presence does not establish that every included notice applies to linked members:

| Installed NDK record | Bytes | SHA-256 |
| --- | ---: | --- |
| root `NOTICE` | 516,438 | `faf0dc52cf6ce9ab09a04b0c074a378dd2565ee1ed9bc1179d83793bcdba012e` |
| root `NOTICE.toolchain` | 799,639 | `789714a9076571c580cf531bdcebec776a4d889c12c3c1108adafc6e4338710a` |
| LLVM toolchain `NOTICE` | 130,424 | `f96f763beb66a7ba7a667647fc64c0226ace875e590c831fdd9579ec1c1d91e1` |
| LLVM toolchain `clang_source_info.md` | 11,370 | `8ffa6ebc4941a0f0de492584444c08b65ce96ba32d824d674fd35aa0398f1454` |
| LLVM sysroot `NOTICE` | 494,921 | `2905ac5c59628352af990c748a8f4c3675a04f36eca7914612e3068661d2c6a6` |

The manifest additionally hashes the NDK toolchain's Python, pip and setuptools
license files. The inspected start of `NOTICE.toolchain` contains GPL-2.0 text;
the inspected sysroot notice contains multiple distinct attribution/license
texts. These broad installed-package records are not a license classification of
the four map-selected static archives. The required notice subset and applicable
terms remain unresolved until each selected archive/member and affected patch or
section is mapped to its source, terms and distribution obligation.

The compiler log reports Android clang 19.0.1, based on r530567e, repository
commit `97a699bf4812a18fb657c2779f5296a4ab2694d2` (`vcs-read/c2129f0d0cae49969429c6c18adadfde`). An exact upstream commit-metadata read identifies this as “Merge 3b5e7c83… for LLVM update to 530567”, with `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` as its second parent. The installed `clang_source_info.md` instead names that `3b5e7c83…` commit as its base revision and lists Android toolchain patches from repository revision `e727bfb014bd436f581a66a450c939a6983a1fc3`. The component `LICENSE.TXT` hashes recorded above were re-fetched at base revision `3b5e7c83…` and match, but this verifies only identical license-text bytes, not that the patched installed archives' selected object code matches the mapped source files. Patch-to-member/source closure remains open.

### Installed patch overlap (partial)

The exact `clang_source_info.md` artifact names patches at the immutable Android
LLVM toolchain revision `e727bfb014bd436f581a66a450c939a6983a1fc3`
(`vcs-read/5a60708a01b74460876c8a8e9ec0ecb9`,
`vcs-read/af0cdd28285b41128da2817ec8144328`). Comparing those names with the
exact map manifest and compiler-selected-input manifest identifies two direct
review targets:

- **LLVM `[libc++][regex]`, commit
  `e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562`** ([upstream patch](https://github.com/llvm/llvm-project/commit/e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch)). The map selects
  `libc++_static.a` member `regex.cpp.o`; the compiler-read manifest also
  includes NDK `sysroot/usr/include/c++/v1/regex`, SHA-256
  `2ea7d95853a15ef16925668750ccdface9deead18c79fb3e8064447ff326d982`
  (`vcs-read/0c02cedb3b654a8c9337056fd789694a`,
  `vcs-read/6b5d012196944a40b1d34698e6ada3f2`). The upstream patch modifies
  `libcxx/include/regex` and tests; its patch SHA-256 is
  `8f3f35279594e3999168d21ab51ede6a8e7f8769ecefe66efd9fb1c1625951bc`
  (fetch receipt `44b03fac704e9f67d999f318e51617cbea6806aca11e878ca8ea2865ca7bcd81`).
  Its source/header terms are LLVM Apache-2.0 WITH LLVM-exception. But the
  installed header digest differs from both the unpatched base/merge header
  (`897795afd99ac6fea51498ab5bdcdfac55bfd652e82200e8a0fe8a3d9ea35451`) and
  the file at the single upstream patch commit
  (`60ae1433a22fac00ed0935778d1f3fa7e33b37e99aa33e1907273fa02fdd685a`). The
  exact installed header therefore is not reconciled to that patch alone; this
  does not prove whether or how it changes the selected archive object's
  surviving code.
- **`move-cxa-demangle-into-libcxxdemangle.patch`.** The map selects
  `libc++abi.a` member `cxa_demangle.cpp.o`
  (`vcs-read/0c02cedb3b654a8c9337056fd789694a`). `clang_source_info.md` names
  this patch, but its payload is absent from the bounded CI capture. Its changed
  files, authorship, terms, and effect on the selected object/archive cannot
  yet be established.

The source-info list also contains opaque patch filenames including
`9a2fd97d391caf1060e303f636d7113501788d2f-r530567.patch` and
`b433076fcbacba8a3b91446390bbea5843322bcd-v2.patch`; their payloads were not
captured. Patch titles or a source basename are not enough to rule out changes
to selected runtime inputs. The capture does not contain every patch, installed
runtime source file, or object/section-level provenance. Thus this is a useful
crosswalk, not a patch-to-member closure or approval of the broad NDK notice set.

### Pinned patch-source audit capture

The Android probe now has a bounded audit-only capture for the three named patch
payloads above, at the exact `llvm_android` repository commit
`e727bfb014bd436f581a66a450c939a6983a1fc3` recorded by the installed NDK
`clang_source_info.md`. It shallow-fetches that full commit ID into a temporary
bare Git object store under one 120-second total deadline. It resolves the
three exact filenames under `patches/`, rejects missing/duplicate/non-regular
blobs, and records each path, Git blob ID, byte length and SHA-256 in
`ndk-patch-sources/manifest.json`. The configured 16 MiB bound covers the patch
tree index and selected payloads; the fetch pack itself has the time deadline but
no separate hard byte cap. Raw patch payloads and other fetched repository
objects remain only in the temporary store and are not uploaded, avoiding
unreviewed source redistribution; no fetched source is executed. CI runs the
native probe smoke even if this audit capture fails, retains the bounded failure
log, then returns failure so missing patch evidence cannot look green. Local
unit tests use synthetic Git repositories only.

This capture change has not yet run in exact CI. The earlier successful
publication contains no manifest for these pinned patch sources. Even after
capture, matching patch paths to the installed archive's actual object
bytes/surviving sections,
reviewing all applicable terms and determining the required shipped notices
remain open; this is not an adoption or distribution approval.

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
| `ENGINE_LINKER_MAP_MAX_BYTES` | `134217728` bytes (128 MiB); Android LLD map is retained whole or the probe fails, never truncated |
| `ENGINE_NDK_TERMS_MAX_FILES`, `ENGINE_NDK_TERMS_MAX_BYTES` | `64` records, `16777216` bytes (16 MiB); installed-package record capture fails rather than silently omit files |
| `ENGINE_NDK_PATCH_MAX_BYTES`, `ENGINE_NDK_PATCH_FETCH_SECONDS` | `16777216` bytes (tree index plus selected patch blobs), `120` seconds total fetch/capture deadline |
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

The Android-only `llama-simple` link emits LLD `-Map` to `llama-simple.map` inside the clean configured build root. After linking, the probe requires a regular, nonempty file no larger than `ENGINE_LINKER_MAP_MAX_BYTES` (128 MiB default). `linker_map.py` parses and hashes the map in one bounded pass, resolves every `.a(member)` row within the configured build or NDK root, hashes each unique regular archive, and stages `llama-simple.map`, its byte-size/SHA-256 sidecar and `llama-simple.map.archives.json` together before one directory rename. The archive manifest lists root-relative paths, exact archive sizes/digests and the member names named by the map; it does not prove source licensing or which sections survive. The map remains raw linker output, not a normalized inventory: inspect its exact rows rather than infer completeness from `-static-libstdc++` or ELF `NEEDED`. The updated inventory is now present in successful exact CI publication `788dba8903ab7a69988a6b2d575984d4a453553bf3bdfe6cfe7bc4ac30497f40`; it still does not prove which sections survive or establish complete runtime/legal closure.

The `android-api35-x86_64-engine-probe` artifact retains the linker map, its hash/size record and, on successful capture, the archive manifest alongside raw compile commands,
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

`ninja_reads.py` matches valid Ninja dependency records for **actual built** compiler
objects to unique configured Clang commands, cross-checks compiled outputs in clean
Ninja v5 or v7 build logs (both use the validated five-field record shape), and
requires each compiled source in its own read set. Dependency records for non-object
link outputs are outside compiler-read scope; the linked executable's target query
is retained separately. Unmapped `.o`/`.obj` records still fail, and every compiled
output in the build log must have its own validated dependency record. Unknown log
versions remain rejected. Compiler records reject missing/empty/stale/malformed
entries, missing or non-file inputs, parent traversal, aliases escaping roots and
dependencies outside configured roots. Every raw compiler dependency is resolved and checked; the output
manifest deduplicates paths that resolve to the same canonical file. Most-specific
configured `source`, `generated`, `ndk`, `probe` roots produce sorted UTF-8/LF
SHA-256 manifests (`android-selected-sha256.txt`, `android-compiled-sha256.txt`)
and counts (`android-compiler-summary.txt`). POSIX case is preserved; Windows
tlogs and case folding are not reused. Configured but unbuilt targets are not
included in selected-read membership. Raw evidence remains available if strict
capture fails. The script still attempts independent native smoke, but returns
failure for incomplete capture, never inferred closure.

**Current evidence limits:** publication
`788dba8903ab7a69988a6b2d575984d4a453553bf3bdfe6cfe7bc4ac30497f40` records
the exact Android x86_64 static archives, member names and archive hashes. The
ELF artifact reports `/system/bin/linker64` and direct imports `libm.so`,
`libdl.so`, and `libc.so` (`vcs-read/358bf47a662346b1a59712bee63dc60c`). The
owned API 35 x86_64 emulator's loader output resolves them to
`/apex/com.android.runtime/lib64/bionic/` and records provider hashes in the
exact run's `smoke.log` (`vcs-read/c461d14a496a467bb4130df4de43ff90`,
`vcs-read/2224d928d73544789d129a8ec91cd98e`). This does not establish other
ABIs/OS versions, live application mappings, all `dlopen` paths, Android
system-provider license notices, or product linkage. The raw linker map still
needs independent complete-byte verification; installed NDK notices have been
captured but their applicability to selected members and the distribution notice
set remain unresolved. Nothing here authorizes engine adoption, model
distribution, persistence, privacy, quality, or platform-support claims.

## Selected-source and runtime audit

**Not approved for product distribution.** This review applies
[dependency_policy.json](specs/dependency_policy.json), not just root MIT.

### Exact experiment and selected inputs

The detailed selected-source Windows capture below is from exact publication
`f679d5f55a5932db170300e9ed6fcb42949c877b37d84a81b7fbfbb25bee00c2` at SHA
`ef16f3cbc8a9d802ab7d676f6ec41cf93f275911`; its paired Android job failed before
compilation at the then-unfixed CMake target guard. A subsequent exact publication
`820eba2fea04674dae6af0e4f296a730f4116248223915f4a375e94741ac1810` at SHA
`0e08c89d1022a51ad4c815b25bdc46ca20c3a2a8` passed the Windows job and advanced
Android through cross-compilation, emulator start and linker check before the
initial parser failures described above. Newer exact publication
`0d94696cd2df2af8b75319e9393b0b47ed427bb857fa4716247fe4101d355979` at SHA
`85ce0d2e928eec5dd4732c66075e6ca2d557d867` again passed Windows and completed a
narrow Android loader/inference smoke, but strict Android selected-read capture
failed with duplicate canonical dependencies. The Windows byte-counted file manifest
below remains the detailed capture from `f679d5f`; current artifacts under
`windows-x64-engine-probe/build/engine-probe/`:

| Retained file | Bytes / represented inputs | SHA-256 |
| --- | --- | --- |
| `source-sha256.txt` | 27,243 / 302 archive files: 237 C/C++ (including 176 model files), 65 headers | `faf08d710aacca675ffbebd3470592a9ae0efda170d6b4657fcb62fad446eb2c` |
| `generated-sha256.txt` | 1,420 / 11 Unity units and 2 version headers | `878e6081ada8c2be995b98bf382e7b30b3e27c3d77e0cd469e36688ddca9547f` |
| `compiler-summary.txt` | 1,022 / 72 source keys, 581 represented inputs: source 302, generated 13, MSVC 141, SDK 123, Windows 2; 5 tracking logs hashed separately | `3e641af006b845ff846f35ab079d66a9962acb7378d98bb2fa343a6b95612522` |
| `smoke.log` | 10,610 / pinned-fixture validation, loader rejections and one synthetic inference sample | `c38c28a073b4e8b64971c0395685a09636bc6e6e1c27ee22e677abe4380d8736` |
| `linkage.log` | 6,588 / x64 PE headers and direct imports | `6c37378410ba3ab8d5f7b3bde7adeeece15fd33bfeb13bebbb06a87402660285` |

The latest source-manifest digest is unchanged from the independently checked
302-file archive manifest. All 11 raw Unity units and both version headers were
read at this SHA and matched the 13-entry generated manifest. Each Unity unit
includes 16 model files: **176 unique inclusions**, matching the model entries
in the unchanged source manifest and the pinned archive's complete
`src/models/*.cpp` set. The archive-manifest review hashed all 302 selected
regular, nonlink members, matched their sorted UTF-8/LF hash/path projection, and
found no Windows-canonicalized traversal/casefold collisions. This independent
source check and the actual CI build are separate evidence.

The pinned
[`src/CMakeLists.txt`](https://github.com/ggml-org/llama.cpp/blob/31424b7cf14604ca65a9195123da1413f31c4472/src/CMakeLists.txt)
selects these models, not only Qwen2, and 33 separately compiled core files.
The 72 compile units project to 237 archive C/C++ files: llama 33 core + 176
models, ggml-base 9, ggml-cpu 16, ggml 2, simple 1. Projection SHA-256
`97c258eaed98d7f95ba8b67c123136da6e54008efeaab4f79d804aa04a8cfb10`
uses sorted `<lowercase SHA-256>  <archive-relative path>\n`, UTF-8/LF.
The source-only `ggml/src/ggml-cpu/hbm.cpp` key is included, hash
`e5cf5c8327f99ccb58461d8416e27bc38da01d9bd450e48f3df69bd34a81a47c`;
it does not imply additional dependencies. AMX/HBM/tiled files are represented
regardless of whether their conditional bodies survive preprocessing.

Both current version headers declare llama `0.9.0-dev` and ggml `0.29.0`,
with commit macros `ef16f3c` (the published probe source, not the pinned upstream
llama.cpp commit). Generated-manifest keys lowercase `CMakeFiles`/`Unity`;
artifact paths retain case. The summary's source-key fingerprint is
`1bdca7142f8c67bf78ee76e00d819a86b4a2f09542828645ba859913d857d5d2`.

`compiler_reads.py` hashes UTF-8 tracking-log keys and reads, including source-only
keys; missing/empty/malformed logs and missing, non-file, relative, traversing,
escaping or unmapped inputs fail closed. Most-specific canonical roots label
source, generated, MSVC (`vswhere`), SDK (registry) and Windows (required actual
`SystemRoot`, no fallback), with sorted lowercase relative paths. OS reads
(sortdefault.nls/tzres.dll) need not be code; labels are not legal approval.
Key-only records may be valid or truncated: shape alone cannot prove completeness.

At the same exact publication, `smoke.log` records the complete pinned model
terms/card/weight checks, real-loader rejection of missing and truncated GGUFs,
and one generated-only `Bonjour.` sample; it is not a language or quality
evaluation. `executable-sha256.txt` records the tested executable as
`6e697bcc371771d7a0a97947c7c4db110902d8992a9fdd4ee6666edd7d07e881`. Its
file-API evidence selects static llama/ggml/ggml-cpu/ggml-base and the simple
consumer, not common/vendor/optional backend libraries. The exact captured PE
imports below provide runtime-provider evidence for this build, not license or
redistribution approval.

The Windows compiler reads and source/Unity projection are not surviving binary
membership, actual intrinsic preprocessing, complete static-provider/runtime
redistribution or license/notice closure, or Unicode production provenance. The
separate Android archive/member inventory below identifies its map-selected
archives, but not surviving executable sections or legal/runtime closure. Product
integration, quality and privacy are also unverified. Adoption gates remain open
independently for each platform.

### Android API 35 x86_64 selected archives and runtime

The exact publication and archive inventory above establish this **developer
probe** selection only. `ndk.properties` records NDK r28c (`28.2.13676358`;
`vcs-read/a4ed2e3e281e435599b585f534797afc`). `compiler.log` identifies clang
19.0.1 based on `r530567e` and Android LLVM project commit
`97a699bf4812a18fb657c2779f5296a4ab2694d2`
(`vcs-read/66f8fe7be295487b87338a4c2567bcfc`). `link-inputs.txt` names the four
engine archives; the map-derived manifest additionally records the selected NDK
builtins, `libunwind.a`, `libc++_static.a`, and `libc++abi.a`, with exact member
sets and archive hashes. The linker-map sidecar and manifest agree, but the
complete raw map has not been independently assembled/rehashed, and map members
are not proof of retained executable sections.

`linkage.log` identifies ELF64 x86_64, interpreter `/system/bin/linker64`, and
`DT_NEEDED` imports `libm.so`, `libdl.so`, and `libc.so`. The smoke's explicit
Android linker query records `linux-vdso.so.1` and maps those imports to the
Android 15 runtime APEX, with provider hashes (`vcs-read/fed9e003654c46edb91d72c34596b3f2`).
These are emulator-provided libraries, not bundled NDK archives; this observation
is limited to this exact API 35 x86_64 system image.

The NDK r28c release page identifies `clang-r530567e` and directs users to the
installed `clang_source_info.md`. The Android Clang toolchain guide explains that
this file identifies the LLVM project commit, cherry-picks and downstream changes.
Android NDK C++ documentation describes `libc++` as LLVM's standard library and
states the LLVM Project is under Apache License 2.0 with LLVM Exceptions. These
general statements are not a hash-bound license record for the selected archive
members. Earlier probe artifacts omitted the exact `clang_source_info.md`, NDK
package metadata and license/NOTICE files. The workflow now runs a bounded capture
of `source.properties`, `package.xml`, required
`clang-r530567/clang_source_info.md` and `clang-r530567/NOTICE`, plus regular
license/notice/copying/copyright-named records at the NDK root and under
`toolchains/llvm/prebuilt/linux-x86_64`. It retains `ndk-terms/manifest.json`
and the original bytes under `ndk-terms/records/`; the manifest hashes and sizes
every record. The configured 64-file/16-MiB bounds fail closed. Until the next
exact Android job passes and its records are reviewed, this is a capture
implementation, not source/terms evidence. It does not classify archive members
or prove which source terms apply. The member/source mapping and complete
applicable per-file terms remain open. Do not infer complete license
classification from docs or from `libc++`'s name. **Android engine adoption
remains disabled** pending exact source/terms/notices, any third-party exceptions,
binary/runtime closure, and platform-specific review. The official reference
points are the [NDK r28c release](https://github.com/android/ndk/releases/tag/r28c),
the [Android Clang toolchain guide](https://android.googlesource.com/toolchain/llvm_android/+/main/README.md),
and the [NDK C++ library support guide](https://developer.android.com/ndk/guides/cpp-support);
these guides are explanatory, not substitutes for the exact package records.

### Planned user-accessible notice delivery

The app already registers its Unicode notice with Flutter's `LicenseRegistry` and
exposes the standard `LicensePage` from its existing `show-licenses` action;
`test/licenses_test.dart` checks that notice end to end. Once the applicable
engine/runtime notice set is established, package each complete required notice
as an offline app asset, register it by component through `LicenseRegistry`, and
reuse that in-app Licenses page. Extend the widget test to open each component
and compare its displayed complete text with the bundled source. This keeps
notices available without network access and uses Flutter's platform-standard
scrollable license surface rather than an external link or a separate custom
viewer. No new engine notice asset is added until its applicability and exact
text are established.

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

The pinned `src/unicode-data.cpp` records at line 7035 `Canonical normalization
tables: Unicode 16.0.0`; its pinned generator derives that marker from Python's
`unicodedata.unidata_version`. This identifies only the normalization tables, not
the separately fetched `UnicodeData.txt` input: the generator fetches UCD `latest`,
and its historical input bytes and interpreter environment remain unknown.

The legacy flags differ from Unicode 16 at 5,185 code points; each case map lacks
27 keys and NFD lacks 20. The normalization marker therefore cannot label the whole file.
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

### Android selected runtime and delivery gate

The exact Android API 35 x86_64 probe is publication
`e9d1b9920dffbdb5825e5a0d8aa6751fc838b4e28fc2e575e104f9adc3c80464` / SHA
`e91f1c4218dbc3e69cee2bd1d122fcd2b43b3ead`, job `128479488127`. `link-inputs.txt`
selects static `libllama.a`, `libggml.a`, `libggml-cpu.a` and `libggml-base.a`; the
LLD map includes NDK `libc++_static.a` rows. The map sidecar asserts size 4,660,773
and SHA-256 `2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`.
The exact ELF output has `/system/bin/linker64` and direct `NEEDED` entries
`libc.so`, `libm.so`, `libdl.so`; those names do not identify the runtime providers'
versions, terms or redistribution rights. The map was read in verified pages but
not fully assembled/re-hashed; the archive files themselves have no hashes in this
publication. `libc++abi.a` is not asserted selected without an exact map row.

The new probe implementation emits `llama-simple.map.archives.json`, containing
the exact hash/size of every unique archive referenced in the map and its listed
member names. That capture remains pending exact CI. NDK `28.2.13676358` r28c is the selected
toolchain, but its actual static C++ archive identity, complete applicable license
terms/notices and delivery path have not been established. Prior official Android
license-source fetches were refused; do not infer NDK runtime terms from the
compiler version or root llama.cpp MIT. Complete platform-provider/runtime review
and a user-accessible notice action remain required before any app adoption. This
is x86_64 emulator evidence only; it does not establish ARM, physical-device or
system-image/OEM runtime behavior.

### Windows runtime and delivery gate

The exact Windows x64 probe in publication
`e4db5049dc6cbd79ce8210b77d511b3de216fb31ba989746c022321abc792e7` / published
SHA `e443153fffa469e437b470899c2038cd18b76a68` passed job `128452818470`.
Its `configure.log` (SHA-256
`9db6ad2ff896d00f57f807889cbd9c0ebbb84820be8c3036c2173716f23b30a1`) records
Visual Studio 18 / Enterprise 2026, MSVC `19.51.36260.0` and toolset
`14.51.36231`. Its `linkage.log` (SHA-256
`2cfe734a0a21ba318a611074ad37e557c1cb7d20d91ea8ae33c22b42ef938e45`) reports
COFF Dumper `14.29.30159.0` and x64 PE direct imports `KERNEL32.dll`,
`ADVAPI32.dll`, `MSVCP140.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll`, and
`api-ms-win-crt-` contracts for runtime, stdio, locale, convert, string, heap,
math, environment and utility. This is **dynamic** CRT linkage despite static
engine libraries. The import record does not identify the actual runtime DLL
paths, provider versions or hashes; the older dumper version is not runtime
identity evidence.

Microsoft's [Visual Studio 2026 REDIST
list](https://learn.microsoft.com/en-us/visualstudio/releases/2026/redistribution)
is the edition-specific online list referenced by Visual Studio Enterprise,
Professional, Community and Build Tools terms. It permits unmodified listed files
for a validly licensed copy, subject to those terms; its Visual C++ section names
the `Microsoft_VC145_CRT_[arch].msm` family and files under `VC\redist` (except
the excluded debug folders), and limits distribution of the runtime package and
individual files to licensed Visual Studio users. This is a possible route, not
permission established for this runner: the build artifact does not identify the
provider binaries or their hashes, and the applicable runner license terms are
not captured. Page retrieved 2026-11-07: receipt
`3b2a6113930dd4413738cd98383e577b9462473fea498d26fa8ea9bd7b7a7ef6`, SHA-256
`0e91cdda4d1d224221b1559e72e70677d304859c296ceb2463ceb222850eb054`.

KERNEL32/ADVAPI32 and UCRT contracts still require supported-Windows provider
and terms review; VC C++/vcruntime DLLs are **not assumed OS-provided**. For any
product runtime, capture the exact provider binary identities, then match them to
the selected installation's REDIST list and terms. Record provider, linkage,
redistribution and approval under policy. Do not ship runner DLLs or infer
redistribution permission from dumpbin.

Before adoption: close generated/header and selected-term gaps above, then ship
complete selected notices alongside the engine and expose them through the app's
existing license action (including all intrinsic attributions and applicable
data/runtime notices). CI logs or this audit are not user-accessible notice
delivery. No engine notices/assets are added to the app before selection is
approved. Product brokering/session-only consent, model/language reporting,
cancellation/resource failures, verified no-network/no-text-persistence behavior
and Flutter integration remain separate gates. The watchdog is not cancellation
evidence. Draft persistence retains its existing security/recovery gates.
