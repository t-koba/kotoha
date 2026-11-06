# Memory-only plain-text and Markdown import

Kotoha implements user-triggered import on macOS, Windows, Android and iOS.
The mobile source and tests still require native compilation and hosted execution
before acceptance; local Dart tests are not mobile runtime evidence. The selected
content is decoded into the source editor in memory and can then
be edited manually; existing translation fields and the copy action remain
unchanged. No model inference, network client call, selected path retention, cache
copy, or draft persistence is part of this workflow. The user's original file
remains outside this guarantee.

The audited umbrella `file_selector` uses an Android cache copy and iOS
`asCopy: true`; the app-owned mobile adapter below replaces those paths rather
than attempting to delete copies afterward. No mobile dependency is added.
Linux remains separate because the project's designed Linux Flutter host must
avoid GTK, while `file_selector_linux` links GTK. Neither prerequisite blocks
the macOS/Windows slice.

## Selected desktop packages and exact resolution

`pubspec.lock` resolves only the desktop implementations and their common
interface, not the umbrella or mobile/Linux selector packages. The exact
pub.dev archive SHA-256 values and full exact-version license-page evidence are
recorded below. Each license-page digest is SHA-256 of the complete rendered
upstream page, which contains the full terms; archive hashes bind the package
source used by the lock.

| Package (locked version) | Archive SHA-256 | Full upstream license page SHA-256 |
| --- | --- | --- |
| `file_selector_macos` 0.9.5+2 | `d785431f1910aac8a50e5c492cae912320158030a88703c67b9ef7f1f96fd7ba` | `1466d4cb35da174800a80ec4a827979b7e6f9af555c4f97dbc55e635881aff9b` |
| `file_selector_windows` 0.9.3+6 | `fbefc5fb92c6d3cbe8d284a2cd971b593bb07d2cd6da8557b81a862250b4acec` | `612e7b01214a97770a41c715e1d96b02e807b14f424e18de15de59e22301f85a` |
| `file_selector_platform_interface` 2.7.0 | `35e0bd61ebcdb91a3505813b055b09b79dfdc7d0aee9c09a7ba59ae4bb13dc85` | `8b8e497fc68982da7fcd4461e142382d20f8deaa67043cc7decabb7f6f0db9c2` |
| `cross_file` 0.3.5+2 | `28bb3ae56f117b5aec029d702a90f57d285cd975c3c5c281eaca38dbc47c5937` | `0770fb0009ca03130975a2e99d51025902b0d9afd38fbceedf01c62e8d69506d` |
| `http` 1.6.0 | `87721a4a50b19c7f1d49001e51409bddc46303966ce89a65af4f4e6004896412` | `67848bd26d07e5030f4f54658bf3a6b79bf3a546bab0a224486c1991da218f9a` |
| `http_parser` 4.1.2 | `178d74305e7866013777bab2c3d8726205dc5a4dd935297175b19a23a2e66571` | `7cbb213efb00465c2d12060511bbe2167ae47f1d58afd8fb295680495224c4ec` |
| `typed_data` 1.4.0 | `f9049c039ebfeb4cf7a7104a675823cd72dba8297f264b6637062516699fa006` | `d239a7f7561b57a0be50c18e987235907f79e6a513030e01969dd2dae0938769` |
| `web` 1.1.2 | `e119e82ac4795c7925103b7cf3768191f33941b99e7ccffbd6c645201d9f606b` | `09deb0705576ce347891446f980a1d233230b76ab44971e8271773691ad3f1b9` |

The remaining transitive dependencies already exist in the app lock; their
exact archive SHA-256 values are in `pubspec.lock`, and their exact-version
full license-page digests are:

