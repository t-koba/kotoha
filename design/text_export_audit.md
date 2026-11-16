# Native text-export overwrite audit

Kotoha's desktop export asks the locked `file_selector` package for a save location, then exports only the selected translation as UTF-8. `lib/text_document_exporter.dart` stages the bytes in an operation-owned sibling directory and only replaces the selected path after staging succeeds. A prior production-function failure injection (`b665c739bad64eee9229b68c61d615e6`) reproduced direct-write truncation: a failed write left a 29-byte existing file reduced to a four-byte prefix. A second experiment (`f0311dbc15d546e699b14d55f7a4fbf9`) found that replacement widened an existing POSIX mode `0600` file to `0644`. Linux focused tests and Windows native CI verify mode/ACL preservation; the macOS implementation now uses path-based stat and ACL calls, but its deny-read behavior still awaits native CI. Required access-control preservation failures abort before replacement.

## Locked package and source evidence

`pubspec.lock` pins `file_selector_windows` 0.9.3+6 (archive SHA-256 `fbefc5fb92c6d3cbe8d284a2cd971b593bb07d2cd6da8557b81a862250b4acec`) and `file_selector_macos` 0.9.5+2 (archive SHA-256 `d785431f1910aac8a50e5c492cae912320158030a88703c67b9ef7f1f96fd7ba`). Pub's version metadata reports the same archive hashes (Windows receipt `e0106608d74b927fe9c7f4d39765bdb5db53a75d38fb618a7af46af04fa1619bf`; macOS receipt `2a553e93d514ba898a823f268af3232413be5327917427e2cf5d32ed8e9319bf`). The corresponding upstream version tags resolve to Windows commit `9854cd5607da4001f2dd3cbdcd6903202d28958c` and macOS commit `f2c6798b45a7ae936feb6798fe45cb51f832dc18`; each tagged `pubspec.yaml` declares the locked package version. The inspected Windows plugin source SHA-256 is `17e0345a6c0a508986d7d2100ecd04880339b40459c46bb1c14370cbce4b2d3e`, its option-forwarding controller is `b35502bb981c2e19b201c2c0bd7202dc25d0b255ac5fef66fec4b80da63e4d4e`, and the macOS Swift plugin source SHA-256 is `2ce6820e865f645c7823c82091d1df2a3a2f36662add35fd75d509b9a5bcc24d`. The immutable source links are [Windows](https://github.com/flutter/packages/blob/9854cd5607da4001f2dd3cbdcd6903202d28958c/packages/file_selector/file_selector_windows/windows/file_selector_plugin.cpp), [Windows controller](https://github.com/flutter/packages/blob/9854cd5607da4001f2dd3cbdcd6903202d28958c/packages/file_selector/file_selector_windows/windows/file_dialog_controller.cpp), and [macOS](https://github.com/flutter/packages/blob/f2c6798b45a7ae936feb6798fe45cb51f832dc18/packages/file_selector/file_selector_macos/macos/file_selector_macos/Sources/file_selector_macos/FileSelectorPlugin.swift).

The version tags and registry metadata identify the source and pinned package versions, but the gzip archives were not available through the text-only fetch interface, so this audit did not independently compare each archive's extracted files byte-for-byte with its Git tag. That is the remaining source-identity limitation; it does not change the API-level dialog behavior below.

## Overwrite-consent behavior

- **Windows:** the pinned plugin's `ShowSaveDialog` selects `DialogMode::save`, which creates `CLSID_FileSaveDialog`. Its normal Kotoha save request does not request folder selection or multiple selection, so the plugin does not add options; when options are added, `DialogWrapper::AddOptions` obtains the current flags, ORs the requested flags, then passes them to `IFileDialog::SetOptions`. The controller forwards `GetOptions`/`SetOptions` directly. Microsoft documents the Common Item Dialog's default Save flags as including `FOS_OVERWRITEPROMPT`, and defines that option as prompting before overwriting an existing same-name file. Thus the pinned implementation retains the documented Windows Save-dialog overwrite prompt. Sources: [Microsoft Common Item Dialog](https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog), [Microsoft `FILEOPENDIALOGOPTIONS`](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/ne-shobjidl_core-_fileopendialogoptions).
- **macOS:** the pinned plugin creates `NSSavePanel()` and displays it through the standard sheet/modal APIs; it does not install a delegate or set an overwrite-related option. Apple's AppKit contract for `NSOpenSavePanelDelegate.panel(_:userEnteredFilename:confirmed:)` says the Save panel asks whether to replace an existing file when the chosen name already exists. The plugin does not implement that delegate or suppress the panel behavior. This establishes a source/documentation-level native overwrite-confirmation path for the locked macOS implementation. Source: [Apple AppKit delegate method](https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:userenteredfilename:confirmed:)); retrieved JSON receipt `79a8406612cf39fda933c97184edf810de5e5d98e616e5f813fdc782384a97d7`, SHA-256 `385876c4e270ef5ffcface187665b8f810a6369061d17e31647830425d09c313`.

