# Memory-only plain-text and Markdown import

Kotoha implements user-triggered import on macOS, Windows, Android and iOS.
The hosted iOS simulator check on SHA
`a079cda9db05bb5dcac9bb8e90f85dee5c23bcc3` passed 4 RunnerTests and 5 UI tests.
`Cancel` was found and tapped twice in
`testImportChannelPresentsSystemPickerAndCancellationKeepsDraft`; this was a
non-reproduction of the original timeout on SHA
`4d3256d260b32a876a4a5ff687698a48d2b0e312`, whose failure hierarchy and `.xcresult`
remain unavailable. On a later SHA, `548c92ba16fbd85c446e17059fc1fa093a87d4a0`,
Android passed 20 connected instrumentation tests, but the iOS check failed.
The same iOS picker test tapped `Cancel` after two Import requests; afterward
the existing `source-text` lookup did not resolve before the test's 2-minute
execution allowance expired. The CI action then timed out after 15 minutes;
the job log records no accessibility hierarchy contents, and the exact-SHA
artifact listing contains the job log but no `.xcresult`. This failure is a
recurrence, not a pass or an explanation of the original. The separate macOS
and Linux checks also failed on those aggregate runs and failed again on SHA
`78d0bc90d5124dbf3413597114447179cc06ac62`; the mobile results do not make the
aggregate workflows green.

On SHA `78d0bc90d5124dbf3413597114447179cc06ac62`, the iOS simulator check
passed all five accessibility UI tests. The picker test found and tapped Cancel
twice and the direct `source-text` lookup succeeded after each cancellation;
that test passed in 22.777 seconds, with all five UI tests passing in 148.153
seconds. This is another non-reproduction and does not explain the previous
two-minute timeout. The current source change conditionally calls
`reveal("source-text")` only when the node is absent after cancellation
(`d8ddc54`), preserving the exact draft assertion and deadline. The iOS
simulator check on SHA `8f6ea2aba0b2e4a7fc0d4cd4bf8ddc5f747acee3` passed 4
RunnerTests and all 5 accessibility UI tests. The picker test tapped Cancel
after both presentations and its post-cancellation `source-text` queries
succeeded; the log does not establish whether the conditional reveal branch ran.
This is another non-reproduction, not an explanation for the historical timeout.
Hosted simulator/emulator tests do not establish live provider-selected reads,
physical-device behavior, or offline availability; the local sandbox lacks
native mobile SDKs, so its Dart tests are not mobile runtime evidence.

The selected content is decoded into the source editor in memory and can then be
edited manually; existing translation fields and the copy action remain
unchanged. No model inference, network client call, selected path retention, cache
copy, or draft persistence is part of this workflow. The user's original file
remains outside this guarantee.

While Flutter reports the app as anything other than `resumed`, the editor
keeps draft controllers in memory but covers the workspace, absorbs pointer
input, intercepts bubbled hardware-key events, marks text fields read-only to
reject text-input edits, and excludes the covered workspace's semantics; the
localized cover appears instead. Flutter widget tests inject lifecycle, key,
and text-input events through the test binding and check the covered UI, draft
and selection preservation, rejected edits, and editing after resume. They do
not perform an operating-system background or task-switcher transition.

Android `MainActivityPrivacyTest` directly invokes pause/resume and checks the
`FLAG_SECURE` state. Its API 35 screenshot test draws a synthetic magenta marker
in the app window overlay, captures that window with `UiAutomation`, and checks
the marker is visible before pause, suppressed while the secure flag is set,
and visible after resume; the bitmap is recycled without persistence or logging.
The test invokes `onPause` while the app stays on screen, so it is a window
screenshot probe, not an OS-generated Recents thumbnail or task-switcher view.
On Android 13 (API 33) and newer, `MainActivity.onCreate` also calls
`setRecentsScreenshotEnabled(false)`, a version-guarded declarative request that
the system not use this activity's screenshot as its Recents representation.
It leaves screenshots during active use enabled and does not change the
pause/resume `FLAG_SECURE` behavior. The platform API has no public getter and
no CI path captures the OS-generated thumbnail, so its effect on real Recents
behavior is not observed here.
iOS `RunnerTests.testPrivacyCoverIsIdempotentAndLeavesContentAttached` directly
invokes scene callbacks and checks that an opaque cover is added/removed while
the content remains attached; it does not background the app or capture its
system snapshot.

