# Memory-only plain-text and Markdown import

Kotoha implements user-triggered import on macOS, Windows, Android and iOS.
Hosted CI for code SHA `a76efcb9b0f75637bae608bfb2a761d97ca02247` passed all five
required checks, including Android Emulator import coverage and iOS Simulator
tests/builds. This evidence covers configured tests, not live provider-selected
reads, physical devices or offline availability; the local sandbox lacks native
mobile SDKs, so its Dart tests are not mobile runtime evidence.

The selected content is decoded into the source editor in memory and can then be
edited manually; existing translation fields and the copy action remain
unchanged. No model inference, network client call, selected path retention, cache
copy, or draft persistence is part of this workflow. The user's original file
remains outside this guarantee.

The audited umbrella `file_selector` uses an Android cache copy and iOS
`asCopy: true`; the app-owned mobile adapter below replaces those paths rather
than attempting to delete copies afterward. No mobile dependency is added.
Linux remains separate because `file_selector_linux` links GTK and Kotoha has
no adopted Linux runner, packaging target, or import adapter. Flutter's
engine-level embedder API is toolkit-agnostic, but is not itself a complete
Linux host. This does not block the macOS/Windows slice.

## GTK-free Linux host candidate (not adopted)

A concrete upstream candidate beyond a bare custom embedder is Toyota Connected's
`ivi-homescreen` v3.0 at commit
`05fb91a0d0e09cd0fb099299dcf2202e1a4d21e4`. Its project documentation describes
Wayland/EGL desktop support (including Ubuntu 22.04), C++ Flutter embedding,
and optional AccessKit semantics exposed to screen readers over AT-SPI. Its
`LICENSE` declares Apache-2.0. The `.flutter-version` in this exact source is
3.47.2, while Kotoha CI pins Flutter 3.47.9; compatibility with Kotoha's patch
version has not been tested. The candidate is not a Kotoha-supported runner.

The accessibility path has a privacy-sensitive disk write: `BUILD_ACCESSIBILITY`
and `BUILD_ACCESSKIT` are off by default, but enabling the semantics tree writes
one `semantic_tree_init.json` snapshot under the user's config `accessibility`
directory when the first root arrives. It serializes node labels, hints,
tooltips, and values. This is an initial snapshot, not a per-edit journal, but
the inspected path neither redacts text nor offers an opt-out; if the first tree
arrives after text is present, it can persist editor content. Kotoha has not
verified that lifecycle ordering. Treat this as an adoption blocker until a
reviewed change disables the file write without disabling AT-SPI semantics.
Evidence: CMake feature gates (`fetch/0b8652a95977fcd04e28728741133ca12ebc755f046ac9cdd2f59101f146c766`) and
exact accessibility tree source (`fetch/6cf2cfba15a4604a7773c9951b5eaa4cf2d5c5321b91b1da6a00aa316530147a`).