These conclusions are about the pinned source and the documented platform APIs, not observations of a user's Windows/macOS runtime or physical device. The chooser is unchanged; it is still the authority for native overwrite consent, and export does not start until it returns a path.

## Failure-safe replacement

The exporter encodes the selected translation once as UTF-8 and writes it to an exclusively created file inside a unique sibling staging directory. It does not touch the destination until the staged write is complete. Cleanup removes only the operation-owned staged file and then non-recursively removes its directory in `finally`; cleanup errors propagate, and an error after replacement may leave the new destination in place. Removing the staging entry is not secure erasure. A final symlink to an existing file is resolved first so export continues to write through to its target; a dangling symlink fails closed.

Staging and replacement retain the existing file's access restrictions before plaintext is written or the final name is replaced:

- **Linux:** `mkdtemp` creates the sibling directory, then `chmod(0700)` is applied before any stage file is created. A regression using an inherited POSIX default ACL found that the requested `mkdtemp` mode alone did not yield owner-only access; the post-create chmod sets the ACL mask to owner-only while retaining the directory's default ACL for new-file inheritance. For an existing regular destination, the exporter reads owner, group and mode with `statx`, applies them to the staged file, then copies the exact `system.posix_acl_access` xattr (or removes a stage ACL if the destination has none). Errors other than an explicit “no access ACL” result abort without replacement. Tests verify replacement of mode `0600`, an explicit named-user access ACL, safe staging under an inherited default ACL, and that a new export matches a directly created sibling's mode and access ACL. These are real-filesystem Linux tests, not cross-filesystem or race guarantees.
- **macOS:** for an existing destination, path-based `stat` and `acl_get_file(ACL_TYPE_EXTENDED)` inspect ownership, mode, and ACL without opening file data. The `stat` lookup uses `stat$INODE64` on x86_64 and plain `stat` on arm64 to match Darwin's 64-bit-inode layout. Before opening the stage for writing, the exporter removes inherited file ACLs and sets owner-only mode; it then opens a write-only handle, applies source owner/group/mode and the destination ACL to the empty stage, and writes through that already-open handle. This allows a read-only destination mode to be preserved without reopening an unwritable stage. If `acl_get_file` reports `ENOENT` after `stat` confirmed the source, any stage ACL is removed; other errors abort replacement. This does not promise timestamps, file flags, extended attributes, resource forks, or other metadata. New destinations retain the selected parent directory's inherited ACL defaults. macOS tests cover deny-read staging, read-only replacement, existing ACL-free files under an ACL-inheriting parent, and new-file ACL defaults. The native ACL behavior still needs exact macOS arm64 and Intel CI results; Linux skips these platform tests.
- **Windows:** for an existing destination, the existing DACL is read with `GetNamedSecurityInfoW` and applied as a protected DACL to the empty stage file before writing. The exporter holds a write-only stage handle open before applying the DACL, so writing does not reopen the path after restrictions are applied. Microsoft documents [`ReplaceFileW`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew) as preserving the replaced file's ACL. It is called with flags `0`, without `IGNORE_ACL_ERRORS` or `IGNORE_MERGE_ERRORS`; any failure propagates. New files use the selected directory's inherited ACL path and ordinary rename. Windows-only tests compare a protected, owner-only DACL before stage writing and after replacement, and compare new-file DACLs with direct sibling creation. In the exact CI run on SHA `c7d02c5de36175123decd3daecd44eebc89f1821`, both Windows DACL tests failed before their ACL assertions because `powershell.exe` could not load `Microsoft.PowerShell.Security` for `Get-Acl` (log `vcs-read/bcbbd798f59d4a9798b2738674f680d4`). The tests now use the runner's PowerShell 7 executable and explicitly import that module. Exact Windows CI run `43801419820`, job `133082932302`, on SHA `4e1428fbb32f53a1e64ab4bee8993aff04ee6d7c` passed the prior text-export test file, including both Windows DACL tests (log `vcs-read/baef890642054853a4875546215f909c`); the current open-handle implementation needs its own native run. The stage directory itself is created under the selected parent, so temporary names may be visible there; existing-file staged data is protected by its copied DACL. For a new file, the selected directory's access policy intentionally applies to the staged file too.