On SHA `e681faf32f1fd8b2ed9c98c59adcb6977b65ccfa`, CI passed all 22 Android
API 35 emulator instrumentation tests; a later check on byte-identical app and
test source failed two Delete assertions (described in the native regression
discussion below), so this pass is not a durable closure. CI also passed all 4
iOS Runner tests plus 5 iOS Simulator UI tests. The Flutter format, analysis,
and widget-test check also passed. These results verify the named emulator,
simulator, and widget-test interactions on that revision only. Android
documents `FLAG_SECURE` as preventing secure-window content from appearing in
screenshots and non-secure displays; Apple's QA1838 advises obscuring sensitive
content before suspension to affect the saved app snapshot.
These are platform API documentation and guidance, not observations of Kotoha's
OS-generated task-switcher thumbnail. No CI path captures such a thumbnail,
and no physical-device or OEM behavior has been observed, so those behaviors
remain unverified. The platform references and release acceptance boundary are
in `design/kotoha_design.md` [S20]–[S22].

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
verified that lifecycle ordering. This blocks adoption until a reviewed
change disables the file write without disabling AT-SPI semantics. The
evidence comes from the CMake feature gates and the exact accessibility tree
source.

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
Source evidence: commit/tag, README, architecture, `.flutter-version`,
`LICENSE`, CI workflow, SBOM generator, `.emb` build manifest, and submodule
list.
Flutter's generic embedder C API and Linux GTK `FlView` are distinct.

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
`pubspec.yaml`; candidate architecture, plugin ABI at the exact v3.0 commit,
public host plugin header, root CMake plugin dispatch, `cmake/options.cmake`,
and `.emb` build manifest.

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
or a reproducible Kotoha build. A current-source check on 2026-11-07 found that
the upstream `master` ref still points to `1653fa656bf9fe9fa5f84789a59b0c07671a8fc8`,
dated 2025-05-09. Open PR #450, based on that exact master revision, proposes
adding direct `<cstdint>` includes to two client-wrapper headers because GCC 15
no longer accepts their transitive-include assumptions; its July 2026 head is
`4d3d077fc70afe6ebb879ceba7fe70e89b2e2aa4`. The associated workflow was
listed as awaiting maintainer approval; the commit checks API returned zero
check runs, and its status API returned `pending` with zero statuses. No
completed build result is evidenced. This indicates unresolved toolchain
compatibility in the candidate, not evidence that the proposed fix builds or
has merged.

The companion SDK and plugin repositories, feature-resolved dependency/license
closure, platform runtime, and compatibility with Kotoha's pinned Flutter 3.47.9
have not been reviewed or tested. No Kotoha Linux plugin registration,
read-in-place portal adapter, privacy or accessibility behavior, or supported
CI path is demonstrated. Linux remains unscaffolded. A comparison with the
designed Engine + SDL/AccessKit host requires pinned artifacts, complete
license/runtime closure, and reproducible integration evidence.

Source evidence: repository commit record, README, exact BSD-3-Clause license,
support matrix, plugin API wiki, CMake, and build workflow. Current upstream
evidence: `master` commit API and commit feed, current `master` build workflow,
PR #450 state/base/head, proposed client-wrapper headers, Actions approval
status, and the exact head's check/status APIs.

## GTK-free Linux portal candidate (not adopted)

The repository intentionally has no Linux Flutter runner until the designed
non-GTK host embedding exists. `ashpd` 0.14.0 exposes `file_chooser` as an
opt-in feature: its manifest enables `serde_repr` for that feature, with Tokio
defaulted; GTK, GDK, GLib, Wayland and PipeWire integrations are separate
optional features. Its `SelectedFiles::uris()` API returns URIs, not file bytes.
This is only evidence that a GTK-free feature selection may be possible; the
complete resolved dependency/license closure, GTK-free build/link, and Flutter
host bridge have not been verified. A bounded local probe found no Cargo
executable, so no local
feature-resolved build was possible. The full `ashpd` MIT license was inspected,
but that does not establish the licenses of its transitive dependencies.

