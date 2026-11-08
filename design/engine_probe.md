# Native-engine feasibility probe

This is **developer tooling only**, not product inference or distribution
approval. The latest exact native-probe publication is
`e4627bd337029fec04f4af39799566a7b0a7469dd68bad57d6a5c624e9469d16` / SHA
`5752035ff2adb68a51b78c020f1d52ec7d5be1ba` (code digest
`3279e24928491426c61a0b1302ac17e993677965d74e7bef4ebf2c96ebd48417`). Its
receipt-bound status (`vcs-read/fdd6c0cbcb9b423ab5f26928b9b85175`) reports the
Android API 35 x86_64 and Windows x64 native-probe checks successful in run
`42515261841` (jobs `128836792623` and `128836792802`). These are feasibility
observations only, not source, license, redistribution, adoption, or physical-
device approval.

The later full CI publication `523041581cee6bae793cc1ec6be19f5debbdad74b74a0078cbb2a99c49d8b823`
/ SHA `38abcdd872705ec2471008098954abd6c85900a7` (run `42511182547`; status
`vcs-read/715ab52343a140a88ea34f3b46058920`) passed Flutter, Design, and Windows
checks but failed Android and Apple. Android instrumentation completed 20/20
tests, then `emulator-5554` went offline and the emulator segfaulted; the
profile-enabled EXIT trap's unbounded `adb logcat -d` waited for a device until
the 15-minute step timeout (`vcs-read/da49a97da804433f8cffbfe98da192a8`,
`vcs-read/61ec684a2b6f40d7be81760512a14098`). Commit `f325740` bounds only that
failure-only diagnostic capture; its exact Android CI is pending, and the
emulator segfault itself remains unexplained. The Apple test reached one
window-coordinate gesture, then reported source-language, source-text,
scrollViews, and target absent and failed at `NativeExportPanelUITests.swift:76`
before field entry or native save-panel presentation
(`vcs-read/e04aec26a5544d0882844dab0d036c87`). Save-panel, cancellation, and
draft-preservation behavior therefore remain unestablished; assertions and
deadlines were not weakened.

The exact Android pinned-NDK line-table report `ndk-member-debug.json` is
307,893 bytes, SHA-256
`b638280b8a8fbfe2bd732715e0c7b69dd6dcfab56fc2ebff99481fbba3226e07`
(`vcs-read/74a16fa950be48d799e16e06a564b6c9`). Its recorded archive-manifest
hash `8efc215b9079c3f77ec0583aa0138885f5d95b9d8657f9ea14bc74ecb044efb9`
matches the 5,417-byte link-map-bound manifest
(`vcs-read/ce873ce82b894b34a72b33b0122b2c56`), which names all 26 selected
`libc++_static.a` members. The report records 26 compile units, 26 line tables
and 1,506 file entries, but zero MD5 checksums. Its first member record names
`libcxx/src/algorithm.cpp` as a component-relative DWARF path; such paths are
source-location clues, not byte identity, and no candidate-byte comparison is
possible. The exact NDK patch-source manifest is 1,526 bytes, SHA-256
`d8dc351b4d2a681fa16997a47c02b01f3921970c62146aa3c776b1dd048ef0b1`
(`vcs-read/b6c42f82da224c018d25e4f05414d175`): it names four patch blobs at
`llvm_android` revision `e727bfb014bd436f581a66a450c939a6983a1fc3` and records
hashes, sizes and Git blob IDs, not raw patches. Bounded experiments decoded
Gitiles responses for all four exact-revision blobs and matched their byte
counts and SHA-256 values to the manifest; no decoded patch files were
retained. The observed non-test diff targets are:

| Patch | Bytes; SHA-256 | Non-test changed paths | Experiment |
| --- | --- | --- | --- |
| `move-cxa-demangle-into-libcxxdemangle.patch` | 3,857; `6a8879953b2133491d4bc6be97332d4d031b837e0175227969f4ef7f7d6ef8b9` | `libcxxabi/CMakeLists.txt`, `libcxxabi/src/CMakeLists.txt` | `experiments/e5793796d8e440c398cb2a3e6210cef4` |
| `9a2fd97d391caf1060e303f636d7113501788d2f-r530567.patch` | 174,905; `9b0a015f44a91d6ed83eb9ba4b0303f0e634daa8874199eb76d74f7d61dba7b3` | `llvm/lib/Transforms/Instrumentation/HWAddressSanitizer.cpp` | `experiments/862ec89446ba4171acffa45aad11455b` |
| `b433076fcbacba8a3b91446390bbea5843322bcd-v2.patch` | 18,250; `2f6b8beec77bfb2bff02b6cf341ff31ec424834aa28c23f30ce18bb12945d8eb` | `clang/lib/CodeGen/CGDecl.cpp` | `experiments/97f297c42c93471bacd504eed6af32bf` |
| `e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch` | 15,251; `4ff1cd2a122ecafc3d8920386bc3387b22c9b01e541931f9096b0f3d1047849d` | `libcxx/include/regex` | `experiments/e34b5a63a6c9455ebd58426e5909a5fe` |

The exact selected-input artifact page for SHA `c9dd460d9392485594a5fa6b0a8b92ae6d66da08`
records `sysroot/usr/include/c++/v1/regex` with SHA-256
`2ea7d95853a15ef16925668750ccdface9deead18c79fb3e8064447ff326d982`
(`vcs-read/92c4b4eeddd64179a6da1b12793ce79f`); its selected archive manifest
also names `regex.cpp.o`. The newer line-table report's exact member record gives
`regex.cpp.o` SHA-256
`c1f4771dcb758744d3a5add17084102095354b0efb685d98f4eb006c1c7b5c67`, size
127,056 bytes, compile-unit path `libcxx/src/regex.cpp`, and a line-table entry
named `regex` with `relative-name` state and no MD5 (`vcs-read/a04ccc41ffbd4a9bbca03a5c43f70ff2`,
`vcs-read/afa363a4859748e9b6fcef46830fe5b2`,
`vcs-read/dcfcff547ed0405d8094872bf02382a9`). These records strengthen the
member/source-path and header-basename overlap only: they do not map that
relative line-table name to the full compiler-read header path or compare the
header bytes to the object. This is not proof that the installed header matches
an upstream patch postimage or that the patch was applied. The pinned-source
comparisons below retain distinct base, patch-commit and installed-input hashes.

The archive manifest names `cxa_demangle.cpp.o` and `regex.cpp.o`; the
source-info/compiler-read comparison below also identifies the regex header as
a selected input. These are candidate overlaps only: the CMake patch's
configured effect, installed patch postimages and patch application to the
captured NDK remain unproven. The other two patches alter Clang/LLVM code
that may affect generated objects despite not targeting an engine runtime
member. Neither path comparison establishes member bytes, surviving code,
notice applicability or redistribution authorization. The exact NDK terms
manifest is 2,735 bytes, SHA-256
`6a92040adc41f19068e0e621c0e0b17ff00f6d55d77423312cb7edc61740bff8`
(`vcs-read/a030cba6c6e64ba286d505d325278ffb`); it identifies broad r28c
package/toolchain/host notices, not their applicability to selected archive
members. The earlier exact patch-effect and terms analysis below remains
bounded: neither these manifests, DWARF paths, member hashes nor successful
probes establish installed source identity, patch application, surviving code,
applicable notice obligations, redistribution authorization or device behavior.
The capture invokes the pinned NDK `llvm-dwarfdump --debug-line` and retains
only compact per-member line-table metadata: version, sanitized source
path/state, and MD5 when present. Missing MD5 remains explicitly unavailable;
it is neither synthesized nor passed to source comparison. Line output has a
workflow-configured 32 MiB budget, with aggregate tool output bounded by the
existing 64 MiB budget plus that configured addition. Malformed or over-budget
output fails capture. Extracted objects and raw DWARF/line-table output are
temporary and deleted. A DWARF MD5 is debug metadata, not an integrity proof or
evidence of build/patch identity, surviving code, licensing, rights or device
behavior. The exact Android API 35 x86_64 probe publication
`e4627bd337029fec04f4af39799566a7b0a7469dd68bad57d6a5c624e9469d16` / SHA
`5752035ff2adb68a51b78c020f1d52ec7d5be1ba` additionally captured only
`libc++abi.a(cxa_demangle.cpp.o)` into
`ndk-member-debug/libcxxabi-demangler.json`. The sanitized report is 14,944
bytes (SHA-256
`7dd2e92b9d477770e78f178efc00036c64154ddfabcdceedbf1cb3126ad1c17`, pages
`vcs-read/1ee9e785319f47019eedc06df22a2b4b` and
`vcs-read/cd540580aa0b42edbb2f1de49ce63f58`). Its `archive_manifest_sha256`
matches the exact 5,417-byte selected-member manifest (SHA-256
`2cafd537db2a905e0cb4a746ae365a38c0f4c74aaf5e4bf45ff3772e140c27fc`,
`vcs-read/75b1787d57d04335946967b739a6eed7`), where the `libc++abi.a`
archive (2,792,306 bytes, SHA-256
`11ff6729a881f3d1a2e72c2a9c4bd2c096e02c5dfb3858d942405e0514b7b95c`) lists
`cxa_demangle.cpp.o` once. The report binds the same map SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd` and size
4,660,773 recorded by its 96-byte sidecar (`vcs-read/ba0e778911104ed9aa05e3f92018ac4c`).
It records the extracted member's in-memory SHA-256
`8807afd3edd4b1dd569cefe42bfc7596060fdd7313a46003632db2d62a492930` and size
2,158,776; one compile unit names component-relative
`libcxxabi/src/cxa_demangle.cpp` (producer `clang version 19.0.1`), and one
line table contains 69 file entries, with zero MD5 checksums. The report retains
only sanitized component-relative or relative-name paths, including
`libcxxabi/src/cxa_demangle.cpp` and
`libcxxabi/src/demangle/ItaniumDemangle.h`; absolute paths are not retained.
Tool output (8,538,151 bytes), line-table output (1,212,242 bytes), and member
bytes remain under the configured 16 MiB, 8 MiB, and 8 MiB limits respectively;
the elapsed-time limit is 30 seconds. The CI check passed in run `42515261841`,
job `128836792623` (`vcs-read/fdd6c0cbcb9b423ab5f26928b9b85175`). The reduced report and bounded capture summary are retained; temporary objects
and raw tool output are deleted.
This narrows provenance only: it does not establish source-byte identity,
patch application, surviving linked sections, notice applicability, licensing,
redistribution rights, device behavior, or adoption.

The separate Android smoke log reports emulator-only loader rejection and one
`Bonjour.` sample (`vcs-read/ebd8643b34544a958045fe6b1802c8b0`), not translation
quality or physical-device coverage. The exact Windows provider capture remains
one CI-runner observation, not redistribution authorization. The operator
confirms no Visual Studio license entitlement or agreement, no basis to
redistribute Microsoft VC++ runtime DLLs, and no Windows runtime distribution
path is chosen (`operator/kotoha/a-e1ceeae8-r1-1794137634`). Engine adoption
remains disabled.

The detailed archive/member inventory below is historical evidence from exact
publication `20ab85fc177a5dfa821f148cda27dac71473b5e51b486c4e87f9b887f67d9785`
/ SHA `59cdc16f38ab3d18cf5a91aeff383b168e7792c4`. The newer exact archive
manifest and DWARF line-table report are summarized above; this historical
inventory remains evidence for the bounded source-list and terms analysis, not a
substitute for the current report.

The earlier `android-api35-x86_64-engine-probe` artifact includes the map
and a link-map-bound archive manifest. The complete manifest is
5,417 bytes, with locally verified artifact SHA-256
`77989f7a3172bedbd86b23a6f7fa2f5ab4dccef696ebe2657cf1dcad13df09fd`
(`vcs-read/a0174cd30958445f915a379412d958c5`). Its declared map size/hash
(4,660,773 bytes; SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`) matches
the exact publication's 96-byte sidecar (`vcs-read/35b02c94bd924b7bb8025017857f67e0`).
This confirms internal manifest/sidecar agreement, not an independent re-hash
of the 4.66 MB raw map, which has not been fully assembled here.