| Package (locked version) | License page SHA-256 |
| --- | --- |
| `async` 2.13.1 | `0d737f95fd411d8a3db85ead252c6b653d792f93a257fb3cb6474a2c3f2de5e3` |
| `collection` 1.19.1 | `195fb7824c58f05bf880982b6e4108c2e275de58bbb4e076d52048d2e5b542e5` |
| `meta` 1.18.3 | `52b0db3684f042bb7606cca8049cb64019ff893a3f846f724ba3fa5c3dfbec49` |
| `plugin_platform_interface` 2.1.8 | `f5b8481676bf29edd841d2443bb7c56863525c823e6bfe6d16312241b00bd808` |
| `source_span` 1.10.2 | `813a2625618e40853b7730806c84d1b9b708e5bb2ef7c1a535d5e068b1b86671` |
| `string_scanner` 1.4.1 | `b1052abda6e8f75de6e56d6235c28eab88bc8c34ad6b466e0c0bc3c9a45171bc` |
| `path` 1.9.1 | `73bf40706818db1a7c539b19765db743fd39bb743177139f7ce49f34fe082ae9` |
| `term_glyph` 1.2.2 | `051c3e1f69ba5b7174cf15e69bc7cfd632ad69e1fe197edcec03c2968b4a7520` |

The dependency graph is limited to those packages: the selector packages use
`cross_file`, the common interface and Flutter; the interface adds `http` and
`plugin_platform_interface`; `http` adds `async`, `http_parser`, `meta` and
`web`; `http_parser` adds `collection`, `source_span`, `string_scanner` and
`typed_data`; `source_span` adds `path` and `term_glyph`. `cross_file` also uses
`meta` and `web`.

### License decision

For every package above, the complete exact-version license text is BSD
3-Clause: redistribution retains the copyright, conditions and disclaimer,
and the no-endorsement term is retained. Each term is classified as
`permissive` under `specs/dependency_policy.json`; no unknown term or excluded
license branch remains. In particular, pub.dev marks `cross_file` 0.3.5+2's
license metadata as unknown, but its exact-version page includes the complete
BSD 3-Clause text; the classification is based on those terms, not the metadata
label. License notices remain in the package sources. The app keeps Flutter's
License page as the user-accessible delivery surface; the existing license test
covers the bundled Unicode notice, not a package-by-package registry assertion.

The relevant package source was also inspected, with source-file SHA-256 values
below. The package archive hashes above bind these files to the selected
published packages.

| Source | SHA-256 |
| --- | --- |
| macOS `FileSelectorPlugin.swift` | `2ce6820e865f645c7823c82091d1df2a3a2f36662add35fd75d509b9a5bcc24d` |
| macOS Dart `file_selector_macos.dart` | `ca66cdc242edec2749c28b106bb364a5ac8b2669d9494e6d0fa1c3bd545edffc` |
| macOS picker entitlement README | `efabe466bf9b70bf310d517904469b1f6d01a93673f03a9d157da74ef0e1013b` |
| Windows Dart `file_selector_windows.dart` | `a9fff36257ce9b6e874f3f207526d3ce6d5221f39b9a9bfb92a10c8b84e4f74a` |
| Windows `file_selector_plugin.cpp` | `17e0345a6c0a508986d7d2100ecd04880339b40459c46bb1c14370cbce4b2d3e` |
| Windows plugin `CMakeLists.txt` | `a233e689aea9f7962ee635e02b68d7db3b0903fb5fb854898ecec400d7931a82` |
| `cross_file` IO `XFile` implementation | `6fc172b039ffc7e9df8c0fbb557264383a4ed67175c26e21919809db6a6f82d1` |
| platform interface `FileSelectorPlatform` | `0fcae2ba20e51a8a422ff127a106046504445772f69a8f912221bc83e7050a1e` |
| platform interface method-channel implementation | `bcd2c14e81c08356a1e45d520fb21658019ab0d5f27c7b923520986f6f18e5f9` |
| platform interface type exports | `d7e2982a26ba4a7997686e2abe1a8add8a277bf5e1065953f3ad35fb58ca4771` |

## Data flow and platform review