The upstream workflow has CMake build/CTest jobs on Ubuntu 22.04 for
`BUILD_ACCESSIBILITY=ON` and `BUILD_ACCESSKIT=ON`; the AccessKit job selects
`accesskit-c` 0.22.3. The workflow recipe is evidence of a build path, not an
observed green run for Kotoha or this source revision. The candidate has ten
source submodules; its CI generates a CycloneDX/OpenVEX SBOM for those pinned
submodules. The desktop workflow also installs Wayland, xkbcommon, pugixml, and
Mesa/EGL/GLES development packages. The AccessKit job fetches a separately
distributed x86_64 static-library archive by version but does not check its
content digest; the `.emb` configuration notes that other board builds compile
AccessKit from Rust source. We have not reviewed a generated SBOM artifact or
verified full license texts/notices for the candidate build and its system
runtime. Nor have we reproduced the build here, linked a Kotoha bundle,
exercised text input and screen-reader actions, or established a Kotoha Linux
CI path. No GTK-free Kotoha build or runtime support is therefore claimed.
Source evidence: commit/tag (`fetch/9acf96562b48a053af92363964d6d60d73c514c9bd07b6a032d1f92c922d7271`),
README (`fetch/4f73e95eb0f48e7f1d98f0fb0ed676c6bb4bc6627e7a498bf3e4b49f72847ff2`),
architecture (`fetch/0f37147b15dc9ef0a6b37704f86a54b9e157a3d6ae415b4464a7fd8c3107c907`),
`.flutter-version` (`fetch/c9eebb962457ca2236d8d1972376f8ba7abdce7342ef22daeba4b7cfba0a20d3`),
`LICENSE` (`fetch/8f355051b6bbe0fa649596835abe1c1030345c2468841c6fa5df4e638c61dbcf`),
CI workflow (`fetch/e90d1c962ac422caf1e23688da294fedea65b0468273f99a8978ca97cdc8a26b`),
SBOM generator (`fetch/aad6b217e2daf9751a14f75ffe0aa68f11ac4fd64c4596a1756c2c8f8abfe4b7`),
`.emb` build manifest (`fetch/d99c22e5ef246980c29530e770c27c65f35cf4c44ee26e077307203d6c6e348d`),
and submodule list (`fetch/18ab6880a998d3fe1ac8fd9d1fa1e8f011ddf04096b6b3e6d45dc1d2e92379d2`).
Flutter's generic embedder C API and Linux GTK `FlView` are distinct
(`273690fb58153d725062db635bc7357e20a18da1e26cb9862181b69ebb2a1cef`,
`aa721ddb2009177bc3f918b7b31c7288f017cf3e929376b87cc957f5b13cef4f`).

Kotoha has no Linux picker registered or exposed in the UI. `lib/main.dart`
shows the import action only on macOS, Windows, Android, and iOS. The picker
routes Android/iOS through Kotoha's `org.kotoha/text_import` channel and routes
other targets through `FileSelectorPlatform.openFile`; `pubspec.yaml` declares
only the macOS and Windows selector implementations plus their shared interface.
A future Linux UI would therefore need a Linux implementation registered for
that platform interface, not just an embedder. Kotoha's explicit export action
is also limited to macOS/Windows.

The candidate's documented plugin surfaces do not supply that adapter.
`docs/PLUGIN_ABI.md` describes `ihs_shared` as a C ABI for logging, tracing,
surface negotiation, and configuration; it explicitly does not provide a
Flutter registrar or messenger. The document identifies the separate
`FlutterDesktopPluginRegistrar`/messenger surface for in-tree or statically
registered Flutter plugins. The public `flutter_homescreen.h` declares a
registrar lookup by engine and unique plugin name and includes the messenger
and registrar headers. This is a host API a future Kotoha plugin would need to
integrate with, not a ready Kotoha file-picker implementation; no compatible
Linux `FileSelectorPlatform` implementation or `org.kotoha/text_import`
handler has been verified. Its `.emb` manifest sets
`DISABLE_PLUGINS=ON`. At this exact source, `cmake/options.cmake` maps that to
`ENABLE_PLUGINS=OFF`, and the root `CMakeLists.txt` skips the configured
`PLUGINS_DIR` and `EXT_PLUGINS_DIRS`; the core homescreen host is still added.
Thus the manifest does not demonstrate a Kotoha picker or plugin path. A Linux
target would need an explicit plugin-enabled build configuration, a separately
reviewed non-GTK adapter, and a demonstrated registration and method-channel
path before any import action is exposed.