The manifest records the following archive files and exact build hashes:

| Archive | Bytes | SHA-256 |
| --- | ---: | --- |
| `libggml-base.a` | 10,016,748 | `b3012c80945ae3880599bddbd5a70a0f239d76752b16cb06f34e37aab7ba94bf` |
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
branch. The exact Android link-map manifest records archive-level hashes and
selected member names, not per-member hashes. Separate bounded DWARF reports
now hash 26 `libc++_static.a` objects and the single selected
`libc++abi.a(cxa_demangle.cpp.o)`; the other 14 selected libc++abi objects have
no per-member hash or DWARF capture. A member-name or DWARF-path match alone
does not prove source-byte identity, patch application, or surviving linked
sections.

For the demangler candidate, the exact manifest lists `cxa_demangle.cpp.o` in
`libc++abi.a` (archive SHA-256
`11ff6729a881f3d1a2e72c2a9c4bd2c096e02c5dfb3858d942405e0514b7b95c`, size
2,792,306 bytes; `vcs-read/efd03137e3cc49a78bfbe6462a2d5769`). The immutable
compiler-reported LLVM source candidate `libcxxabi/src/cxa_demangle.cpp` has
SHA-256
`75d8f3ff6fb628bc57508f4c95cc8534e228c085e4e5167c593ea1cf4f703e97`
(`mizu_fetch/de3ddede7537ac4215831d91a33be537c549f63e70d6d341ab11c00e5a67743c`);
its reviewed header declares `Apache-2.0 WITH LLVM-exception`. This is an
upstream candidate source read, not a source-read record for the prebuilt NDK
object. The separate exact report now records the archive-member byte digest
and a component-relative DWARF path for this one selected object; it still does
not compare the object with this candidate source. The other 14 libc++abi
members remain uncaptured. The separate demangler patch changes libc++abi CMake
files, while the map-bound manifest still lists this member in `libc++abi.a`;
neither fact identifies the configured build-graph effect or proves patch
application. Source-byte identity, surviving sections, exact notice
applicability, and redistribution rights remain unresolved.

The full upstream terms were read at that same revision, including each
component's own `LICENSE.TXT` (SHA-256 values are whole-file digests):

| Upstream record | SHA-256 |
| --- | --- |
| LLVM `LICENSE.TXT` | `8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee` |
| `compiler-rt/LICENSE.TXT` | `1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d` |
| `libunwind/LICENSE.TXT` | `b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d` |
| `libcxx/LICENSE.TXT` | `539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b` |
| `libcxxabi/LICENSE.TXT` | `e2b35be49f7284a45b7baca8fc7b3ab7440e7902392b2528a457816b5bb2a15c` |

The four component `LICENSE.TXT` files above explicitly state that their
respective runtime libraries are dual licensed under the University of
Illinois/NCSA and MIT licenses, and include both full texts (compiler-rt
`mizu_fetch/3d2a8f7ac3e59993aa44cf5e441d3d15f07d692e2042c1ab476bf757198c415d`,
libunwind `mizu_fetch/f68c9e49188a33a5c3f63512d5784b3c49eb13842bb70464313b2d99800ac706`,
libc++ `mizu_fetch/0aaca30739202814bc07c0236dbc31724d7f620cf0439c0ca3695811701c28a0`,
and libc++abi
`mizu_fetch/8661c9a74fab06b41dfff8e53f3f5d1b3d04fd6ab2d6675398eeea723177dfea`).
LLVM's `DeveloperPolicy.rst` at the same revision (SHA-256
`8f0134f982af6a56c50cbaaa7a806507c2cd9c372a8a12629556fdd4372a512c`,
`mizu_fetch/712c7445714285d00a776951b5a062e280c493a1273754a532ca767954006155`)
states that relicensing is incomplete and contributions are under both the
new license and legacy scheme. The candidate source files' Apache-2.0 WITH
LLVM-exception SPDX headers therefore do not by themselves establish an
Apache-only term set. These upstream source candidates have permissive
license alternatives; this does not identify the selected NDK object bytes or
show that vendor patches and third-party inputs introduce no additional terms.
The Apache exception specifically relaxes sections 4(a), 4(b), and 4(d) for
embedded object-form portions; the legacy NCSA binary-notice condition and the
MIT copyright/permission notice remain alternative obligations whose use and
applicable source subset have not been selected. Exact package-record capture,
member-to-input/section closure, and a reviewed user-facing notice payload are
still required. No product adoption or notice set is approved by this partial
result.

#### Selected libc++ member DWARF (bounded exact-CI capture)