- The desktop picker receives `.txt`, `.md`, and `.markdown` extensions plus
  recognized plain-text and Markdown UTIs. Mobile uses advisory broad data filters
  (`*/*` on Android, `.data` on iOS) so provider MIME/UTI mappings do not exclude
  Markdown; both native adapters validate the selected name before loading bytes.
  Dart independently validates every returned name. It strictly decodes UTF-8,
  strips a UTF-8 BOM, and replaces only the in-memory source text after consent
  when nonempty text would be replaced. Cancellation, errors, unsupported
  extensions, invalid bytes, or a source edit during selection/read/consent
  preserve current content. No selected path or filename is retained.
- macOS `NSOpenPanel` returns selected URL paths; the plugin does not copy the
  selected file. The `cross_file` IO `XFile.readAsBytes` implementation reads
  the selected path via `dart:io File.readAsBytes`; it does not call `saveTo`
  or write a cache file. The app sandbox receives only
  `com.apple.security.files.user-selected.read-only` in DebugProfile and
  Release entitlements.
- Windows uses the OS `IFileOpenDialog`/COM shell API and returns the selected
  filesystem path. The plugin CMake lists no bundled third-party libraries;
  the app reads the path into memory using the same IO `XFile` implementation.
- Platform runtimes: macOS AppKit and the Windows Shell/COM dialog are
  platform-provided, linked through the Flutter desktop plugin, and are not
  redistributed by this dependency. The app's approval is limited to the
  user-triggered, read-only document selection in this scope. Windows needs no
  added app permission; macOS uses the read-only sandbox entitlement above.
- The interface's transitive `http` package is part of the license closure,
  but Kotoha's desktop path does not call it. No Kotoha network request or
  remote service is added. An OS file provider, mounted volume or cloud
  provider may itself fetch selected content; the picker cannot guarantee
  offline-local input.

The exact desktop package archives and full license pages establish a
permissive dependency closure. The umbrella `file_selector` is not added:

- Android `file_selector_android` 0.5.2+11 uses `ACTION_OPEN_DOCUMENT`, then
  writes provider bytes with `FileOutputStream` beneath app cache before
  returning a path. Deleting the copy afterward would not avoid the write.
- iOS `file_selector_ios` 0.5.3+7 constructs
  `UIDocumentPickerViewController(..., asCopy: true)`; the exposed API has no
  read-in-place option.
- Linux `file_selector_linux` 0.9.4+1 links GTK, incompatible with the
  designed GTK-free Linux Flutter host.

The umbrella candidate was resolved separately (not adopted); its materialized
resolution is receipt `79146132bfd34463a71264fdecd19c01` and locked offline
resolution evidence `4b8953fcc80e42adb20c2fc3e00ba755`. Its archive hashes and
source-file hashes are recorded in the following provenance table. The mobile
adapter reads the granted document handle directly into memory; it is separate
from encrypted save/reopen or SQLCipher.

## Mobile read-in-place adapter

`TextImportPlugin.kt` registers with the Android Flutter engine and implements
`ActivityAware`/activity-result handling. `TextImportPlugin.swift` registers with
the iOS implicit engine registrar and presents through the active scene, never
`AppDelegate.window.rootViewController`. The activity's pause/resume privacy flags
and scene's inactive cover remain unchanged.

The app-owned `org.kotoha/text_import` channel accepts `open` and returns only a
display name and typed bytes, null on cancellation, or a generic error without
selected locations. `text_document_picker.dart` checks the response shape and
feeds the same `_importSource` validation, consent and edit-race handling as the
desktop picker; language and translation controllers remain untouched. The
mobile response is an in-memory document, not a provider URL wrapped in a Dart
`File`/`XFile`. Desktop selection still uses its existing deferred `XFile` read.
Native code must also check the name before reading unsupported content. Picker
filters are advisory: MIME/UTI mappings differ across Markdown providers, so a
filter must not be the only acceptance check.

