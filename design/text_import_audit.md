# Memory-only plain-text and Markdown import

Kotoha now offers a user-triggered import on the currently scaffolded macOS and
Windows desktop targets. The selected content is decoded into the source editor
in memory and can then be edited manually; existing translation fields and the
copy action remain unchanged. No model inference, network client call, selected
path retention, cache copy, or draft persistence is part of this workflow. The
user's original file remains outside this guarantee.

Mobile import is intentionally separate: the audited umbrella `file_selector`
uses an Android cache copy and iOS `asCopy: true`. Linux remains separate
because the project's designed Linux Flutter host must avoid GTK, while
`file_selector_linux` links GTK. These platform decisions do not block the
macOS/Windows slice.

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

- The app passes only `.txt`, `.md`, and `.markdown` extensions (plus the
  recognized plain-text and Markdown UTIs) to the picker and independently
  validates the returned filename before reading. It strictly decodes UTF-8,
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
source-file hashes are recorded in the following provenance table. Mobile still
needs an OS adapter that reads the granted document handle directly into
memory; it is separate from encrypted save/reopen or SQLCipher.

## Validation boundaries

Focused widget tests use a fake `FileSelectorPlatform` for cancellation,
multilingual import, malformed UTF-8, unsupported extensions, read/picker
errors, replacement consent, source-change races, and preservation of source
language and translation fields. They exercise the app's import logic and
filter arguments; they do not exercise a live OS dialog. Hosted CI must build
macOS and Windows from the exact published revision. No claim is made here
that an actual native picker selection/cancellation has been manually observed.


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