The Android probe's capture rechecks the exact link-map and `libc++_static.a`
hashes, enumerates selected members, hashes each extracted object in memory,
and runs the pinned NDK `llvm-dwarfdump --debug-info` on a temporarily staged
object. The NDK r28c release identifies version `28.2.13676358` and LLVM
`clang-r530567e`; its Linux x86_64 prebuilt tool directory contains
`llvm-dwarfdump` (Gitiles listing receipt
`mizu_fetch/d17b244233de0cf5d7ddfcca89f4b418a3d8a168fcb7e8a2577ae5730e9dddc1`,
entry blob `1132c55545f1a580a3ad3118adcfe55b53adfaa7`). The LLVM 19.1.7
command guide documents `--debug-info` as the `.debug_info` section selector
(`mizu_fetch/29e5c5536faefdcca094d298adaedd86638a91324438742214054f7ef5b082e2`,
SHA-256 `4b6cd335bdaaf9e05f2af1229643d8f3f8ac046631ac65d81bfb0d01789b6d89`).
The corrected command completed on publication
`0f9b59bf92eca25d42bce26015e3254228419da6853def4fe4a7b360f32f19f0` / SHA
`678896ce4c8d9b73ba56d897e0d575e36e67ea7e`. Its exact artifact
`ndk-member-debug/ndk-member-debug.json` is 12,917 bytes, SHA-256
`74e5ef31fd187059f6ee51b293260d0a7c8c856076c2d69d649a6fbca3dd0a5b`
(`vcs-read/e60540330e3248ed9f3ccdfce43e542c`); the capture log confirms 26
selected members and 26 with compile units
(`vcs-read/3807234c23034c0ca3b4f4072427a90c`). The report binds
`libc++_static.a` (14,336,094 bytes, SHA-256
`893dc67b8c7eef4000af6e582421a14ea7e5fdec97249496005fc3a48f7d7099`) and the
link map (4,660,773 bytes, SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`) to the
archive manifest. The manifest is 5,417 bytes, SHA-256
`6be9cfbb85dffc2f419d832fc03f280775a929b62fb0ee3d3cd36ebc48bc2474`
(`vcs-read/18af8b776b514d96a7564c86f094ec89`), matching the report's recorded
manifest hash; its 96-byte map sidecar has SHA-256
`4f1b583fec32579adb492d8cc7bc0769ef46b4fbcc3f1856ab78efbafe558ac3`
(`vcs-read/f97488d99da94752a2e304de9bdc07ba`) and agrees on the map hash.
All 26 records contain a compile unit with a component-relative `libcxx/src/...`
DWARF path and reduced producer version `clang version 19.0.1`; recorded DWARF
output totals 65,517,398 bytes and combined tool output totals 65,518,293 bytes.
The capture retains member hashes and reduced metadata, not raw archive-member objects or absolute `DW_AT_comp_dir` values.

Temporary objects are removed; configured limits bound member count, extracted
bytes, combined tool output and elapsed time. Tool stderr is drained under the
same output budget; only a byte-capped diagnostic remains after C0/C1-control
and path redaction, while successful stderr is discarded. Synthetic tests cover
indexed DWARF strings, the exact `--debug-info` argument, path redaction,
archive/map binding, duplicate members, bounds, timeout and bounded failure
context. An earlier run failed because `llvm-readelf` rejected the unsupported
GNU-style `--debug-dump=info` option
(`vcs-read/3a7f8344b4aa49efa21d9cb6931c835f`); that tool error was corrected and
the exact run above succeeded.

This bounded result shows only that the selected archive-member objects expose
DWARF compile-unit records with those path clues. It cannot establish exact
source bytes, patch identity, surviving linked sections, applicable notices,
licensing or redistribution rights. The separate emulator failure gives no
Android runtime observation; adoption remains disabled.

#### Source-list candidate comparisons at the NDK-reported LLVM base

A separate bounded comparison used the four component CMake source lists at
source-info base `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` (not the
compiler-reported LLVM commit `97a699bf4812a18fb657c2779f5296a4ab2694d2`).
Each of the 47 selected archive-member basenames has exactly one matching
source-list path at that base. This is a unique filename candidate, not proof
that the NDK build selected that CMake target or that an archive member was
compiled from those exact source bytes.

| Archive | Candidate matches | CMake source-list SHA-256 | Bounded comparison |
| --- | ---: | --- | --- |
| compiler-rt builtins | 1/1 | `b62993a0dbad605272194914305ca62ade86e47e49d6ba63b0221609270a4ea0` | `mizu_fetch/27118ae48174bd1058e297d506836d2d7ee6b95c958ae57339bbc67833d3ce69`; `experiments/66281496c5b742d8af5e9d67b99b0746` |
| libunwind | 5/5 | `a806c64195fc9e8bf88a8e3cdfb7701ac354e841873273651cc7f3a09241aa97` | `mizu_fetch/d7b089045a6bbd9801543b8c0227decfb946e8872169c5834cf6b314d73d81bf`; `experiments/388dbc7e3f48416d86dad080e2ee37db` |
| libc++ | 26/26 | `b62aa4a6c2cb2d95cb48872cc4a4fb10568d2b99531b345e8ce499993bfabf87` | `mizu_fetch/7e3089ec7654af05b712824a2f7e76f7c59af5322a4e5b1a6ca14883a0b9b0f1`; `experiments/66b474fa51a34fa599f69bded2dc4133` |
| libc++abi | 15/15 | `c6192d1454baad9a0c3f3ef4e88320e845628c76c8100fd11eaf5327e28fb29d` | `mizu_fetch/428f48da215b3a3b06893bdf01edb975eae5c5ae86d0975e1abfcfa90caba0de`; `experiments/aef9f40ff5384d568ffc6032fe704a13` |

The per-member outputs found exactly one CMake filename candidate for every
member (no multi-candidate basename hits). Candidate paths below are relative
to each component source root:

```text
compiler-rt:
  emutls.c.o -> emutls.c
libunwind:
  UnwindLevel1-gcc-ext.c.o -> UnwindLevel1-gcc-ext.c
  UnwindLevel1.c.o -> UnwindLevel1.c
  UnwindRegistersRestore.S.o -> UnwindRegistersRestore.S
  UnwindRegistersSave.S.o -> UnwindRegistersSave.S
  libunwind.cpp.o -> libunwind.cpp
libc++:
  algorithm.cpp.o -> algorithm.cpp
  call_once.cpp.o -> call_once.cpp
  chrono.cpp.o -> chrono.cpp
  condition_variable.cpp.o -> condition_variable.cpp
  condition_variable_destructor.cpp.o -> condition_variable_destructor.cpp
  directory_iterator.cpp.o -> filesystem/directory_iterator.cpp
  error_category.cpp.o -> error_category.cpp
  exception.cpp.o -> exception.cpp
  filesystem_error.cpp.o -> filesystem/filesystem_error.cpp
  future.cpp.o -> future.cpp
  hash.cpp.o -> hash.cpp
  ios.cpp.o -> ios.cpp
  ios.instantiations.cpp.o -> ios.instantiations.cpp
  locale.cpp.o -> locale.cpp
  memory.cpp.o -> memory.cpp
  mutex.cpp.o -> mutex.cpp
  mutex_destructor.cpp.o -> mutex_destructor.cpp
  new_helpers.cpp.o -> new_helpers.cpp
  operations.cpp.o -> filesystem/operations.cpp
  path.cpp.o -> filesystem/path.cpp
  random.cpp.o -> random.cpp
  regex.cpp.o -> regex.cpp
  stdexcept.cpp.o -> stdexcept.cpp
  string.cpp.o -> string.cpp
  system_error.cpp.o -> system_error.cpp
  thread.cpp.o -> thread.cpp
libc++abi:
  abort_message.cpp.o -> abort_message.cpp
  cxa_default_handlers.cpp.o -> cxa_default_handlers.cpp
  cxa_demangle.cpp.o -> cxa_demangle.cpp
  cxa_exception.cpp.o -> cxa_exception.cpp
  cxa_exception_storage.cpp.o -> cxa_exception_storage.cpp
  cxa_guard.cpp.o -> cxa_guard.cpp
  cxa_handlers.cpp.o -> cxa_handlers.cpp
  cxa_personality.cpp.o -> cxa_personality.cpp
  cxa_virtual.cpp.o -> cxa_virtual.cpp
  fallback_malloc.cpp.o -> fallback_malloc.cpp
  private_typeinfo.cpp.o -> private_typeinfo.cpp
  stdlib_exception.cpp.o -> stdlib_exception.cpp
  stdlib_new_delete.cpp.o -> stdlib_new_delete.cpp
  stdlib_stdexcept.cpp.o -> stdlib_stdexcept.cpp
  stdlib_typeinfo.cpp.o -> stdlib_typeinfo.cpp
```

Representative unique candidates are `emutls.c.o` →
`compiler-rt/lib/builtins/emutls.c`, `UnwindLevel1.c.o` →
`libunwind/src/UnwindLevel1.c`, `regex.cpp.o` → `libcxx/src/regex.cpp`, and
`cxa_exception.cpp.o` → `libcxxabi/src/cxa_exception.cpp`. Each of these four
pinned base source files carries `SPDX-License-Identifier: Apache-2.0 WITH
LLVM-exception` (source SHA-256 respectively
`a4437f3e329a0835adbc7df38e36df12f358d05c073b11813c409f849c2345d2`,
`60713346aa7712b5292e4cc2a05c0d3400296ebe76d7c25d256ee46a7dc2a174`,
`87ce61e6756d2a07a5794ed44df844a4c3e02c5cf91cfcf0d3c6626f7e846643`, and
`eb6c7923d2e8ddc9347410b95981c6b800ccbe251d34057e5fca9069bf99ecf2`). These
are representative source-file checks, not a file-by-file license audit of all
47 candidates. The component `LICENSE.TXT` files at this base (whole-file
SHA-256 values in the preceding table) explicitly describe their libraries as
dual licensed under Apache-2.0 WITH LLVM-exception and legacy UIUC/NCSA and MIT
options, consistent with the project policy summarized above. This component-
level source licensing does not establish the identity of any selected object
or third-party code and notice obligations in linked sections.

#### Exact libc++ DWARF-path source candidates at the compiler revision

The exact Android report lists 26 `libcxx/src/...` compile-unit paths for the
26 selected `libc++_static.a` members (`vcs-read/04388ed5a7fe4dfa93bd203180c33903`
and continuation `vcs-read/96480eb28e004c5d92f37385d74e50e9`; report SHA-256
`74e5ef31fd187059f6ee51b293260d0a7c8c856076c2d69d649a6fbca3dd0a5b`). Each
path has a unique filename candidate in the source-list comparison above. I
fetched each candidate from the compiler-reported immutable LLVM repository
commit `97a699bf4812a18fb657c2779f5296a4ab2694d2` and reviewed its first-page
file header. All 26 headers state
`SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception`; whole-source hashes
and exact fetch receipts are:

| Candidate source path | SHA-256 | Exact source receipt |
| --- | --- | --- |
| `libcxx/src/algorithm.cpp` | `5965a2ccb91e21d3dbeaa659299e43566a8128d9648743395d1dd14d592ec8a7` | `mizu_fetch/0c632bed3980a362212ec8b928327fea92c12c8bd09a08c6a3a73438b6cfc8be` |
| `libcxx/src/call_once.cpp` | `b01877158f1ba03d107d0e01307bfcd7a26613ccb9f605ca0eb741a6aad800b3` | `mizu_fetch/f8f75ff0cf5896093a14709d98db8b957db52cb706c0b781b4f7b36cc0f50fd9` |
| `libcxx/src/chrono.cpp` | `b4f61b94430171b4d7c3f8f8fa8dbf50b82c8ba8d44d291f06b7bc6cbc25fe13` | `mizu_fetch/0505348618872b7766fb2d4e4991c7e8602792e184a5b6849fbf809261f4a0d1` |
| `libcxx/src/condition_variable.cpp` | `2c2daa42f90592fcd085bec73a99b3db1d4dc0f228622401a25b630f4a2cf57d` | `mizu_fetch/9ea0b3cb0d4dc8382edf884b8a4834e36283fc481727e92c9e41b1f4e0dba207` |
| `libcxx/src/condition_variable_destructor.cpp` | `5ffc3496ccaafcc01a57c854a6e8e9fc15f2ed18008b8a96382603f674f79e08` | `mizu_fetch/d12315537fa0fe9556b9715a4dba72b7cbc0391a504afdcfe975c72f02331faf` |
| `libcxx/src/filesystem/directory_iterator.cpp` | `c6ae3cbb77ca3a6afe0117ce43c87f86ec9855f5dde0e88e3d3b36419dfebc52` | `mizu_fetch/1a81f770bc875beedea96353e16325fa45b54c21c7249276558e684046c3385e` |
| `libcxx/src/error_category.cpp` | `236d878ed42578f1599dae12d0b7b5f44acc146f9f5af2b92f29c5b54008193a` | `mizu_fetch/85222634506a843028e832a5d1e1554338ca511d91b3802677cd95f84894a037` |
| `libcxx/src/exception.cpp` | `a7b7792329befed2fa15e31232329340ae36f4380c76348f895b9ad0e7975e66` | `mizu_fetch/080211102f6696b2d9a34a6816423ae9d23107b9abd64f2eac226bfafea85c94` |
| `libcxx/src/filesystem/filesystem_error.cpp` | `3e33692dbdba317553144222703db6e701138bd9d0148bc421ecf27bcd524381` | `mizu_fetch/1866de76e3a6a49a4bff15e89ac29883ab9dc2c76a95d2535a1a62c359af36ef` |
| `libcxx/src/future.cpp` | `81d9672773eee216b5150cb6004c54a04c30d22c71a3402a25bb9eac1551f8e9` | `mizu_fetch/0339d72c4350693aa7b02c0f48dc807694c1d6544393a936189b66d71e074c83` |
| `libcxx/src/hash.cpp` | `63890063c9f5b28bdfe5168bc2777ccc19586d27a05465f25dfa04ef51e1a6e4` | `mizu_fetch/58c4401aa13597ad4e402cde4edf6669bcde5469925a64a33e531c33f22ea676` |
| `libcxx/src/ios.cpp` | `88be7f1eaf4fdf7d2647de4ed0bceb519bdc41768cf919e28a20c314c8d73795` | `mizu_fetch/a35fd764f33ad43796c4441a17d9636f4d6e5ccc8d6f17b50669bb2110a3caf3` |
| `libcxx/src/ios.instantiations.cpp` | `995a37e2e986af415dd95c5406daa73a7c4f847b16ecd06bd5c621e059096427` | `mizu_fetch/bb6198e44b259880d74861e414eebba89e3b556a9b64933130e754ea72b87e8d` |
| `libcxx/src/locale.cpp` | `fca6ab86c3b16b3660d41ba38360efb3fa5e9f4cbc42186f19556431716d1457` | `mizu_fetch/6cf6c98b138a40f43c0e6fe304c1b69f0069187702258bf4c7fdd1572084e93b` |
| `libcxx/src/memory.cpp` | `f5dd019603cdbe6a03c2caabad2a85a2ff6782f276f5c69ab1c523ab40fa1551` | `mizu_fetch/6cba385804833a48ef619c3651edb1a40747b4ef82ac20f62f9c765161a9ea76` |
| `libcxx/src/mutex.cpp` | `f562a2cda5b2fff8c592e94f225af080916a547cd4c144cba959e8e4e1326fbe` | `mizu_fetch/175922e2be7ad74e66ddf58da4eba0c1837292b978e57d88741ea0f1059c5798` |
| `libcxx/src/mutex_destructor.cpp` | `0940ca95f81440e72ca9919b284b9a1a837b1700e08dbe90d61139240ac57cce` | `mizu_fetch/a1bb6ba1c8497316c3beef22d63801935b49abf9552afa4c4f494f2e6b7dfb61` |
| `libcxx/src/new_helpers.cpp` | `745bd190f8e82539b9896aef7f9a6a32948f2c5313bcbdc836a5f45b518a1399` | `mizu_fetch/4c27b93e6fa06ae8c44dd0408ebf53d64e745f3d43d2aecd07f2828bc25af9ec` |
| `libcxx/src/filesystem/operations.cpp` | `fc33c72864afb24384d76bd0fbed9cb8ea68a6a3218adabe634c94817f326645` | `mizu_fetch/fbdfc762f15c78bb3903dd36d37f725f72bc684f86c6f4f14413527acd656efe` |
| `libcxx/src/filesystem/path.cpp` | `17b89bcf9dd5973ed774fb8559c1f9b917f6b4d659650b482e1bd4f52744e200` | `mizu_fetch/805d34c56cd9910eef68ebcb03e04f9e922880b8ecf962a52d4928709a466f92` |
| `libcxx/src/random.cpp` | `c288b5d9d4cdf253bd867a5572c7aca9a1c93398680b915518f4ae111d82bfed` | `mizu_fetch/4dc684630437aec6c1c0bef0d741776099d61ec8dbc937fa934702c9cdea1447` |
| `libcxx/src/regex.cpp` | `87ce61e6756d2a07a5794ed44df844a4c3e02c5cf91cfcf0d3c6626f7e846643` | `mizu_fetch/8930d5b57de897eaad62e8e4915e648e68715d797b491ff2180857679d0d1a4d` |
| `libcxx/src/stdexcept.cpp` | `3d4cdfcf736eb5cd67d0cb1c406caf8c7b831f7bfd80f13fcb19cb5df18fdaee` | `mizu_fetch/0f115f57dce17053f7681c77e92b5bb74a8fd9cefb384a96e1b269c13f425853` |
| `libcxx/src/string.cpp` | `7fc174817784c4ebd597b5cb494a62c76098eb40aee0949ce22b8233e9476a01` | `mizu_fetch/bb992a8e198cd1cb6543fd6f5d41408319ad5b5679c96b11c043f9617c1350f6` |
| `libcxx/src/system_error.cpp` | `fb570270dcc6749dd2d5bdd078d7b0f0576ffbc0afb2d2e6862a691f53f1c8ff` | `mizu_fetch/efe91ddc59bfe8b60b795419a0282b28cf8222a465f59bb20ad3cfcaaed63e0e` |
| `libcxx/src/thread.cpp` | `74acf68a6c8eb1701e166fc48b4c40a39cf09d29af95bee63d6bbd56401f6a45` | `mizu_fetch/de1b685d3e81b4d1fcf1afcb666abb33a32d604cb3f3ac453c5337834ec27d72` |

The complete LLVM and libc++ `LICENSE.TXT` files at commit `97a699...` have
SHA-256 `8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee` and
`539dd7aed86e8a4f12cbdd0e6c50c189c7d74847e4fecc64ce2c6ee3a01da38b`,
respectively (`mizu_fetch/6b4820014d0c42cde7e151b2fac81332a262a1853668862f9bec7d53960c0f09`,
`mizu_fetch/d7ae0a769b142de0d9ed9070f71d9e80b3bdaf892579b97f8993e39c8c2c2caf`,
full receipts). They match the component-text digests already recorded at LLVM
base `3b5e7c83...`. The source headers and component license records establish
permissive upstream candidate terms under the Apache-2.0 WITH LLVM-exception
and legacy UIUC/NCSA-or-MIT alternatives described above; no license option or
notice set is selected for an NDK archive member. The file headers classify
these source candidates, not the archive objects. This advances source-term
classification for these 26 candidates only. The DWARF paths and upstream
source hashes do not prove that the NDK archive members came from these files,
identify applied source patches, establish surviving sections, or determine
exact notice applicability or delivery. Headers were reviewed for the SPDX
expression; no full body-level embedded-origin audit is claimed.

#### Remaining compiler-rt, libunwind, and libc++abi source-list candidates

The other 21 unique basename matches from the 47-member source-list comparison
(1 compiler-rt, 5 libunwind, and 15 libc++abi) are candidate paths only; unlike
the libc++ set above, this comparison does not have corresponding DWARF source
paths. I fetched the candidate files at the same immutable compiler-reported
LLVM revision `97a699bf4812a18fb657c2779f5296a4ab2694d2` and checked their first
page. All 21 headers state `SPDX-License-Identifier: Apache-2.0 WITH
LLVM-exception`. The table records whole-source hashes and exact fetch receipts;
these are upstream candidate bytes, not proof of archive-member identity.

| Archive member | Candidate source path | SHA-256 | Exact source receipt |
| --- | --- | --- | --- |
| `emutls.c.o` | `compiler-rt/lib/builtins/emutls.c` | `a4437f3e329a0835adbc7df38e36df12f358d05c073b11813c409f849c2345d2` | `mizu_fetch/b8d4ebfd6919c8abdd5091e4f2943e2f8a75aaab98ce2675d7d9e7c8ba12a25f` |
| `UnwindLevel1-gcc-ext.c.o` | `libunwind/src/UnwindLevel1-gcc-ext.c` | `3bed106de18fec9d1c52cb7bc3d5db89d3225252f3c0312597d159edbbd6e802` | `mizu_fetch/a845025fde7a5c638bf12d2264172fc92e079b5c24d4761e660f6707f0b37f4b` |
| `UnwindLevel1.c.o` | `libunwind/src/UnwindLevel1.c` | `60713346aa7712b5292e4cc2a05c0d3400296ebe76d7c25d256ee46a7dc2a174` | `mizu_fetch/b817673de5b5dffb5d559da5b89927173385ac13e52daa72e7e761f7e60f0184` |
| `UnwindRegistersRestore.S.o` | `libunwind/src/UnwindRegistersRestore.S` | `7c66721db60ae08b776119e0475bb4efe6aeaec79dc0386c8cd35cb4aee268f1` | `mizu_fetch/b5fb3adddcf5045d52c5c9129e8794d232b1be3547f7c0d2b069c238df002ef0` |
| `UnwindRegistersSave.S.o` | `libunwind/src/UnwindRegistersSave.S` | `9c7c51e705f73bb22d8113714a47fe9f1a3b84fe5a9484bb6801578523cabc5d` | `mizu_fetch/fe9c2ba3cd302bce16a4b9a46fae26535102354f2847d626e80a0b73fc8792f1` |
| `libunwind.cpp.o` | `libunwind/src/libunwind.cpp` | `6897d1a337fc38d050b5742f404a623c8988ce9d6a55fe8271c4b7ceee32ef10` | `mizu_fetch/26f2c53c3e3c623523dc21bdf5b5f29e75fe10d68c487a85dfe89404be08cb27` |
| `abort_message.cpp.o` | `libcxxabi/src/abort_message.cpp` | `2891464b7f9273747fe6dd10d9c34e5b07023add80735065965d9f3bfeb8997d` | `mizu_fetch/a582c5c7c9c192e86a45ccde5b5d4fe637415593c98804f900d8cf75a31fa5fd` |
| `cxa_default_handlers.cpp.o` | `libcxxabi/src/cxa_default_handlers.cpp` | `eed7e4752a04198064a8cf15d64495bc854135b8d7bf1b5ec320457f86fe0c8b` | `mizu_fetch/7a35a1faa723569b04b0f50ddfd0a985f29da1fd59685844ac1c59ed69845af5` |
| `cxa_demangle.cpp.o` | `libcxxabi/src/cxa_demangle.cpp` | `75d8f3ff6fb628bc57508f4c95cc8534e228c085e4e5167c593ea1cf4f703e97` | `mizu_fetch/de3ddede7537ac4215831d91a33be537c549f63e70d6d341ab11c00e5a67743c` |
| `cxa_exception.cpp.o` | `libcxxabi/src/cxa_exception.cpp` | `eb6c7923d2e8ddc9347410b95981c6b800ccbe251d34057e5fca9069bf99ecf2` | `mizu_fetch/0edd735ede486316a0053e9e89b3d3295dab576839fa60f1f3c94a034afcccc0` |
| `cxa_exception_storage.cpp.o` | `libcxxabi/src/cxa_exception_storage.cpp` | `320adf288aded3e266bd1b1ef117e714c90d24bc1de607a7c51567ade3f06b9b` | `mizu_fetch/a99a150941474ca1e93f80fbabacdb1680e25e8a257f12791cee9c50b00066f0` |
| `cxa_guard.cpp.o` | `libcxxabi/src/cxa_guard.cpp` | `97dbc2a48acb2233301bd7c11717cda173b23c73e7da64eb1710332c3b19f54d` | `mizu_fetch/7b00eeaa56e0e3f437f5496e91cea30e458c43398f7b722eb77d893ca31f8109` |
| `cxa_handlers.cpp.o` | `libcxxabi/src/cxa_handlers.cpp` | `c95d15e9b6e3f3e3e665a2ca170ebfe87bd323fb498ded9711e32e0633da2892` | `mizu_fetch/e79137a535a9abfc80fc47e9adc0b868f803f931fd79a59ac450267f935e7540` |
| `cxa_personality.cpp.o` | `libcxxabi/src/cxa_personality.cpp` | `57c285728ed943c0168dbbcd244ba5550af673ea7e317c0953eecaa733e7559b` | `mizu_fetch/b2ec27bcf9591ab078a8977dcaed0847422a2262c3a02be78114e3759d393722` |
| `cxa_virtual.cpp.o` | `libcxxabi/src/cxa_virtual.cpp` | `ac1a29d1c9d4fa78d69e209879f61abeb65e1614d1cdd7271d2f386737a4d2a3` | `mizu_fetch/1e7a45d1f98ad1d6c72623ac8cdce736f60342ba0942964a13a73f08d4c4c97e` |
| `fallback_malloc.cpp.o` | `libcxxabi/src/fallback_malloc.cpp` | `b68232eb83588c20e28acf706703a5e9769c63adbeb2c6594ce4c0be5634a011` | `mizu_fetch/125ec3afb533c419425887577c2193b93a2700fef7ba8c7612d034ea071ced28` |
| `private_typeinfo.cpp.o` | `libcxxabi/src/private_typeinfo.cpp` | `55fb71fdd633e1c0f7b4bccba5b947bd03c1498f9cb5f79f162c58efc34342c3` | `mizu_fetch/b2f9fd6335334449e8fa234afc2054fb7be7937ee3b4256aa0fbe15bb81efd06` |
| `stdlib_exception.cpp.o` | `libcxxabi/src/stdlib_exception.cpp` | `d609597f8f536fec59f7afa2dbd352c69a9b50ce8aaf85082fd1fbad08c79a25` | `mizu_fetch/e8fe2b54f261e8c8fcfa0540d2383379734c8c2417187fc6929d76b62fcca295` |
| `stdlib_new_delete.cpp.o` | `libcxxabi/src/stdlib_new_delete.cpp` | `eba213003682944709bcfeb8278da1327be01cf2620146ed9aea412ad04b6c69` | `mizu_fetch/de9838572f759a45e5809896f07c567c42848783dd2f9c060efaedb432c0a87c` |
| `stdlib_stdexcept.cpp.o` | `libcxxabi/src/stdlib_stdexcept.cpp` | `8539fc8929cd9a166a74fe04ef81472e7a6d507f4422f991963867fbda1f256a` | `mizu_fetch/9444fbc55fe08bdd7e31959ffd4ba96cea3ec06641cec6831b5bde9871329bbf` |
| `stdlib_typeinfo.cpp.o` | `libcxxabi/src/stdlib_typeinfo.cpp` | `5d0b584b9341eb49ea5e640a475dc690d44b0770712222e2667185b1e814367f` | `mizu_fetch/9ee3ffe94f07f36e30e43c94d9298bee310e5555dcf1e15bc84396d0e4ad119e` |

The three component license files were also fetched at this LLVM revision;
whole-file hashes match the component digests above: compiler-rt
`1a8f1058753f1ba890de984e48f0242a3a5c29a6a8f2ed9fd813f36985387e8d`
(`mizu_fetch/ce51531af43620f97822207b6c534da77fe8ce145658188321f98dc65fb73aa5`),
libunwind `b5efebcaca80879234098e52d1725e6d9eb8fb96a19fce625d39184b705f7b6d`
(`mizu_fetch/7cb3352abf0bd66c53ca7a31e3088a0e36f9509b6f63314aa05344d3b8dd9f17`),
and libc++abi `e2b35be49f7284a45b7baca8fc7b3ab7440e7902392b2528a457816b5bb2a15c`
(`mizu_fetch/95e37edcb4ace56559ee4afe6995221ce72c3f8e4b5b892579f698d4c5f5977b`).
This extends the header-level candidate classification to the 21 files only;
there is no complete body-level embedded-origin review. Matching paths and
permissive SPDX headers do not establish object identity, patch provenance,
linked-section survival, notice applicability, or redistribution authorization.

The NDK `move-cxa-demangle-into-libcxxdemangle` patch changes the libc++abi
build graph, and the exact map still places `cxa_demangle.cpp.o` in
`libc++abi.a`. The source-list comparison does not reveal the configured build
option or explain that archive membership. None of these candidate matches
closes patch application, member-source identity, object-section survival, or
license/notice applicability. The retained artifact inventory contains no raw
NDK archives or extracted archive-member objects. The installed `NOTICE` and
`NOTICE.toolchain` therefore remain broad candidate records; in particular,
their GPL text is not evidence of either applicability or irrelevance to these
members. The Flutter LicensePage currently exposes Unicode and crypto notices
only. It is a suitable user-facing surface for a future reviewed notice set,
but no NDK notice payload is packaged and the exact required subset is
unresolved; adoption remains disabled.

### Exact installed-NDK capture (partial)

The bounded capture completed on the exact diagnostic publication
`20ab85fc177a5dfa821f148cda27dac71473b5e51b486c4e87f9b887f67d9785` / SHA
`59cdc16f38ab3d18cf5a91aeff383b168e7792c4`, before its later DWARF and emulator
failures. Its manifest (`ndk-terms/manifest.json`, 2,735 bytes, SHA-256
`6a92040adc41f19068e0e621c0e0b17ff00f6d55d77423312cb7edc61740bff8`;
`vcs-read/4995c5cc44c24fbea2e2f794343675c5`) records 10 files totaling
1,988,532 bytes under its 64-file/16-MiB limits. Its declared capture scope is
package metadata plus matching root-level and host LLVM-toolchain license/notice/
copying/copyright files, not a complete package inventory or legal classification.
`source.properties` identifies
NDK 28.2.13676358 / r28c (108 bytes, SHA-256
`c00aa236fdb205e9be9edd9e2169763e48aca52735efff4e16f34205d49783b5`;
`vcs-read/52917ab1d9064711bb26316fb4d73726`). `package.xml` records the same
package revision and `uses-license ref="android-sdk-license"` (18,351 bytes,
whole-file SHA-256 `1d901b6452ef3f759a7d7a09b0c3ea5d745a60a8ae9a5be06db24b893ebf8a9a`;
exact captured artifact `vcs-read/e71cf72fea54473c81e5ed9c0fea84a2`; prior pages
`vcs-read/da7142b4dc9e411486fedcda2b3bc383` and
`vcs-read/47d58a05d9c84bd6ae47b91624f4fa80`). The embedded Android SDK
agreement says §§3.1–3.4 limit SDK use to Android-app development and restrict
copying or redistribution of the SDK except backup or where third-party
licenses require it; §3.5 says components licensed under open-source licenses
are governed solely by those licenses, and §3.8 prohibits removing proprietary
notices. This package-use condition is neither an open-source license for the
entire NDK nor a redistribution grant for the selected runtime archives. It
also does not determine which archive members qualify as open-source components
or which member-specific terms/notices apply; those still require exact
source/member/section mapping.
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
the map-selected static archives. The exact archive manifest
`validated-linker-map/llama-simple.map.archives.json` (`vcs-read/a0174cd30958445f915a379412d958c5`,
SHA-256 `77989f7a3172bedbd86b23a6f7fa2f5ab4dccef696ebe2657cf1dcad13df09fd`)
identifies four NDK runtime archives and 47 selected members: compiler-rt
builtins (one `emutls.c.o`), libunwind (5), libc++ (26), and libc++abi
(15). This bounds the selected archive-member set. The full source-info
patch-path comparison appears below, but it does not map member bytes to source
files or surviving sections. The required notice subset
and applicable terms remain unresolved until each selected member and
affected patch/section is mapped to its source, terms and distribution
obligation.

The corrected parser snapshot is publication
`3dc2ba80dd8f8b01bea7c80f5abf113668f9a751f9184359d0ef1e118c908d5b` / SHA
`bd2d8a0619fdbd1a5431e6671b81abc073d0b2c5`. Receipt-bound status shows
`CI / Design contracts` and `Native engine probe / Android API 35 x86_64 CPU
feasibility` passed (jobs `128737632108` and `128736947860`; evidence
`vcs-read/dc36aec496be4d5886c8b1f83d5f2d53`). Its
`validated-linker-map/llama-simple.map.contributions.json` artifact (first and
last pages `vcs-read/cc88d73fc051462e821406e220c6e6d5`,
`vcs-read/3b370cf9b1fd4d91808865f691f81541`) is 459,104 bytes with SHA-256
`504654291e47812ef7883f7f124879e921382fcd9ed4e0a4d08f88be3aefb6b5`; it records
1,563 input-section contributions across all 26 selected `libc++_static.a`
members. Each row records map line, member, input/output section, VMA/LMA, size
and alignment. Its archive identity is
`toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib/x86_64-linux-android/libc++_static.a`,
SHA-256 `893dc67b8c7eef4000af6e582421a14ea7e5fdec97249496005fc3a48f7d7099`,
size 14,336,094 bytes; the map identity is SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`, size
4,660,773 bytes. Those identities agree with the separately recorded archive
and map sidecars (`vcs-read/68517223cb504e98b12b70f95313ec4e`,
`vcs-read/dc743bbf69f04438a8ed1bcd528787a4`). The manifest contains debug
sections and is not evidence of retained executable code, exact source identity,
patch application, applicable terms or redistribution authorization; the raw
map has not been independently reassembled or rehashed here. No raw archive-member
objects are retained.

The compiler log reports Android clang 19.0.1, based on r530567e, repository
commit `97a699bf4812a18fb657c2779f5296a4ab2694d2` (`vcs-read/c2129f0d0cae49969429c6c18adadfde`). An exact upstream commit-metadata read identifies this as “Merge 3b5e7c83… for LLVM update to 530567”, with `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` as its second parent. The installed `clang_source_info.md` instead names that `3b5e7c83…` commit as its base revision and lists Android toolchain patches from repository revision `e727bfb014bd436f581a66a450c939a6983a1fc3`. The component `LICENSE.TXT` hashes recorded above were re-fetched at base revision `3b5e7c83…` and match, but this verifies only identical license-text bytes, not that the patched installed archives' selected object code matches the mapped source files. Patch-to-member/source closure remains open.

### Pinned Android LLVM patches and selected inputs

The exact diagnostic Android publication is
`20ab85fc177a5dfa821f148cda27dac71473b5e51b486c4e87f9b887f67d9785` / SHA
`59cdc16f38ab3d18cf5a91aeff383b168e7792c4`; member-DWARF capture and emulator
startup failed, but the package and patch metadata captures completed. Its
`ndk-terms/manifest.json` (exact artifact `vcs-read/4995c5cc44c24fbea2e2f794343675c5`)
records NDK `28.2.13676358`, `clang_source_info.md` SHA-256
`8ffa6ebc4941a0f0de492584444c08b65ce96ba32d824d674fd35aa0398f1454`, and the
candidate notice files. The exact source-info bytes were read in the earlier
same-r28c probe (`vcs-read/5a60708a01b74460876c8a8e9ec0ecb9`,
`vcs-read/af0cdd28285b41128da2817ec8144328`); they pin LLVM base
`3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` and Android toolchain source commit
`e727bfb014bd436f581a66a450c939a6983a1fc3`. The same-r28c probe's `compiler.log`
reports LLVM-project revision `97a699bf4812a18fb657c2779f5296a4ab2694d2`
(`vcs-read/282338e9792e4c7c9aab2cac0afde1bf`). Gitiles metadata for that exact
Android `toolchain/llvm-project` commit lists
`3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` as its second parent (along with
first parent `d8003a456d14a3deb8054cdaa529ffbf02d9b262`) and describes a merge
for LLVM update 530567
(`fetch/8f681f457b8f4d193fae4939e74314310bcbdb648f32cce753e927e90ca2d0af`).
Thus the banner revision and source-info base are ancestry-related, not conflicting
revision claims. This commit graph does not prove patch application to installed
files or identify selected archive-member source bytes. The current patch metadata
is the 1,526-byte exact-SHA artifact `vcs-read/36db48b5025e49c68da696c62b80e289`
(SHA-256 `d8dc351b4d2a681fa16997a47c02b01f3921970c62146aa3c776b1dd048ef0b1`).

The exact CI capture contains metadata for these four patch blobs; decoded
payload identities and effect review are independently reproducible from the
immutable `llvm_android` commit:

| Patch path at pinned commit | Git blob ID | Bytes | SHA-256 | Bounded observed effect |
| --- | --- | ---: | --- | --- |
| `patches/move-cxa-demangle-into-libcxxdemangle.patch` | `21533ee8f77a251f9143f16c9043f8a68e419dae` | 3,857 | `6a8879953b2133491d4bc6be97332d4d031b837e0175227969f4ef7f7d6ef8b9` | `libc++abi` CMake build-graph change only; the exact map still names `cxa_demangle.cpp.o` inside `libc++abi.a`, with no separate demangle archive in that map. This does not establish the build option value or object-section provenance. |
| `patches/cherry/9a2fd97d391caf1060e303f636d7113501788d2f-r530567.patch` | `06f046b19b45d11a32a68b0ae33cfc0d9ba823e3` | 174,905 | `9b0a015f44a91d6ed83eb9ba4b0303f0e634daa8874199eb76d74f7d61dba7b3` | HWASan compiler-pass and test changes; compiler tooling, not a linked product-runtime archive. |
| `patches/cherry/b433076fcbacba8a3b91446390bbea5843322bcd-v2.patch` | `b9772a9cf10a19f1ad7c86db4a86ae73c2ed8a66` | 18,250 | `2f6b8beec77bfb2bff02b6cf341ff31ec424834aa28c23f30ce18bb12945d8eb` | Clang CodeGen and test changes; compiler tooling, not a linked product-runtime archive. |
| `patches/cherry/e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch` | `cdd63954108d97d7c34018ccc9840cb8a6c703e9` | 15,251 | `4ff1cd2a122ecafc3d8920386bc3387b22c9b01e541931f9096b0f3d1047849d` | `libc++` regex iterator fix and tests; selected header/object provenance remains unresolved. |

The exact diagnostic publication's patch-source metadata manifest is
`vcs-read/36db48b5025e49c68da696c62b80e289` (1,526-byte manifest, SHA-256
`d8dc351b4d2a681fa16997a47c02b01f3921970c62146aa3c776b1dd048ef0b1`, describing
212,263 patch bytes plus a 16,039-byte tree index; 228,302 total collected bytes). The manifest
scope is hashes, sizes and Git object IDs only; the raw patch blobs are not
retained in CI. The checked-out temporary Git fetch has a 120-second deadline,
but the pack has no independent hard byte cap.

The four-entry capture allowlist and metadata-only manifest remain incomplete
as payload retention; the full installed source-info inventory has now been
intersected with the exact archive-member and compiler-read manifests. The
retained `clang_source_info.md` is 11,370 bytes with SHA-256
`8ffa6ebc4941a0f0de492584444c08b65ce96ba32d824d674fd35aa0398f1454`
(`vcs-read/b16654cc3bf946759bffa59d44c7396c`, continuation
`vcs-read/09c32684b9ff4a219be8f310a9d6d7b1`); it names LLVM base
`3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` and Android toolchain source
commit `e727bfb014bd436f581a66a450c939a6983a1fc3`. Its 52 patch entries were
decoded and their diff paths compared with all 47 map-selected NDK archive
member names (and basename-inferred source candidates) and the exact selected
compiler-input hash list. Four patch entries directly name a selected
compiler-read header; none directly names one of the candidate source paths
inferred from the 47 archive members. The other 48 entries modify
compiler/driver/linker code, build configuration, tests, nonselected
sanitizer/HWASan/OpenMP paths or other target architectures. These are direct
path results only: toolchain changes may affect generated code, and no path
comparison proves patch application, object-section survival or license
applicability. Paths in the table's selected-input column are relative to
`ndk/toolchains/llvm/prebuilt/linux-x86_64`. The four exact intersections are:

| Source-info patch | Exact diff path | Exact selected compiler input | Link-map relation and remaining limit |
| --- | --- | --- | --- |
| `f886dfed3ae6cf70827cedc8d8aefde6250a239b.patch` (`experiments/15418f8ce0bb4431ad2c5081095d8142`) | `libcxx/include/__config` | `sysroot/usr/include/c++/v1/__config`, SHA-256 `4a2eb47672b4f8c68000044174ba4ea01a00e287483a3fda12b29ed268fa93da` (`vcs-read/c55baa2e6768434ea8cf0fb8494de267`) | Header input; no direct member-source path. Upstream patch-commit hash does not match the installed input hash; presence and binary effect are unproven. |
| `e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562.patch` (`experiments/52e149171bb14295972aaff3b7922196`) | `libcxx/include/regex` | `sysroot/usr/include/c++/v1/regex`, SHA-256 `2ea7d95853a15ef16925668750ccdface9deead18c79fb3e8064447ff326d982` (`vcs-read/e4719ea39a8c4086b6b1df600ae8d707`) | `libc++_static.a(regex.cpp.o)` is selected; the upstream base, patch-commit and installed-header byte hashes differ, so patch-to-input or surviving-object identity is not established. |
| `Revert-Fix-diagnostic-for-stdatomic.h-before-C++23.patch` (`experiments/fdd2d7dbe3f5413f959b130736580eae`) | `libcxx/include/atomic` | `sysroot/usr/include/c++/v1/atomic`, SHA-256 `99cb8c4b0cc7866a710f877a377c9749a3e3c6905d8eb7012b00859f20a4a1bd` (`vcs-read/800cb3aec4ed416da5af9ccce09ea7e4`) | Selected header input; the map has no `atomic.cpp.o` member. Header use/inline code and any emitted-section effect are not proven. |
| `7d20ea9d32954e8e5becab8495fa509a3f67b710.patch` (`experiments/b8af38156bb743bea1d01296e5ed72e5`) | `clang/lib/Headers/limits.h` | `lib/clang/19/include/limits.h`, SHA-256 `201a7790932ddd1da2b69c0484d6d8ecd076e08684aabc5ce984bd0fa8ef2cf8` (`vcs-read/4b378905b66c401698249f915c141d39`) | Selected compiler resource header, not an archive member source path; patch-to-installed-header and emitted-code effects remain unverified. |

The complete two-page artifact inventory for this publication
(`vcs-read/d6a5d402b76f4afa93e824c6df38515f`, continuation
`vcs-read/91af38e63bf749a590cc96db8cac8bcd`) retains the archive manifest,
link map, compiler-input hashes and notice records, but no raw NDK runtime
archives or extracted archive-member objects. Exact source/member provenance
therefore cannot be recovered from these retained CI artifacts.

Representative non-overlap checks include compiler-rt sanitizer-common code
and tests (`experiments/8f0c09ce7db342b0ab38a6d182a83f83`), the AArch64
`sme-abi-init.c` builtins path (`experiments/cf1ad34f6f854620ba3889f24bc8d1eb`),
HWASan-only paths (`experiments/f597dd462c6747a98345d206d05e3698`,
`experiments/4c7282f3061945fab7783dcf7fdd0e55`), and `nl_types`-related OpenMP
runtime code (`experiments/8d1dcff7ab4a4bc1a0c486a3c54afb13`). These examples
do not substitute for the full path comparison or establish whether toolchain
changes influence emitted code.

The source-info inventory closes only this bounded diff-path intersection. It
does not close exact archive-member source identities or surviving sections,
patch presence in installed files, per-file notice obligations, or user-facing
notice delivery. The app has a user-accessible Flutter license page: the info
button in `lib/main.dart` opens it, and `test/licenses_test.dart` verifies
bundled notice access. The current app registers only the Unicode and crypto
notices from `assets/licenses/`; `pubspec.yaml` packages those two assets and
no NDK notice payload. This is a delivery surface, not delivery of the NDK
notices. The broad `NOTICE.toolchain` contains GPL-2.0 text, but these path
comparisons establish neither applicability nor irrelevance. Keep all unknown
selected terms fail-closed and engine adoption disabled.

The demangler patch affects build-graph selection. A bounded decode of the
exact `9a2fd97` patch in experiment
`experiments/2aa9e6e756234995819851b9e7b6ce5b` measured 174,905 bytes and
SHA-256 `9b0a015f44a91d6ed83eb9ba4b0303f0e634daa8874199eb76d74f7d61dba7b3`,
matching the NDK manifest; its six diff paths are the HWASan
instrumentation pass and five tests. None names the candidate
`compiler-rt/lib/builtins/emutls.c` path for selected member `emutls.c.o`
(`vcs-read/a0174cd30958445f915a379412d958c5`). This rules out a direct edit
to that candidate source path by this patch only; member-source identity and
surviving-section provenance remain open. The complete diff-path intersection
is recorded above. The CodeGen patch is a
compiler change. The regex patch
affects a selected libc++ input, but neither patch-to-installed-header identity
nor survival in the linked runtime object is established.

The fourth captured patch raw payload was independently fetched from the exact
`llvm_android` revision `e727bfb014bd436f581a66a450c939a6983a1fc3` through
Gitiles (whose endpoint returns Base64) and decoded in bounded experiment
`experiments/52e149171bb14295972aaff3b7922196`: 15,251 bytes, SHA-256
`4ff1cd2a122ecafc3d8920386bc3387b22c9b01e541931f9096b0f3d1047849d`, matching
the NDK capture manifest SHA-256; that manifest records Git blob ID
`cdd63954108d97d7c34018ccc9840cb8a6c703e9` (`mizu_fetch` receipt
`95d67600306683e5838227da6c404ce6f374678d996c30e56148f72fefc266a3`). Its diff
names only `libcxx/include/regex` and two tests; it updates
`regex_iterator::operator++` to preserve the preceding match end as the
unmatched prefix after a zero-length match, and the added test declares
`Apache-2.0 WITH LLVM-exception`.

The exact compiler-input record selects this header, and the
link map selects `libc++_static.a(regex.cpp.o)`. The earlier exact r28c selected-input
artifact page (`vcs-read/2df5e51c0539440bb5e5d15ff2913609`) hashes the installed
`sysroot/usr/include/c++/v1/regex` input as
`2ea7d95853a15ef16925668750ccdface9deead18c79fb3e8064447ff326d982`. Exact
immutable-source fetches hash the header at pinned LLVM base
`3b5e7c83a6e226d5bd7ed2e9b67449b64812074c` as
`897795afd99ac6fea51498ab5bdcdfac55bfd652e82200e8a0fe8a3d9ea35451`
(`mizu_fetch` receipt `f614c261c435ba26dbc74edc5353061a4817a22b0ee0b9712111292cdf988cc1`)
and at upstream patch commit `e9adcc488f96a9f2b8c4344f5e3c7ca6639b9562`
as `60ae1433a22fac00ed0935778d1f3fa7e33b37e99aa33e1907273fa02fdd685a`
(`mizu_fetch` receipt `193d5ec9a2c090a79f73ba0e285ee545a8a2211579bd22111dc42132b5191b75`).
All three byte hashes differ.

A fresh immutable-source check fetched `libcxx/include/regex` at compiler-
reported LLVM commit `97a699bf4812a18fb657c2779f5296a4ab2694d2`: its 212,825
bytes and SHA-256 `897795afd99ac6fea51498ab5bdcdfac55bfd652e82200e8a0fe8a3d9ea35451`
are identical to the source-info base `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c`,
but not to the upstream patch-commit header. Fresh exact source receipts are
`mizu_fetch/214989f9f14857abe317f1e6609c32ef739739c946684efad9bcee58eaf9599c`
(base), `mizu_fetch/ff762f9a255360c1140bd1acd8e2281d7d953e83d9ef6024f04bbd38c2448a51`
(compiler-reported commit), and
`mizu_fetch/5270406d11283568e964439fc2b4c9b89a7812db3bc747ec070bb56d151ae329`
(upstream patch commit). Bounded Git blob hashing gives the base/merge object
`dc3db93744b489a32dc1abb0f63c63faf23aaed0` and patch-commit object
`46968357d39747d887c2e105dd579487ff84d864` (experiments
`e3334137e11b4ed78ccf3805f06246e7`, `d2c1106bb6de43ff8aacfe36099c3b1f`,
`12c07ee7f03949f399e7507951fbb664`). The latter matches the upstream commit
diff's postimage prefix `46968357d397`
(`mizu_fetch/ec7748ca84bf492028ca84db48a8810d99ef00fc3be3e3551e87efe1f655db4a`).
That hunk adds `regex_iterator` friendship and updates prefix bookkeeping after
successful search, preserving the previous match end for zero-length matches.
This establishes the changed header bytes in the upstream patch tree and their
absence from the compiler-reported upstream tree, whose header is byte-identical
to the source-info base. It does not establish whether the installed NDK input
is patched, backported, or behaviorally equivalent: its recorded hash
`2ea7d95853a15ef16925668750ccdface9deead18c79fb3e8064447ff326d982` differs,
and the installed header bytes and extracted object sections are not retained.

The selected read proves the installed header is
a compiler input, while the map member proves an object was linked; neither
proves that this source patch's changed code survives in that object or the final
executable. Patch-to-installed-header and patch-to-binary provenance therefore
remain unresolved. The changed source/header files carry Apache-2.0 WITH
LLVM-exception SPDX identifiers; component-level legacy alternatives and the
license choice for any selected binary section remain as described above.

The exact c87 publication captures all four patch paths as metadata only; its
`patch-source-capture.log` records four files and 228,302 total bytes
(`vcs-read/d9758c2d11614dcf8009cb751a57f825`). The raw patch blobs are not
retained, and this confirms capture execution—not patch-to-installed-header
identity or surviving binary code.

LLVM `LICENSE.TXT` at pinned base `3b5e7c83a6e226d5bd7ed2e9b67449b64812074c`
has whole-file SHA-256
`8d85c1057d742e597985c7d4e6320b015a9139385cff4cbae06ffc0ebe89afee` and was
read in full (`mizu_fetch` receipt
`d1d1fded9c6e52c13b7929cb38acd367f76f773c57f6b0bd6e4e422e3d18c42d`). It
contains Apache-2.0 plus LLVM exception text, a third-party license notice and
legacy UIUC/NCSA terms. File headers at that immutable base revision identify
`clang/lib/CodeGen/CGDecl.cpp`,
`llvm/lib/Transforms/Instrumentation/HWAddressSanitizer.cpp`, and
`libcxx/include/regex` as `Apache-2.0 WITH LLVM-exception`; the changed
`libcxxabi` CMake files have no overriding file header observed. This classifies
these reviewed LLVM patch/source files only. It does not classify every NDK
archive member or notice: the installed broad NDK `NOTICE` and `NOTICE.toolchain`
include other attributions, and their applicability must be mapped to exact
selected member/source/section before distribution.

The source-file spot checks used the exact base-revision raw-source receipts:
`CGDecl.cpp` (`vcs-read/5b08d3658d04a28fa7e7ec4fdc18e865e4bc9dabd6dad482425baa1753e258b6`),
`HWAddressSanitizer.cpp` (`vcs-read/919e5a18b4d76b7492d2c637a03e19b9551d9f59dd43564504f261c88c6213c5`),
libc++ `regex` (`vcs-read/267def09866ca3ba1122834000e5f7e06ed8ab0efa9a7220efbf5c52cc9967ab`),
and `libc++abi` CMake sources (`vcs-read/67d6bd8cf494fa69223a8d14e77cfadfbdf21a4d03cd04ae78749bd3486c5c8d`,
`vcs-read/9a90d75b69bb91f364a6dbabdd545516775663a2c52c9731b3d0c43e67304b4f`).
The exact file terms/payload hashes do not authorize product adoption. The NDK
static-runtime member-to-object/source/section mapping, complete applicable
notices, user-accessible notice delivery, OS runtime terms, ARM coverage and
physical-device evidence remain open. No distribution or support claim is made.

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

The Android-only `llama-simple` link emits LLD `-Map` to `llama-simple.map` inside the clean configured build root. After linking, the probe requires a regular, nonempty file no larger than `ENGINE_LINKER_MAP_MAX_BYTES` (128 MiB default). `linker_map.py` parses and hashes the map in one bounded pass, resolves every `.a(member)` row within the configured build or NDK root, hashes each unique regular archive, and stages `llama-simple.map`, its byte-size/SHA-256 sidecar, `llama-simple.map.archives.json` and `llama-simple.map.contributions.json` together before one directory rename. The archive manifest lists root-relative paths, exact archive sizes/digests and the member names named by the map. The contribution manifest records each selected NDK `libc++_static.a` input-section/output-section mapping, VMA/LMA, size, alignment and map line, without retaining archive-member object bytes. The parser follows LLD output-section headers, checks each contribution range against its enclosing output section, and rejects malformed headers or mismatched explicit section labels. It is bounded by the configured map limit and requires every selected libc++ member to have a mapping. This metadata does not establish source identity, patch provenance, licensing/notice applicability or runtime behavior. The map remains raw linker output, not a normalized inventory: inspect its exact rows rather than infer completeness from `-static-libstdc++` or ELF `NEEDED`. The exact Android inventory in publication
`0f9b59bf92eca25d42bce26015e3254228419da6853def4fe4a7b360f32f19f0` / SHA
`678896ce4c8d9b73ba56d897e0d575e36e67ea7e` has a 5,417-byte archive manifest,
SHA-256 `6be9cfbb85dffc2f419d832fc03f280775a929b62fb0ee3d3cd36ebc48bc2474`
(`vcs-read/44542b47ba7e4958aaadf7c4cf3bcc39`), and a 96-byte map sidecar,
SHA-256 `4f1b583fec32579adb492d8cc7bc0769ef46b4fbcc3f1856ab78efbafe558ac3`
(`vcs-read/9a04acbf8a2e4257b107f388e9f344a5`). Both declare the 4,660,773-byte
map SHA-256 `2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`.
The manifest binds `libc++_static.a` (14,336,094 bytes, SHA-256
`893dc67b8c7eef4000af6e582421a14ea7e5fdec97249496005fc3a48f7d7099`) to the
same map. The exact DWARF report is tied to this archive-manifest digest and
records 26/26 selected members with compile units
(`vcs-read/5701564fb46b4a78b51bb250a1f061f5`). The raw map, archive inventory
and DWARF metadata do not prove source identity, patch provenance, applicable
notices or redistribution rights. The contribution manifest is absent from
this publication.

The `android-api35-x86_64-engine-probe` artifact retains the linker map, its hash/size record and, on successful capture, the archive and libc++ contribution manifests alongside raw compile commands,
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

**Current evidence limits:** the latest exact combined native-engine probe is
publication `a717c516acc2cd60945b93cc65c6d9d37387033e1116a0aeae897794c08f77e8`
/ SHA `1af9fc2853ff8998c261c7ad8b7f5302873c240e`. Receipt-bound status
`vcs-read/5dab69ca10fd42f2b3247c07c95dc5f3` shows the Android API 35 x86_64
and Windows x64 probe checks passed in run `42493623648`. The Android artifact
set includes the corrected bounded DWARF report and the linker-map contribution
manifest; these captures are now present on this exact publication, rather than
outstanding. The Android smoke is limited to the API 35 x86_64 emulator. The
reports identify candidate member paths, mapped sections and one synthetic
sample; they do not prove NDK object/source bytes, patch application, retained
executable sections, applicable terms/notices, redistribution or physical-device
behavior. See the platform gates below for the exact retained evidence and open
conditions.

The previous exact Android probe publication
`20ab85fc177a5dfa821f148cda27dac71473b5e51b486c4e87f9b887f67d9785` / SHA
`59cdc16f38ab3d18cf5a91aeff383b168e7792c4` retained the map, archive/member,
compiler-read and NDK metadata before its DWARF failure. Its manifest and
sidecar agree on map SHA-256
`2402cfa450db1486d103f60f64f245923afd639b74f2a1b2b06944f340936fbd`; the
complete artifact inventory is recorded on pages
`vcs-read/7e2e95a3e76545a18644dbfef1225529` and
`vcs-read/b5d6539719b04b2bb41625846b104085`. These archive details remain
historical evidence, not a fresh complete-artifact review of the later run.
The earlier successful emulator observation at publication
`297d605988c1f6867ba745c26ad064ecd0590223952d3eb940abb4f15a0e1baa`
(`vcs-read/57c733d1cb7b4bd39a8c73d74dfefcb8`) resolved `/system/bin/linker64`
imports on Android 15/API 35 x86_64 only. Neither run establishes
physical-device behavior, other ABIs/OS versions, all `dlopen` paths, provider
legal terms or product linkage. Selected NDK archive/member provenance,
complete applicable notices and user-accessible delivery remain unresolved;
no adoption, model redistribution, persistence, privacy, quality or platform-
support claim is authorized.

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
`vcs-read/88ac4b9e07df4d4fa801a67663708777`). `compiler.log` identifies clang
19.0.1 based on `r530567e` and Android LLVM project commit
`97a699bf4812a18fb657c2779f5296a4ab2694d2`
(`vcs-read/783cc1253f92473ea59df0446e1ba9d9`). `link-inputs.txt` names the four
engine archives (`vcs-read/135c0fac899e415bbec2ccb57544a1ef`); the map-derived manifest additionally records the selected NDK
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
every record. The configured 64-file/16-MiB bounds fail closed. The exact
Android API 35 x86_64 job for publication
`3dc2ba80dd8f8b01bea7c80f5abf113668f9a751f9184359d0ef1e118c908d5b` passed, and
its selected-member contribution evidence is recorded above. This validates the
bounded capture, not the terms records' applicability to linked members. The
source/member/patch mapping and complete applicable per-file terms remain open.
Do not infer complete license
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