The XDG FileChooser portal has different behavior for host and sandboxed apps.
Its specification says selected files may be added to the Documents portal and
that such entries remain accessible across sessions. FileChooser OpenFile
offers no ephemeral-permission option.
The inspected
`xdg-desktop-portal` source at commit `e3ca5567a2dbb5b763a383bba5ff1c0437a7e851`
sets `DOCUMENT_ADD_FLAGS_PERSISTENT` and grants `read` and
`grant-permissions` (plus optional `write`), not `delete`, when registering a
selected file (SHA-256 `f5f10316ae0d059c41465d0e32a70e3695d0a32f60d157b950d3b3610edaa7fb`).
`ashpd` exposes `Documents::delete` as a separate API,
but the FileChooser registration path grants no `delete` permission. That
alone does not establish that the app must retain its read access. The XDG
Documents API specification says `RevokePermissions` is available inside the
sandbox when the app has `grant-permissions` and describes revoking listed
permissions for an application.
`ashpd` 0.14.0 exposes the corresponding method,
but the method's existence does not establish that an app can revoke its own
grant. In upstream `xdg-desktop-portal` 1.14.4 and Ubuntu's `nmp-1.14-backport`,
`portal_revoke_permissions` explicitly rejects a request when the caller's app
ID equals the target app ID, returning `NotAllowed` even if the caller has
`grant-permissions`. The source files have identical SHA-256
`3d08cab5b8e769bdfc467964ce090116beb3602ac2078f6818fb872d4c9d61bf`.
The XDG FileChooser registration source passes the selected app ID to Documents
and grants it `read` and `grant-permissions`
(SHA-256 `f5f10316ae0d059c41465d0e32a70e3695d0a32f60d157b950d3b3610edaa7fb`).
Thus this pinned source predicts that a sandboxed client cannot revoke its own
permissions on that implementation. This is source evidence, not yet a binding
of the CI-installed binary to the source or a Kotoha runtime result.

The FileChooser registration path requests a persistent Documents entry.
`RevokePermissions` is distinct from `Delete`; FileChooser does not grant
`delete`, and the API's persistent entry is not removed by revoking app
permissions. On SHA `548c92ba16fbd85c446e17059fc1fa093a87d4a0`, the hosted probe
failed at `documents-fuse-mount-not-established` before the sandboxed client ran. The corrected probe decodes the
NUL-terminated `ay` path values for `GetMountPoint` and `Info`, seeds the mount
with a separate temporary entry before the chooser call, and constrains the
returned URI to `<doc-id>/<fixture-basename>`. It first exercises an other-app
grant/revoke control, then measures self-revocation, post-close access,
permissions, and record retention under a synthetic app ID. The selected source
encodes `Info` paths with `g_variant_new_bytestring`;
upstream Documents tests likewise strip the trailing NUL from path byte arrays
(SHA-256 `13244c64c2b060e7b6e4804c46f2b2c5d7e096301e12235486c245e72020a0de`).

The follow-up on SHA `78d0bc90d5124dbf3413597114447179cc06ac62` installed the same
Ubuntu 22.04.5 portal packages and failed as `sandbox-client-failed`. The probe
on SHA `8f6ea2aba0b2e4a7fc0d4cd4bf8ddc5f747acee3` installed
`xdg-desktop-portal` 1.14.4-1ubuntu2~22.04.2 and GTK backend 1.14.0-1build1;
the separate portal-session introspection exposed FileChooser v3 and Documents,
but the probe again failed only as `sandbox-client-failed`. Neither run exposes
an allowlisted client-stage result or establishes permission, post-close-access,
`Info`, or `List` behavior. The probe forwards only an exact
lowercase/digit/hyphen failure code bounded to 64 characters; raw child stderr,
paths, URI, and document contents remain suppressed. A startup sentinel is now
added to distinguish failure before the sandboxed Python client reaches `main`
from an unclassified client failure. The five-test stdlib suite covers exact
marker handling, bounded allowlisted codes, rejection of path-like,
malformed/out-of-window diagnostics, and startup-marker preservation after more
than 8 KiB of client warnings. The sentinel is searched in the complete captured
stderr, while failure-stage parsing remains limited to its bounded tail. It is
wired into CI. The hosted probe on SHA
`b4dcae7037afad94b3319ae5bc2a19593f109c34` used Ubuntu 22.04.5 x86_64,
`xdg-desktop-portal` 1.14.4-1ubuntu2~22.04.2, and GTK backend 1.14.0-1build1. The probe reported the allowlisted stage
`sandbox-client-launch-failed`. In the probe, this stage means the subprocess
exited nonzero without the sandboxed client's startup marker; it does not
identify whether bubblewrap setup or interpreter/import startup failed. The
sanitized log establishes no underlying cause. No chooser request, returned URI,
application/document identity mapping, permission
revocation, post-close access check, or persistent-state observation occurred.
Linux import remains disabled pending a runnable client and the supported
permission lifecycle.