| Platform | Implemented read path | Resource lifetime and exclusions |
| --- | --- | --- |
| Android | `ACTION_OPEN_DOCUMENT` with `CATEGORY_OPENABLE`, single selection; query `OpenableColumns.DISPLAY_NAME`, then read the granted URI with `ContentResolver.openInputStream` into memory. | Close the query cursor and input stream on success and failure. Do not call `takePersistableUriPermission`, request broad storage access, derive a real path, or create an app cache file. Keep the URI only for the active request. |
| iOS | `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)`, single selection; acquire security-scoped access and coordinate a read using `NSFileCoordinator`, then `Data(contentsOf:)` inside its accessor. | Balance successful `startAccessingSecurityScopedResource` with `stopAccessingSecurityScopedResource` after the read, including failures. An unsuccessful start is not by itself proof that a local URL is unreadable; the coordinated read must report its actual result. Do not create a bookmark, copy the URL to the sandbox, or retain the selected URL after completion. |

The adapters read provider bytes away from the UI thread and deliver a single terminal result
on the platform thread. One pending picker/read per engine is sufficient; reject
a concurrent request rather than overwriting its completion. Release pending
callbacks and picker delegates on completion, cancellation, read failure and
engine/activity detach. A late result after detach must not reach a new request;
retain only its in-memory request-code tombstone until that result is consumed.
Activity/process recreation does not restore a draft or import: fail or discard
the interrupted request, never persist a callback, URI, bytes or text for recovery.
No retry loop, timer, history, background import service or persistence layer is
needed for this one-shot operation.

This limits **Kotoha's own writes**, not an OS/provider's implementation. A document
provider may download or stage a file even for an in-place read. Neither Android
`openInputStream` nor iOS `asCopy: false` proves that every selectable document is
already offline or that the OS never writes it. No app network client is needed.
The adapter uses platform-provided Android framework and Apple UIKit/Foundation
APIs, not an additional redistributed picker library; it does not resolve or
change the separate SQLCipher/persistence dependency decision.

### Mobile validation boundary

The following native regressions are included in the existing CI test targets,
but have **not been compiled or run in this sandbox**:

- Android `TextImportTest` uses a pipe-backed test provider through
  `ContentResolver`, checking exact selected bytes/name, unsupported/missing
  names, open/read errors and cursor/stream closure. A local provider transport
  exposes resource counters; a test-APK provider exercises real activity-result
  dispatch using synthetic intercepted picker results. Tests cover cancellation,
  busy requests, engine detach and a fresh request afterward. They do not prove
  live DocumentsUI selection, real provider grant behavior, or offline availability.
- iOS `RunnerTests` checks open-not-copy picker configuration, single selection,
  active-scene presentation through the implicit engine's registered plugin,
  delegate selection/cancellation/errors, busy requests and detach. Injected
  system operations check balanced scope release for success/error and both scope
  start outcomes. A synthetic temporary local file separately exercises actual
  Foundation coordination and `Data`; it is not a security-scoped provider test.
  XCUI additionally exercises the real Dart channel's system picker presentation
  and repeated cancellation with an unsaved draft. Presentation uses a form sheet
  rather than a popover; physical iPads and external-provider selections remain
  unverified, as does all native execution until hosted results arrive.
- Dart mobile-channel tests cover malformed channel replies, strict UTF-8/BOM,
  advisory extension rejection, native errors, cancellation, replacement consent,
  source edits during read/confirmation (including undo), translation/language
  preservation and lifecycle continuity. Desktop integrity tests remain in place.
  Native privacy/RTL tests remain selected in CI. Android checks native labels,
  values and synthesized input after direction changes; Flutter widget tests own
  complete forward/reverse traversal, including the mobile import control.

Source review finds no import-path writes, cache staging, URI grant persistence,
bookmarks, selected-location history or network client. Worker reads release their
local URL/URI and bytes on completion; detach clears the callback immediately and
late worker results cannot satisfy another request. This is not a cancellation
guarantee for a provider's already-running blocking I/O. Unchanged cache-directory
contents alone would not exclude a transient OS/provider copy.