The latest exact Android API 35 x86_64 native-engine probe is publication
`a717c516acc2cd60945b93cc65c6d9d37387033e1116a0aeae897794c08f77e8` / SHA
`1af9fc2853ff8998c261c7ad8b7f5302873c240e`; its Android check passed in run
`42493623648` (job `128771063706`; status `vcs-read/5dab69ca10fd42f2b3247c07c95dc5f3`).
The exact report `vcs-read/c5ff83d15f9046859a8826ccef35f323` (12,917 bytes,
SHA-256 `5a0764d6fb9c795d4f80998a40dfdc347fe65180b63743e3cd856f763ab080ec`)
binds the link map and `libc++_static.a` to the captured archive manifest. It
records compile units for all 26 selected libc++ members, component-relative
`libcxx/src/...` DWARF paths, and reduced producer `clang version 19.0.1`; raw
archive-member objects and raw DWARF are not retained. The separate contribution
artifact `vcs-read/c017d0011315425ca607cad010b4733a` (459,104 bytes, SHA-256
`504654291e47812ef7883f7f124879e921382fcd9ed4e0a4d08f88be3aefb6b5`) records
1,563 input-section contributions across those 26 members. The archive manifest
names 47 NDK archive members across compiler-rt, libunwind, libc++, and libc++abi;
the contribution artifact covers only libc++ and is not proof that mapped bytes
survive in the final executable.