The XDG portal candidate below remains unverified and is not enabled. Source
references: Kotoha `lib/main.dart`, `lib/text_document_picker.dart`, and
`pubspec.yaml`; candidate architecture (`fetch/0f37147b15dc9ef0a6b37704f86a54b9e157a3d6ae415b4464a7fd8c3107c907`),
plugin ABI at exact v3.0 commit (`fetch/d7f24b683aef2ad815e1aee8a706ccb23e8d607e2f0fcef5d5c1bbb0195237e5`),
public host plugin header (`fetch/58aa7945afabd0ee0c21d51bc2bfa1a002f18f339301998ea4679b379bed3dc7`),
root CMake plugin dispatch (`fetch/2f3df394cd29553a3d95c3fd3cefe0098c647951b12497a733508a9373b0d2ce`),
`cmake/options.cmake` (`fetch/67049d4213f4c819ae92a1bb80a2d4edc6ed62e9c2a09fc01cc172861209aaf3`),
and `.emb` build manifest (`fetch/d99c22e5ef246980c29530e770c27c65f35cf4c44ee26e077307203d6c6e348d`).

### Alternative GTK-free host: Sony eLinux embedder (not adopted)

A second concrete candidate is Sony's `flutter-embedded-linux` at repository
revision `1653fa656bf9fe9fa5f84789a59b0c07671a8fc8` (the GitHub commit record
dates it 2025-05-09). The README explicitly calls it a non-official,
embedded-Linux-focused Flutter embedder, separate from the `flutter-elinux`
SDK extension and `flutter-elinux-plugins`. It claims x64 and ARM64 support
with Wayland or DRM backends; the support-status page lists x86_64 Ubuntu 20.04
tests on Wayland, DRM, and X11. Its CMake also exposes Wayland, DRM-GBM,
DRM-EGLStream, and X11 backend choices. The project describes a single-window,
full-screen default (with flexible sizing on Wayland/X11). Its plugin API wiki
lists Flutter channels, `BinaryMessenger`, `PluginRegistrar`, and
`TextureRegistrar`; this is a plausible GTK-free engine host path, not proof of
a Kotoha runner or import plugin. The exact repository `LICENSE` is BSD-3-Clause,
whose terms fit the permissive dependency category.

The exact repository's `build-test.yml` installs system packages and downloads
`elinux-x64-release.zip` through a floating GitHub `releases/latest` URL without
verifying a content digest. That recipe is not a pinned engine/toolchain input
or a reproducible Kotoha build. The companion SDK and plugin repositories,
feature-resolved dependency/license closure, platform runtime, and compatibility
with Kotoha's pinned Flutter 3.47.9 have not been reviewed or tested. No
Kotoha Linux plugin registration, read-in-place portal adapter, privacy or
accessibility behavior, or supported CI path is demonstrated. Keep Linux
unscaffolded; compare this candidate with the designed Engine + SDL/AccessKit
host only after obtaining pinned artifacts, complete license/runtime closure,
and reproducible integration evidence.

Source evidence: repository commit record (`fetch/051309ebd8c3f99d38d6d605423dc43e695f7636482658a3ca40d979a8ef6b59`),
README (`fetch/ab8865016d89ecefb9ae9bf3f230ec947f61b2bd4fe6ff476af68b3844194736`),
exact BSD-3-Clause license (`fetch/69ff4894b1d51fc31050194608f699095837950ab93942a945da719555958e6e`),
support matrix (`fetch/4e8ae1865a278105efc7569776eff511581deb4582cd3376b9263f45b6148c64`),
plugin API wiki (`fetch/7898c6750057c6da88a0bcb4c336535966a640d317009ca6c33fe797ffd46d7e`),
CMake (`fetch/54004f08dd017d99ae937300f3dd48a8912b8cdfcba78033661dcec59e45e0db`),
and build workflow (`fetch/ec8059f79fdfe7b09be58161b097cca16d889ee472a8c261e01f87bdcce60f9b`).

## GTK-free Linux portal candidate (not adopted)