The hosted Ubuntu portal probe on SHA `a079cda9db05bb5dcac9bb8e90f85dee5c23bcc3`
observed Ubuntu 22.04.5
x86_64/amd64, `xdg-desktop-portal` 1.14.4-1ubuntu2~22.04.2,
`xdg-desktop-portal-gtk` 1.14.0-1build1, `dbus-x11` 1.12.20-2ubuntu4.1, and
`xvfb` 2:21.1.4-2ubuntu1.7~22.04.16. The default portal exposed
`org.freedesktop.portal.FileChooser` v3 and the GTK backend exposed
`org.freedesktop.impl.portal.FileChooser`; both interface checks were reached.
The job failed afterward because its EXIT cleanup could not remove the private
`XDG_RUNTIME_DIR/doc` directory. The log does not establish whether that path
was mounted or why `rm` returned `EISDIR`; no chooser call, returned URI,
application/document identity mapping, revocation, post-close access, or
persistent-state observation occurred. The workflow now detects and unmounts
that path when it is a mountpoint before removing the private runtime directory.
The rerun on SHA `a3999abe6a35e37f481f31fc79f4d7b35a9c2c10` passed in CI. The log again shows the default
FileChooser v3 and GTK backend FileChooser interfaces; the successful job also
shows that its mount-aware EXIT cleanup completed. The recorded output does not
say whether `doc` was mounted or actually needed unmounting. No chooser request,
returned URI, application/document identity mapping, permission revocation,
post-close access check, or persistent-state observation occurred. This remains
interface-availability and cleanup evidence only, not portal behavior or
Kotoha support. Linux import remains disabled.

The hosted Ubuntu portal probe on SHA `fc81137061efe5b017c0fd049b43fd4ac2cad740`
ran on Ubuntu 22.04.5
x86_64/amd64 with bubblewrap `0.6.1-1ubuntu0.3`, Documents portal
`1.14.4-1ubuntu2~22.04.2`, and GTK backend `1.14.0-1build1`. Both the desktop
and GTK backend FileChooser interfaces introspected, but sandbox setup then
failed at `sandbox-bwrap-bind-file-target-failed`, before the client ran. No
FileChooser request, URI/document mapping, permission operation, post-close
access check, or persistent-state observation occurred; Linux import remains
disabled.

The earlier failure stage was the app-info data-bind to `/.flatpak-info`.
Pinned bubblewrap v0.6.1 source (SHA-256 `aaa4effa46873a7c7b6e6e9e8e7cdb91153ecd2c028dbeadd043166efdb9ea0c`)
shows that `--ro-bind-data` calls `ensure_file(dest)` before mounting and fails
if the destination cannot be created (lines 1418-1426). The original probe had
already made host `/` read-only, so that hosted failure occurred before the
client or any FileChooser request.

A later correction kept a writable bind of host `/` during setup. That design
was also invalid: a bind mount does not grant an unprivileged runner write
permission to root-owned host `/`, and a sufficiently privileged invocation
could leave `/.flatpak-info` on the host. The permission boundary was
reproduced in a user namespace. The current implementation instead starts with
a private `--tmpfs /`, binds only `/usr`, `/lib`, `/lib64`, and `/etc`
read-only, keeps `/run`, `/tmp`, and `/home` private, and exposes only the
probe's runtime directory and Documents mountpoint. App info and the script are
bound inside that private root; the base root is remounted read-only before the
client command. In bubblewrap v0.6.1, `setup_newroot()` resolves bind sources
under `/oldroot` and destinations under `/newroot` (source and destination
handling at lines 1151 and 1178); the tmpfs operation creates its new-root
destination before mounting it (lines 1327-1337). This avoids a host-root bind
and gives `--ro-bind-data` a private target.