The exact smoke artifact `vcs-read/410e26585a2e498795730bce37451744`
(SHA-256 `6d63d1b4fde218427a91dcca18595a68b770465d7c9ddf27a13af9f3616c519e`)
records Android 15/API 35 x86_64 emulator fingerprint
`Android/sdk_phone64_x86_64/emu64x:15/AE3A.240806.019/12368160:userdebug/test-keys`,
loader resolution of `libm.so`, `libdl.so` and `libc.so` under the Android runtime
APEX with provider hashes, real-loader rejection of missing/truncated GGUFs, and
one generated-only `Bonjour.` sample. This is a narrow emulator observation,
not language-quality, physical-device, ARM or other OS/ABI evidence.

NDK r28c package/source-info and patch captures, candidate-source hashes and
license texts are described above. DWARF paths and basename/source-list matches
still do not prove the installed archive-member source bytes; patch-to-installed-
input and patch-to-surviving-section provenance remain unresolved. The broad
NDK notices do not determine which terms apply or are irrelevant, and the app's
license page currently carries no reviewed NDK notice payload. Applicable terms,
notice set and user-accessible delivery, selected-section/runtime closure, and
redistribution authorization remain open; Android engine adoption stays disabled.

### Windows runtime and delivery gate

The latest exact Windows x64 native-engine probe is the same publication
`a717c516acc2cd60945b93cc65c6d9d37387033e1116a0aeae897794c08f77e8` / SHA
`1af9fc2853ff8998c261c7ad8b7f5302873c240e`; its Windows check passed in run
`42493623648` (job `128771063475`; status `vcs-read/5dab69ca10fd42f2b3247c07c95dc5f3`).
The exact `runtime-providers.json` artifact (`vcs-read/339838cf95884ba1b24c4bf67d14da30`,
5,692 bytes, SHA-256 `450ce0c1f74b55deba34fa5c13f82b607a8d1427e2621a98b20ecbbdf419fafc`)
and summary (`vcs-read/69f5b84847d64ba7b7d8c634f337ec09`, SHA-256
`882fb93c80accc69432068e60b044d8dc81cb43d1bbcc4c0455b98f0657259b5`) bind the
pre-entrypoint `llama-simple.exe --help` capture to executable SHA-256
`fef29542fdc1cd13e579d64e2bd5c018e2698f979879c66034eeccfbc1fff745` and linkage
SHA-256 `8042425d905cedfffcc422c2885470eabc18273a3374b314221bee2b9c033987`.
They report 14 direct imports, zero delay imports, 9 API-set contracts, 11
loader-resolved providers and zero redacted paths. Direct imports include
`MSVCP140.dll`, `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll`; each resolved under
`windows/system32` at version `14.51.36247.0`:

| Provider | SHA-256 | Observed version |
| --- | --- | --- |
| `MSVCP140.dll` | `7c26614e1d733892c2deac7e245ce115504b1d80592dd0a01b08e3e5a55f89ca` | `14.51.36247.0` |
| `VCRUNTIME140.dll` | `d1f4225df2cd877dbf130d5668a021dce3f94118455ff5ec952061c30afc9ce7` | `14.51.36247.0` |
| `VCRUNTIME140_1.dll` | `a7146c08f89fe5b04541ab507cdb59ff7b44534d4ba3c668a426c6450a03434e` | `14.51.36247.0` |

The observed System32 providers have cache-only `WinVerifyTrust` signer status
`Valid`; no online revocation retrieval or provider binaries are retained. This
is one CI-runner loader observation, not a Windows runtime entitlement or
redistribution authorization. The exact run does not establish providers or
installation terms on other Windows versions.

The developer-only Windows workflow captures actual `LOAD_DLL_DEBUG_EVENT`
file handles before the executable entrypoint, hashes observed files, records
file/product versions and cache-only Windows trust status without online
certificate retrieval, and classifies paths under the probe directory or
`%SystemRoot%`; providers outside those roots are represented by basename only.
Direct ordinary PE imports must tie to observed module basenames;
`api-ms-win-*` and `ext-ms-win-*` remain contract names, not fabricated DLL paths.
The process is terminated before the initial breakpoint is released. Workflow
defaults are a 60-second debug wait and 256 provider/import records;
`ENGINE_RUNTIME_DEBUG_SECONDS`, `ENGINE_RUNTIME_MAX_PROVIDERS` and
`ENGINE_RUNTIME_MAX_IMPORTS` configure them. The workflow's 15-minute job cap
bounds runtime. These are capture limits, not the Windows loader or every
supported runtime. The exact run establishes one host observation only, not
redistribution approval.