The repository intentionally has no Linux Flutter runner until the designed
non-GTK host embedding exists. `ashpd` 0.14.0 exposes `file_chooser` as an
opt-in feature: its manifest enables `serde_repr` for that feature, with Tokio
defaulted; GTK, GDK, GLib, Wayland and PipeWire integrations are separate
optional features. Its `SelectedFiles::uris()` API returns URIs, not file bytes.
This is only evidence that a GTK-free feature selection may be possible; the
complete resolved dependency/license closure, GTK-free build/link, and Flutter
host bridge have not been verified. A bounded local probe found no Cargo
executable (`experiments/c69b0215c0024aabac474640e132a9b6.json`), so no local
feature-resolved build was possible. The full `ashpd` MIT license was inspected,
but that does not establish the licenses of its transitive dependencies.

The XDG FileChooser portal has different behavior for host and sandboxed apps.
Its specification says selected files may be added to the Documents portal and
that such entries remain accessible across sessions. FileChooser OpenFile
offers no ephemeral-permission option; see XDG FileChooser search evidence
`search-abbf315cb6271eb8b0de05cd0394af8f4ce8aaae5062a86a93bb7a9168147cf2`.
The inspected
`xdg-desktop-portal` source at commit `e3ca5567a2dbb5b763a383bba5ff1c0437a7e851`
sets `DOCUMENT_ADD_FLAGS_PERSISTENT` and grants `read` and
`grant-permissions` (plus optional `write`), not `delete`, when registering a
selected file (`fetch/85c46777ca08db4548c9cbb7f50dc4c53fd5cd5ff697d1521506292a10bb4d35`,
SHA-256 `f5f10316ae0d059c41465d0e32a70e3695d0a32f60d157b950d3b3610edaa7fb`).
`ashpd` exposes `Documents::delete` as a separate API
(`fetch/b546771bd6472d409f2b4d2dd9636ba33baf122c68f00d0a4fd58be4d45c8a97`),
but the FileChooser registration path grants no `delete` permission. That
alone does not establish that the app must retain its read access: the XDG
Documents API defines `RevokePermissions`, available inside the sandbox when
the app has `grant-permissions`, and specifies that it revokes listed
permissions for an application (`search/16eee028f3c1a576da38435f7ac5da4a3ece6f3282eadb6132ee733108aa6823`).
`ashpd` 0.14.0 likewise exposes `Documents::revoke_permissions` under that
permission (`search/8fb9e29428f55a95b0b7e0b3d2c5de46f70b44586b1b28246a4d6cb2c5b8ad06`).
Because FileChooser grants `grant-permissions`, a GTK-free sandboxed client
may be able to revoke its own `read` and `grant-permissions` access after
reading. This is an API-supported candidate, not verified Kotoha behavior:
mapping the returned URI to a document ID and exact application ID, successful
revocation on supported portal implementations, and loss of access after open
handles close have not been tested.

The FileChooser registration path also requests a persistent Documents entry.
`RevokePermissions` revokes listed app permissions; it is distinct from
`Delete`, and available evidence does not establish that revocation removes the
persistent document-store entry. The sandboxed path is therefore not approved,
but it is not ruled out solely by the missing `delete` permission. End-to-end
runtime evidence must establish both the no-retained-grant behavior and what
portal state remains before Linux import can be considered.

For a host app, the portal source returns the original URI without registering
a Documents entry (`fetch/fe26d14e6343f3a082b87a702d4660e52bac909f01a47aee86a2cc827760b711`,
SHA-256 `a2e3a1251dfbc22dedffce3e3d5112ae0f28004615893410cc3f658a6539c5ca`),
but Kotoha has no Linux host or packaging target to validate that mode.