The sandbox preflight runs `/usr/bin/true` and `/usr/bin/python3` from the
read-only `/usr` mount. Its first diagnostic stage groups the tmpfs root with
`/usr`, `/lib`, `/lib64`, and `/etc`, so it does not test an executable before
its binary and runtime are visible. The focused probe tests assert the private
root, these read-only system inputs, app-info target, explicit runtime/document
binds, hidden fixture path, and final root remount. The exact hosted result for
the latest preflight and routed-probe attempt is recorded below; passing the
preflight did not establish FileChooser backend routing. Linux import remains
disabled.

The Ubuntu portal probe on SHA `223fa9d4ac397668d2015dfe87b36023fbcc6b04` ran on
Ubuntu 22.04.5 x86_64 with bubblewrap `0.6.1-1ubuntu0.3`, Documents portal
`1.14.4-1ubuntu2~22.04.2`, and GTK backend `1.14.0-1build1`. All 22 probe unit
tests, the real-bwrap preflight, and GNOME-session portal/backend FileChooser
introspection passed.
In the separate custom-desktop session, the client then failed with
`sandbox-client-openfile-unknown-method-backend-not-reached`: its `OpenFile`
call returned unknown-method and the test backend readiness report was absent.
No test backend FileChooser method, returned URI, permission operation,
post-close access check, or persistence observation was established.

The runtime had the corrected lowercase `XDG_CURRENT_DESKTOP=kotoha_portal_test`
and a `kotoha-test.portal` descriptor under `XDG_DATA_HOME`, but the test backend
was still not reached. The pinned Ubuntu package is `xdg-desktop-portal`
`1.14.4-1ubuntu2~22.04.2`. Review of the exact tagged source
`src/portal-impl.c` (SHA-256
`20701b5df21ac89520ee6b158071e2d74a882f8766386413dd4d91f3b776688f`) shows that
this version selects backends in `find_portal_implementation()` by matching a
descriptor's `UseIn` against `XDG_CURRENT_DESKTOP` and its `Interfaces` list, and
discovers descriptors in `load_installed_portals()` from
`XDG_DESKTOP_PORTAL_DIR` (otherwise the build-time `DATADIR/xdg-desktop-portal/portals`).
It reads neither `XDG_DATA_HOME` nor any `portals.conf`: no such parser exists in
the 1.14.4 frontend. A first correction (`b931276`) wrote a desktop-specific
`portals.conf`, but the current upstream material documents that mechanism
only for newer releases. It is inert on the pinned version and was removed.

The code now binds `XDG_DESKTOP_PORTAL_DIR` to the probe's `XDG_DATA_HOME`
portal-descriptor directory and fails closed unless that variable exactly
matches the directory where the probe writes the descriptor. Four focused tests
assert the descriptor's exact `DBusName`/`Interfaces`/`UseIn` fields and the
missing/mismatched/matching directory cases.

The hosted probe with that corrected binding ran on SHA
`323e750da2e07c0bb696276f4f558fd24a5ffce2`. On Ubuntu 22.04.5 x86_64 with the
same pinned portal/GTK/bubblewrap versions, `XDG_DESKTOP_PORTAL_DIR` and the
lowercase `XDG_CURRENT_DESKTOP=kotoha_portal_test` were exported as intended,
all 26 probe unit tests passed, the real-bwrap preflight and GNOME-session
portal/backend FileChooser introspection passed, and `OpenFile` was exposed on
both the desktop portal and the GTK implementation. In the custom-desktop
session the earlier `sandbox-client-openfile-unknown-method-backend-not-reached`
stage did not recur: the probe reached the end of its host routine and exited 0,
so its internal assertions (backend reachability, fixture hash, read bound,
grant/revoke control, self-revocation, post-close denial and retained-document
record) did not raise. However, the workflow's sanitized-result filter required
two key names the probe never emits (`revoke_read_and_grant_permissions_succeeded`
and `revoked_permissions_remaining`, instead of the emitted `self_revoke_succeeded`
and `app_permissions_remaining`), so it rejected the result with "Linux portal
probe produced no sanitized result" and the check failed. No sanitized field
values were surfaced by that run. The workflow keys are now aligned and a
regression test asserts the required set names only keys the probe emits.