The current focused Linux run passed 16 tests, including exact UTF-8 output, read-only mode replacement, failure injection after a real partial stage write, cleanup, final-symlink write-through, POSIX mode/ACL preservation, and selected-directory default ACL inheritance. Five native macOS/Windows ACL tests were skipped on Linux. `dart analyze` on the exporter and test reported no issues, and the Dart formatter made no changes. CI runs the same test file in isolated five-minute steps on macOS arm64 and `macos-15-intel` x86_64, plus Windows; native results for the current open-handle/ABI-correct revision are pending.

Dart SDK 3.13.7 inspection shows macOS `File.rename` calls POSIX `rename`; for Windows, the existing-target path now uses `ReplaceFileW`, while a genuinely new destination uses Dart's `File.rename` (`MoveFileExW` with replacement/write-through flags). Source inspection and local Linux tests do not establish power-loss durability, behavior on every filesystem or filter driver, concurrent external path replacement, native overwrite-dialog interaction, or preservation of all metadata (including extended attributes, resource forks, hard-link identity and creation-time semantics). No crash-durability or path-race guarantee is made.

## Existing test coverage and hosted accessibility limit

`test/text_export_test.dart` checks exact UTF-8 replacement, selected-
translation-only writing, save-dialog arguments, cancellation, and an injected
partial stage-write failure on a real filesystem; it also verifies temporary
cleanup and final-symlink write-through. Widget coverage uses a fake selector;
it does not show native UI or exercise overwrite confirmation.
`macos/RunnerUITests/NativeExportPanelUITests.swift`
is intended to verify the accessible native save panel, cancellation, and
preservation of the in-memory translation. It does not select an existing file
or exercise the confirm-replacement alert. There is no equivalent end-to-end
overwrite-dialog test in the Windows probe.

The exact hosted macOS probe in run `43715005994`, job `132814879210`, on
SHA `548ccbc99275e6dd264e8d953bdc0cf023c3ae5d`, failed at
`NativeExportPanelUITests.swift:114` after one window-coordinate scroll. Its
failure-only diagnostic reports `voiceOverEnabled=true`, `axClientTrusted=false`,
`appEnhancedUIStatus=-25211`/unavailable, `scrollViews=0`, and
`target{exists=false}`, `source-language{exists=false}`, and
`source-text{exists=false}` while the application window is present
(`vcs-read/a6701edfddaf46a39f12bf8446980572`). The test therefore fails before
field entry or reaching the native save panel, Cancel, or draft-preservation
assertions. This is evidence that this hosted accessibility-query path is
unavailable, not a product root-cause diagnosis or proof of how a user-run Mac
exposes the app to VoiceOver. A later exact run `43718257468`, job
`132824669921`, on SHA `548c92ba16fbd85c446e17059fc1fa093a87d4a0`, failed at
the same line with the same diagnostic: `axClientTrusted=false`, enhanced UI
status `-25211`/unavailable, zero scroll views, and missing target,
source-language, and source-text nodes (`vcs-read/8b9d1ab4e0164d45befd066b4b4f7500`).
This repeats the hosted query failure; it still does not reach field entry or
the save panel and does not establish behavior on a consented user Mac. A later
exact run `43723433412`, job `132840442367`, on SHA
`78d0bc90d5124dbf3413597114447179cc06ac62` failed at the same assertion with
`voiceOverEnabled=true`, `axClientTrusted=false`, enhanced UI status `-25211`/
unavailable, zero scroll views, and missing target, source-language, and
source-text nodes while the app window was present
(`vcs-read/3fff63ad45bf4418972dfcf736ce4ac5`). It again failed before field
entry or the save panel, confirming only a repeated hosted accessibility-query
failure, not user-run VoiceOver behavior.

The operator confirmed that no macOS runner or session is available
(`operator/kotoha/a-q1edb9445c51e96eeb98faaea04a8f7129714884a-1794746647`).
Therefore, keep native macOS accessibility, save-panel, cancellation, and
draft-preservation behavior explicitly **unverified** until there is a
consented environment or an independently valid verification route. Existing
Flutter widget/semantics and fake-selector tests cover in-process behavior only;
they do not establish the native app accessibility tree, native save panel, or
user-run VoiceOver behavior. Preserve the native test assertions and deadlines
and OS privacy controls; do not bypass TCC or call the hosted failure a pass.
This remains an explicit coverage gap rather than a product-behavior finding.

The staged replacement does not alter save-dialog options or provide a
second overwrite prompt. Source/API inspection supports the documented native
prompt path, but no user interaction has been observed. A future UI test would
need a bounded, stable way to create/select a unique existing temporary file and
verify both cancel-preserves-bytes and confirmed-replacement behavior; current
tests do not provide that route.