Linux import remains unsupported. Reconsider only after an explicit product
Linux target adopts a pinned GTK-free host, its complete feature-resolved
license/runtime closure and reproducible Kotoha build/link/CI path are verified,
and a supported import adapter demonstrates its data-flow and permission
lifecycle end to end. The `ivi-homescreen` source and upstream build recipe are
candidates for that assessment, not approval or evidence of Kotoha support.
Evidence for the candidate client manifest/license is in fetch receipts
`21e23ad1cc93bca164f2c1d05eb31ba282f4fe6d348a54c0725ed20a7d79947e` and
`7c3d54f818e5e021d4dee59d8897a4e6e4d4c91aeda61ed40bdf066fd8359b13`
(SHA-256 `ae26bc7b1bc91fb8648f6a298decbb1a77090a56c9d04e2c23b8365e5f54acb5`);
the
`SelectedFiles::uris()` API is documented in search receipt
`38caafccf3bfe978ddeff875b3c0553feaa417c95f8b8ef83ebb2102bfb2ae93`.

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
  or write a cache file. DebugProfile and Release declare
  `com.apple.security.files.user-selected.read-write` for the separate explicit
  translation-export save panel; import still reads the selected input only, and
  export writes only to the user-selected target.
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

The following native regressions are included in existing CI targets and were
exercised on the hosted code SHA above. This local sandbox lacks Android SDK/Java
and Xcode/Apple SDK, so this audit did not compile or execute them locally:

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
  rather than a popover; hosted simulator coverage does not establish physical
  iPads or external-provider reads.
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
The local sandbox has Flutter artifacts but no Android SDK/Java toolchain or
Xcode/Apple SDK, so it could not run the native compilation or simulator tests
itself. Hosted results above cover the configured test fixtures; real
provider-selected file reads and physical-device behavior remain unverified.

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

### Hosted profile workflow

`CI` workflow dispatch defaults to `profile_bytes=65536` and
`profile_editor=true`. An exact-publication VCS request carries no inputs and
therefore runs the 64 KiB profile; ordinary push/PR jobs skip all profile
stages. A direct GitHub workflow dispatch can clear `profile_bytes` to skip the
profile stages, or keep a size selected and set `profile_editor=false` to skip
only the macOS editor trial. The VCS request surface cannot override these
defaults.

Workflow validation accepts only `65536`, `2097152`, and `16777216`. The
synthetic fixture repeats an exact 1,024-byte UTF-8 line (1,003 ASCII `a`
bytes plus Japanese/Arabic text and newline), so each supported profile size is
exact; the test rejects a request that would otherwise require rounding. For a
nonempty size, Android and iOS jobs include native reader profiles, macOS and
Windows run desktop decode profiles, and `profile_editor=true` adds the macOS
editor stage. The 16 MiB ceiling is a profiling-fixture bound, not an
application import limit. The editor trial rejects 16 MiB because the earlier
sandbox widget run did not complete and the sampled RSS watchdog is not a hard
allocation limit. Dispatch a fresh run for each size so peaks do not carry
across sizes. These are debug test profiles, not release/device benchmarks.

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
  with `defer`. Outside profile dispatches the Debug setting is empty; the CI
  workflow passes its selected profile bytes through the scheme into tests.
  This is not an external-provider/scope measurement.
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

Local harness validation only: the exact 65,536-byte fixture completed both
decode and editor stages with 64,832 code units on Linux (commands
`232346d9c81941dd929e7c75c8e6cb85` and
`7b4a74c060944c9fbc49e47569fbeccf`). These debug runs validate fixture sizing
and stage execution, not supported-platform memory behavior. Editor/decode
smoke, wall-time clipping, SIGTERM child termination and fixture cleanup, RSS
stop behavior, design validation (93/93), and all four watchdog tests passed
(`df4421713bce4466b30c0bb5f052ee21`). A 768 MiB group budget stopped startup
before measurement (`dfdf508b3eb542b4a1e53d4ab107f856`), demonstrating that the
budget includes compilation, not only editor memory.

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
OS dialog. The Android and iOS native tests above passed on exact hosted code SHA
`a76efcb9b0f75637bae608bfb2a761d97ca02247`, alongside all five required CI
checks. Those tests cover the documented emulator/simulator fixtures, not live
provider-selected content or physical devices; every later revision still needs
its own exact hosted validation.

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