The rerun was on SHA `ae27293dc65dfcb390580004156118cc9f04738d`. On Ubuntu
22.04.5 x86_64/amd64 with `xdg-desktop-portal` `1.14.4-1ubuntu2~22.04.2`, GTK backend
`1.14.0-1build1`, bubblewrap `0.6.1-1ubuntu0.3`, and `xvfb`
`2:21.1.4-2ubuntu1.7~22.04.16`, the 27 focused probe unit tests passed, the
real-bwrap preflight and GNOME-session portal/backend FileChooser introspection
passed, `OpenFile` was exposed on both interfaces, and the earlier
`sandbox-client-openfile-unknown-method-backend-not-reached` stage did not
recur. The probe reached the end of its host routine, exited 0, and emitted its
full sanitized result; the aligned workflow filter accepted it and the check
passed.

The sanitized values establish the following exact behavior, and only this.
`backend_app_id_matches=true`,
`returned_uri_mapped_to_documents_mount=true`,
`fixture_path_hidden_from_client=true`, `fixture_sha256=554cf07d3809de2c10f52e085525ca27393517d8e3f9e786098117fd9d967c01`
and `read_bytes=31` show that the returned FileChooser URI mapped to a
Documents-portal document and the fixture was read in place without its host
path being visible in the sandbox. `documents_version=4` and
`filechooser_version=3` bind the API versions. Crucially, a sandboxed client
cannot revoke its own access: `self_revoke_succeeded=false` with
`self_revoke_error=NotAllowed`, leaving `app_permissions_remaining` as
`["grant-permissions", "read"]`, `post_close_open_denied=false`, and
`persistent_document_record_retained=true`. A different app with grant/revoke
control could grant and revoke `read` (`other_app_control_succeeded=true`,
`other_app_control_permissions_remaining=[]`), so the grant/revoke mechanism
itself works; only same-app self-revocation is refused. The probe's internal
assertions held: post-close denial matched the (failed) revocation result, the
remaining permissions matched the not-revoked expectation, and the document
record was retained. The green check means the probe measured and reported
this behavior; it does not mean the privacy contract passed. This is runtime
confirmation of the pinned-source prediction above that 1.14.4 rejects
same-app revocation with `NotAllowed`. No claim is made about any other portal
version, a Kotoha Linux host/packaging target, or physical-device behavior.
Linux import remains disabled.

For a host app, the portal source returns the original URI without registering
a Documents entry (SHA-256 `a2e3a1251dfbc22dedffce3e3d5112ae0f28004615893410cc3f658a6539c5ca`),
but Kotoha has no Linux host or packaging target to validate that mode.

Linux import remains unsupported. Reconsideration requires an explicit product
Linux target that adopts a pinned GTK-free host, verification of its complete
feature-resolved license/runtime closure and reproducible Kotoha build/link/CI
path, and a supported import adapter that demonstrates its data flow and
permission lifecycle end to end. The `ivi-homescreen` source and upstream build
recipe are candidates for that assessment, not approval or evidence of Kotoha
support.
The candidate client manifest and license were inspected (license SHA-256
`ae26bc7b1bc91fb8648f6a298decbb1a77090a56c9d04e2c23b8365e5f54acb5`);
the `SelectedFiles::uris()` behavior comes from its API documentation.

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
  selected file. `XFile.openRead` streams the selected path through Dart IO;
  import stops at the size bound without calling `saveTo` or writing a cache
  file. DebugProfile and Release declare
  `com.apple.security.files.user-selected.read-write` for the explicit
  translation-export save panel. Import only reads the selected input; export
  only writes to the user-selected target.
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

The umbrella candidate was resolved separately and not adopted. Its locked
resolution was materialized and checked offline. Its archive hashes and
source-file hashes are recorded in the following provenance table. The mobile
adapter reads the granted document handle directly into memory; it is separate
from encrypted save/reopen or SQLCipher.

## Mobile read-in-place adapter