Microsoft's [Visual Studio 2026 REDIST
list](https://learn.microsoft.com/en-us/visualstudio/releases/2026/redistribution)
says a validly licensed copy may distribute listed files unmodified, subject to
the edition's license terms. It lists the Visual C++ runtime files under
`VC\redist` except the `debug_nonredist` folders and names the runtime merge
modules. Microsoft Learn separately states that distributing the VC++ runtime
package, merge modules or individual binaries is limited to licensed Visual
Studio users and governed by those terms. The current v14 deployment guidance
requires a matching architecture and a Redistributable at least as recent as
the build tools; it recommends the current supported package. These are
conditional redistribution/deployment rules, not project authorization. The
operator explicitly confirmed that Kotoha has no Visual Studio license
entitlement or agreement and no basis to redistribute Microsoft VC++ runtime
DLLs (`operator/kotoha/a-e1ceeae8-r1-1794137634`). No Windows runtime
distribution path is chosen. Accordingly, do not ship the observed MSVC runtime
DLLs or treat the CI runner's `windows/system32` copies as product files or as
evidence that target users have an approved preinstalled prerequisite. Kotoha
has not selected a preinstalled-runtime requirement or a supported
Windows/runtime floor. The `/MD` imports keep this Windows engine distribution
path blocked under the current operator constraint; any alternative toolchain
or runtime requires a separate evidence and licensing review. Windows engine
adoption remains disabled. The exact provider binaries and runner license terms
are not retained.
Sources retrieved 2026-11-08: VS 2026 REDIST receipt
`mizu_fetch/7881f08bbb7a445200d35e7018cd772e6069168f4a20f97dbba26529e037be9d`,
SHA-256 `d103654c2ba511d3f9934fc4ae62cf4342b6a92d737867b9b8315bad88ce413e`;
VC++ redistribution page `mizu_fetch/0540ed656694535d3b217cf5c6ac779e6391103e4e5eb44bc8f7d25264a333df`,
SHA-256 `b54924fde2ea7cb46a7002aebdffcd06a27e84f310a74fbf9543355dfe059863`;
latest supported runtime page `mizu_fetch/32530cdeed12944dea69d9fe0294bc551574bab54d7b8909a8aa92af488ee51b`,
SHA-256 `631e73734f66a3a62546d9c97bcd7408447548f312aae54a2aec9170e5c0592e`.

Microsoft documents the Universal CRT as a Windows OS component included in
Windows 10 or later and Windows Server 2016 or later; older supported systems may
receive it through Windows Update, while local deployment is subject to specific
restrictions. The system UCRT is always used on Windows 10/11 even if the app
contains a local copy. This is conditional OS guidance, not a product support
floor: neither Kotoha's supported Windows minimum nor this `windows-latest`
runner's exact OS build is captured here. Thus API-set contracts do not establish
the UCRT provider across all supported product targets; this CI run observes the
provider on one runner only. Microsoft Learn page retrieved 2026-11-08: `mizu_fetch/30c74266cc7b61875a639168acac25a15014b7d83333442769b820c29e735f2b`,
SHA-256 `ffb73fffc0daf9f3f973b39a7691c59d50fe79184d82e23e3ae00dc69feb568e`.

KERNEL32/ADVAPI32 and UCRT providers are now observed on one CI runner, but
supported-Windows provider and terms review remains. VC C++/vcruntime DLLs are
**not assumed OS-provided**; the exact run observed them in `windows/system32`.
For any product runtime, match its exact provider identities to the selected
installation's REDIST list and terms. Record provider, linkage, redistribution
and approval under policy. Do not ship runner DLLs or infer redistribution
permission from dumpbin.

Before adoption: close generated/header and selected-term gaps above, then ship
complete selected notices alongside the engine and expose them through the app's
existing license action (including all intrinsic attributions and applicable
data/runtime notices). CI logs or this audit are not user-accessible notice
delivery. No engine notices/assets are added to the app before selection is
approved. Product brokering/session-only consent, model/language reporting,
cancellation/resource failures, verified no-network/no-text-persistence behavior
and Flutter integration remain separate gates. The watchdog is not cancellation
evidence. Draft persistence retains its existing security/recovery gates.