API references for implementation (not fetched or runtime-verified by this audit):
[Android document selection](https://developer.android.com/training/data-storage/shared/documents-files),
[`ContentResolver.openInputStream`](https://developer.android.com/reference/android/content/ContentResolver#openInputStream(android.net.Uri)),
[Apple document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller),
[Apple file coordination](https://developer.apple.com/documentation/foundation/nsfilecoordinator).
The current sandbox has Flutter artifacts but no Android SDK/Java toolchain or
Xcode/Apple SDK. Mobile compilation, OS picker interaction and provider behavior
therefore remain unverified; the configured hosted mobile profiles are the next
execution boundary, not evidence already obtained.

## Memory profile (sandbox-only, no limit selected)

The current path materializes the whole selection: `readAsBytes` holds one
`Uint8List`, strict `utf8.decode` builds one `String` into the in-memory source
editor. There is no size guard, chunked transfer, or cache/persistence copy.

Sandbox-only Dart measurement on this Linux host (not device evidence,
experiment `f5c51d3fa13d438db0bcc057b5dbed2b`): fresh `dart` processes reading
synthetic multilingual UTF-8 files via `File.readAsBytes` plus
`utf8.decode(allowMalformed: false)` observed `VmHWM` increases of about
5,444 kB for a 2,097,160-byte file and about 17,372 kB for a 16,777,228-byte
file. This covers only Dart bytes plus the decoded string; it excludes native
provider copies, `MethodChannel` copies, OS staging, and editor retention, and
must not be used to choose a limit.

A separate Linux Flutter widget-test profile included Kotoha's actual import
button, strict decoder, source-controller update, and `TextField` layout, but
used a mocked `FileSelectorPlatform` returning an in-memory synthetic `XFile`;
it did not exercise the OS picker, filesystem `XFile` path, or native bridge.
With a repeated multilingual payload wrapped at roughly 1 KiB per line, the
test process `VmHWM` was 206,884 to 283,964 kB for 65,065 bytes (45,565
decoded code units), 210,200 to 499,604 kB for 261,261 bytes (182,961 code
units), and 206,600 to 2,506,536 kB for 2,097,095 bytes (1,468,595 code
units). The 16 MiB widget case did not complete; `flutter test` reported no
tests and exited 79 after 26 seconds, so its cause is unconfirmed. These are
Linux debug test-process peaks, not target-device memory results; framework and
text-layout costs are included, and native/provider/MethodChannel copies are
excluded (commands `73fa355f39614b37874f57bccb53d084` and
`43f3c85869f3474b81b0a5c870702801`). They show the full widget path can greatly
exceed the decode-only measurement, but are not a basis for a shipping limit.

A matched controller-assignment control used the same widget-test harness,
text payloads, and `TextField`, but bypassed `FileSelectorPlatform` and directly
decoded then assigned the same source text. `VmHWM` rose by 74,148 kB for the
65,065-byte import versus 68,216 kB for direct assignment, and by 288,064 kB
for the 261,261-byte import versus 282,100 kB for direct assignment (command
`21ca1a919b2e486787914cc0d76275ca`). The similar peaks suggest the Linux debug
widget/editor path, not picker/reader overhead, dominates these small local
profiles. This does not predict release or mobile behavior, nor justify a size
limit; native target measurements are still required.

### Opt-in hosted stage harness

Manual `CI` dispatch accepts `profile_bytes` (empty by default: no profile).
Only `65536`, `2097152`, and `16777216` are accepted; each stage rounds down to
complete 1,021-byte synthetic lines (1,000 ASCII letters, Japanese/Arabic text,
newline), and reports actual bytes. The 16 MiB ceiling is a profiling-fixture
bound, not an application import limit. The optional editor trial rejects 16
MiB because the earlier sandbox widget run did not complete and the sampled RSS
watchdog is not a hard allocation limit; start with 64 KiB and review its
headroom before opting into 2 MiB. Dispatch a fresh run for each size so peaks
do not carry across sizes. These are debug test profiles, not release/device
benchmarks.

- Android `TextImportTest.testOptInNativeReadMemoryProfile` calls production
  `readDocument` through `ContentResolver` and a pipe-backed test-APK provider.
  Logcat emits `KotohaImportProfile` with API version, elapsed nanoseconds,
  bytes and before/after `VmRSS`/`VmHWM` (kB). The provider streams bounded
  chunks. The existing emulator and test timeout apply; profile logs are printed
  even on instrumentation failure.
- iOS `RunnerTests.testOptInNativeReadMemoryProfile` creates a synthetic local
  file in chunks, then calls production `TextDocumentReader` with real Foundation
  coordination/loading. XCTest logs include OS version, elapsed seconds, bytes
  and before/after process `ru_maxrss` (bytes on Darwin). The fixture is removed
  with `defer`. The Debug setting is empty by default; the scheme passes the CI
  build setting into tests. This is not an external-provider/scope measurement.
- macOS and Windows run `tools/profile_text_import_test.dart` in fresh Flutter
  test processes for disk `XFile.readAsBytes` plus strict UTF-8 decode. JSON
  records OS/Dart runtime, bytes, code units, elapsed microseconds, current RSS
  and process high-water RSS (memory values in bytes). This is the desktop
  filesystem reader, not an OS picker. Its decoder expression matches the app;
  the decode-only stage does not execute the app import handler.
- `profile_editor=true` additionally runs the actual app import handler,
  controller assignment and `TextField` layout on the macOS hosted test runner.
  Only selection is substituted; bytes come from the synthetic disk file. The
  handler runs in the real async zone rather than via pointer interaction.
  The harness explicitly selects desktop widget behavior (widget tests otherwise
  default to Android). Windows editor and mobile Dart/editor profiles are absent.

Editor trials go through `tools/watch_import_profile.py` and accept only
profile sizes up to 2 MiB. Dispatch settings expose wall time
(`profile_seconds=60`, maximum 120), sampled process-group RSS ceiling
(`profile_rss_mib=4096`, maximum 4096 MiB) and sample interval
(`profile_poll_seconds=0.5`, constrained to 0.05–0.5). These are experiment
safety policies, not app import limits. The watchdog includes
compiler/Flutter children, kills the child process group and reaps its leader
on budget breach
(exit 124) or SIGINT/SIGTERM (128+signal), and removes its owned temporary
directory on completion, stop, or cancellation. Process sampling timeouts and
poll sleeps are clipped to the remaining wall budget. This is best-effort rather
than hard real-time: scheduler/teardown latency can add time, and SIGKILL cannot
be intercepted. Its sampled group peak is a safety estimate, not a process
high-water metric; short peaks can be missed. The CI step's five-minute outer
timeout is separate.
No large editor trial runs on the shared sandbox. Small local smoke command:

```sh
python3 tools/watch_import_profile.py --seconds 45 --rss-mib 1536 --poll-seconds 0.2 -- \
  flutter test --no-pub tools/profile_text_import_test.dart \
  --dart-define=PROFILE_BYTES=8192 --dart-define=PROFILE_STAGE=editor
```

Local harness validation only: 8,168 bytes / 8,080 code units completed in both
stages on Linux. Editor/decode smoke, wall-time clipping, SIGTERM child
termination and fixture cleanup, RSS stop behavior, design validation (93/93),
and all four watchdog tests passed (`df4421713bce4466b30c0bb5f052ee21`).
These are not supported-platform memory evidence. A 768 MiB group budget
stopped startup before measurement (`dfdf508b3eb542b4a1e53d4ab107f856`),
demonstrating that the budget includes compilation, not only editor memory.

All stage peaks are process-wide and may include startup, fixture preparation,
framework work and unrelated allocations. Zero peak delta does not mean zero
allocation. Do not add/subtract separate stage peaks to infer bridge copies.
Native stages stop before MethodChannel serialization. Native-to-Dart transfer,
provider failures under pressure, picker/provider allocations, physical devices
and release-mode editors remain unmeasured. Keep the memory work item open until
hosted observations cover the needed path. No size cap, chunked import
implementation, cache copy or draft persistence is introduced by this harness.

Failure behavior is fail-closed: strict decoding throws `FormatException` on
malformed input, the UI shows only a generic notice and preserves source,
language and translation state (covered by existing desktop/mobile widget
tests). Large-file out-of-memory behavior on constrained targets is unmeasured.

No limit or incremental transfer is selected. Any future guard must be
configuration with hosted-profile evidence, preserve drafts on error, and keep
read-in-place access with no persistence or cache copy.

The smallest hosted measurement still needed, per supported profile
(macOS/Windows and Android Emulator/iOS Simulator CI), is: import synthetic
2 MiB and 16 MiB UTF-8 `.txt`/`.md` files through the exact shipped picker
path, record native peak plus Dart peak and success/failure with draft
preservation. No product telemetry is added for this one-shot check.

## Hosted validation and remaining claims

Desktop widget tests use a fake `FileSelectorPlatform` for cancellation,
multilingual import, malformed UTF-8, unsupported extensions, read/picker errors,
replacement consent, source-change races, and preservation of source language
and translation fields. They exercise app logic and filter arguments, not a live
OS dialog. The Android and iOS native tests above are selected in CI but have not
been compiled or run in this sandbox. Hosted CI must build the exact published
revision and run its platform tests before acceptance; no claim is made that a
real external provider selection or physical-device behavior has been observed.

## Rejected umbrella candidate provenance

The separately materialized `file_selector` 1.1.0 candidate was never added to
the application manifest or lockfile. Its exact archive and platform package
archive SHA-256 values were:

| Package (candidate version) | Archive SHA-256 |
| --- | --- |
| `file_selector` 1.1.0 | `bd15e43e9268db636b53eeaca9f56324d1622af30e5c34d6e267649758c84d9a` |
| `file_selector_android` 0.5.2+11 | `d670cd0ce77a2e785b18d8b4d0a8d6a222d6a813ec9b7ddf2790a1b4fb6fa92c` |
| `file_selector_ios` 0.5.3+7 | `5b42ec0ef7626124b4624ea244341e9df780406793c204e89fa68a2e71af115c` |
| `file_selector_linux` 0.9.4+1 | `da76400e7872ce7637ffdce12749ec24169c25f6195c28372208e65a24bcd2ab` |

The inspected files and SHA-256 values (relative to their package roots) were:

| File | SHA-256 |
| --- | --- |
| Android `android/src/main/java/dev/flutter/packages/file_selector_android/FileSelectorApiImpl.java` | `a178ba326be5417225dcf1ce7445b328c8ce320e50b82b603679baf5b0b5d827` |
| Android `android/src/main/java/dev/flutter/packages/file_selector_android/FileUtils.java` | `916853194111bb06955f8f34e10e31ee45389b63eced204227114a282199e696` |
| iOS `ios/file_selector_ios/Sources/file_selector_ios/FileSelectorPlugin.swift` | `269087f6f93693954fbf9f903b761d1dd6a8dc6e6acfee6a2f970052eaedf54e` |
| Linux `linux/CMakeLists.txt` | `2117e1a092ba2823b3143fdd38733af6a1e006dfa7105a4bfae9d990ac483420` |

The prior source inspection records are `daf2ae0ebd9545b186081878dafc3e6d`,
`70a3ea08a6fc4ab183b7fa49ff4003f7`, and `5669a26cae494729a1a06e3dade9cc14`.
The desktop-source file hashes above come from exact package tags; the package
archive SHA-256 values in the selected-dependency table bind the implemented
versions.