`TextImportPlugin.kt` registers with the Android Flutter engine and implements
`ActivityAware`/activity-result handling. `TextImportPlugin.swift` registers with
the iOS implicit engine registrar and presents through the active scene, never
`AppDelegate.window.rootViewController`. The activity's pause/resume privacy flags
and scene's inactive cover remain unchanged.

The app-owned `org.kotoha/text_import` channel requires a `maxBytes` argument
for `open` and returns only a display name and typed bytes, null on cancellation,
or a generic error without selected locations. `text_document_picker.dart`
checks the response shape and size before passing the document to the same
`_importSource` validation, consent and edit-race handling as the desktop picker.
Language and translation controllers remain untouched. The mobile response is
an in-memory document, not a provider URL wrapped in a Dart `File`/`XFile`.
Desktop selection still defers reading the `XFile`.
Native code must also check the name before reading unsupported content. Picker
filters are advisory: MIME/UTI mappings differ across Markdown providers, so a
filter must not be the only acceptance check.

| Platform | Implemented read path | Resource lifetime and exclusions |
| --- | --- | --- |
| Android | `ACTION_OPEN_DOCUMENT` with `CATEGORY_OPENABLE`, single selection. The adapter queries `OpenableColumns.DISPLAY_NAME`, then reads the granted URI with `ContentResolver.openInputStream` with a byte bound. | The query cursor and input stream close on success and failure. The adapter does not call `takePersistableUriPermission`, request broad storage access, derive a real path, or create an app cache file. The URI is held only for the active request. |
| iOS | `UIDocumentPickerViewController(forOpeningContentTypes:asCopy: false)`, single selection. The adapter acquires security-scoped access and coordinates a read using `NSFileCoordinator`, then checks the file size and reads with a bounded `FileHandle` inside its accessor. | Successful `startAccessingSecurityScopedResource` calls are balanced by `stopAccessingSecurityScopedResource` after the read, including on failure. An unsuccessful start is not by itself proof that a local URL is unreadable; the coordinated read must report its actual result. The adapter does not create a bookmark, copy the URL to the sandbox, or retain the selected URL after completion. |

The adapters read provider bytes away from the UI thread and deliver a single terminal result
on the platform thread. Each engine allows one pending picker/read and rejects
a concurrent request rather than overwriting its completion. Pending callbacks
and picker delegates are released on completion, cancellation, read failure and
engine/activity detach. A late result after detach must not reach a new request;
only its in-memory request-code tombstone remains until that result is consumed.
Activity/process recreation does not restore a draft or import: the interrupted
request fails or is discarded. No callback, URI, bytes or text is persisted
for recovery.
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
  Hosted Android accessibility runs have shown a non-deterministic Delete result
  after a synthetic `p` paste. In a failing run,
  `MainActivityAccessibilityTest.testEnglishLanguageFields` did not observe the
  expected empty value: the focused, visible field still contained `p`. The
  diagnostic recorded FlutterView focus and a visible IME, but this does not
  establish delivery or handling. Android specifies that
  `UiAutomation.injectInputEvent` reports injection success
  ([API reference](https://developer.android.com/reference/android/app/UiAutomation#injectInputEvent(android.view.InputEvent,boolean)));
  its `true` result is not evidence that the editor processed Delete. This
  failure is distinct from the earlier scroll-discovery failures and does not
  establish any physical-device result.

  Another run passed all 22 checks, but that was a non-reproduction, not a
  durable closure. A later run again failed both `testEnglishLanguageFields`
  (`checkField`, line 164) and `testShellInjectedDeleteKeyClearsFocusedField`
  (line 111): after the synthetic `p` paste and `input keyevent 67`, the field
  stayed at `textCodePoints=[U+70]`, selection `1..1`, focused and visible,
  where empty was expected. App sources were byte-identical across the passing
  and failing runs, so these are non-deterministic outcomes of the same app and
  test binaries.
  The suppressed diagnostic shows native focus remained on `FlutterView` with
  `imeVisible=true` before and after, and `events=[]`, `lastContentChange=none`:
  the shell command reached stdout EOF but the editor emitted no text or
  selection event. That separates command completion from editor handling; it
  neither establishes that the key reached the editor nor infers any
  physical-device result. The test's own history records this same unchanged-editor
  symptom with both instrumentation key events and the shell `input keyevent`, so
  no cause-backed correction is established and switching mechanisms again would
  be a blind retry. Any correction must preserve every exact-value,
  accessibility, locale and traversal assertion without adding retries or
  longer waits. Neither run is a durable closure. The product's exact editing and traversal behavior remains owned by the
  Flutter widget tests on this revision.

  Current CI state: `MainActivityAccessibilityTest` and the iOS
  `LanguageFieldAccessibilityTests` XCUI target remain in the sources but are no
  longer CI gates. CI no longer checks native language-field labels/values,
  synthesized input/focus continuity, forward/reverse Tab through the native
  layer, or iOS system-picker presentation and cancellation through XCUI;
  Flutter widget tests and the retained native privacy/import checks cover the
  behaviours they can observe. A runner with deterministic key injection and a
  visible software keyboard is needed to revive those checks as gates.

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

## Import size bound

Text and Markdown import accepts files up to 8 MiB. Oversized documents are
rejected before UTF-8 decode with the existing import error; drafts stay intact.
This is a raw input I/O bound only, not a measured editor-safe envelope: the full
widget path assigns decoded text to one `TextField`, and the widget-profile peaks
below show process memory far exceeding decoded-file size while the 16 MiB cause
remains unconfirmed. No supported-device memory budget or comparable edit/import
measurement was taken, so this bound does not establish that a file under 8 MiB
edits without excessive memory or stall; bounding that work at its cause, or an
evidence-based editing limit with a clear refusal and intact draft, remains an
open decision gated on such measurements.

## Memory profile (sandbox-only)

These measurements predate the import size bound. The measured path held the
whole selection in one `Uint8List` and built one `String` with strict
`utf8.decode`, without a cache or persistence copy.

Sandbox-only Dart measurement on this Linux host (not device evidence): fresh `dart` processes reading
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
excluded. They show the full widget path can greatly
exceed the decode-only measurement, but are not a basis for a shipping limit.

A matched controller-assignment control used the same widget-test harness,
text payloads, and `TextField`, but bypassed `FileSelectorPlatform` and directly
decoded then assigned the same source text. `VmHWM` rose by 74,148 kB for the
65,065-byte import versus 68,216 kB for direct assignment, and by 288,064 kB
for the 261,261-byte import versus 282,100 kB for direct assignment. The similar peaks suggest the Linux debug
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
allocation limit. Each size requires a fresh run so peaks do not carry across
sizes. These are debug test profiles, not release/device benchmarks.

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
decode and editor stages with 64,832 code units on Linux. These debug runs validate fixture sizing
and stage execution, not supported-platform memory behavior. Editor/decode
smoke, wall-time clipping, SIGTERM child termination and fixture cleanup, RSS
stop behavior, design validation (93/93), and all four watchdog tests passed. A 768 MiB group budget stopped startup
before measurement, demonstrating that the
budget includes compilation, not only editor memory.

All stage peaks are process-wide and may include startup, fixture preparation,
framework work and unrelated allocations. Zero peak delta does not mean zero
allocation. Adding or subtracting separate stage peaks cannot establish
bridge copies.
Native stages stop before MethodChannel serialization. Native-to-Dart transfer,
provider failures under pressure, picker/provider allocations, physical devices
and release-mode editors remain unmeasured. The memory evidence remains
incomplete until hosted observations cover the needed path. No size cap, chunked import
implementation, cache copy or draft persistence is introduced by this harness.

Failure behavior is fail-closed: strict decoding throws `FormatException` on
malformed input, the UI shows only a generic notice and preserves source,
language and translation state (covered by existing desktop/mobile widget
tests). Large-file out-of-memory behavior on constrained targets is unmeasured.

The profiling work did not select an import limit or incremental transfer. A
future guard must be configuration with hosted-profile evidence, preserve
drafts on error, and keep read-in-place access with no persistence or cache copy.

The smallest hosted measurement still needed for each supported profile
(macOS/Windows and Android Emulator/iOS Simulator CI) uses synthetic 2 MiB and
16 MiB UTF-8 `.txt`/`.md` files through the exact shipped picker path. It
records native and Dart peaks, import success or failure, and draft
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

The desktop-source file hashes above come from exact package tags; the package
archive SHA-256 values in the selected-dependency table bind the implemented
versions.
