# Native text-export overwrite audit

Kotoha's desktop export asks the locked `file_selector` package for a save location, then writes only the selected translation with `File(path).writeAsBytes`. That write replaces/truncates a file at the returned path; consent therefore depends on the native save panel before it returns that path.

## Locked package and source evidence

`pubspec.lock` pins `file_selector_windows` 0.9.3+6 (archive SHA-256 `fbefc5fb92c6d3cbe8d284a2cd971b593bb07d2cd6da8557b81a862250b4acec`) and `file_selector_macos` 0.9.5+2 (archive SHA-256 `d785431f1910aac8a50e5c492cae912320158030a88703c67b9ef7f1f96fd7ba`). Pub's version metadata reports the same archive hashes (Windows receipt `e0106608d74b927fe9c7f4d39765bdb5db53a75d38fb618a7af46af04fa1619bf`; macOS receipt `2a553e93d514ba898a823f268af3232413be5327917427e2cf5d32ed8e9319bf`). The corresponding upstream version tags resolve to Windows commit `9854cd5607da4001f2dd3cbdcd6903202d28958c` and macOS commit `f2c6798b45a7ae936feb6798fe45cb51f832dc18`; each tagged `pubspec.yaml` declares the locked package version. The inspected Windows plugin source SHA-256 is `17e0345a6c0a508986d7d2100ecd04880339b40459c46bb1c14370cbce4b2d3e`, its option-forwarding controller is `b35502bb981c2e19b201c2c0bd7202dc25d0b255ac5fef66fec4b80da63e4d4e`, and the macOS Swift plugin source SHA-256 is `2ce6820e865f645c7823c82091d1df2a3a2f36662add35fd75d509b9a5bcc24d`. The immutable source links are [Windows](https://github.com/flutter/packages/blob/9854cd5607da4001f2dd3cbdcd6903202d28958c/packages/file_selector/file_selector_windows/windows/file_selector_plugin.cpp), [Windows controller](https://github.com/flutter/packages/blob/9854cd5607da4001f2dd3cbdcd6903202d28958c/packages/file_selector/file_selector_windows/windows/file_dialog_controller.cpp), and [macOS](https://github.com/flutter/packages/blob/f2c6798b45a7ae936feb6798fe45cb51f832dc18/packages/file_selector/file_selector_macos/macos/file_selector_macos/Sources/file_selector_macos/FileSelectorPlugin.swift).

The version tags and registry metadata identify the source and pinned package versions, but the gzip archives were not available through the text-only fetch interface, so this audit did not independently compare each archive's extracted files byte-for-byte with its Git tag. That is the remaining source-identity limitation; it does not change the API-level dialog behavior below.

## Overwrite-consent behavior

- **Windows:** the pinned plugin's `ShowSaveDialog` selects `DialogMode::save`, which creates `CLSID_FileSaveDialog`. Its normal Kotoha save request does not request folder selection or multiple selection, so the plugin does not add options; when options are added, `DialogWrapper::AddOptions` obtains the current flags, ORs the requested flags, then passes them to `IFileDialog::SetOptions`. The controller forwards `GetOptions`/`SetOptions` directly. Microsoft documents the Common Item Dialog's default Save flags as including `FOS_OVERWRITEPROMPT`, and defines that option as prompting before overwriting an existing same-name file. Thus the pinned implementation retains the documented Windows Save-dialog overwrite prompt. Sources: [Microsoft Common Item Dialog](https://learn.microsoft.com/en-us/windows/win32/shell/common-file-dialog), [Microsoft `FILEOPENDIALOGOPTIONS`](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/ne-shobjidl_core-_fileopendialogoptions).
- **macOS:** the pinned plugin creates `NSSavePanel()` and displays it through the standard sheet/modal APIs; it does not install a delegate or set an overwrite-related option. Apple's AppKit contract for `NSOpenSavePanelDelegate.panel(_:userEnteredFilename:confirmed:)` says the Save panel asks whether to replace an existing file when the chosen name already exists. The plugin does not implement that delegate or suppress the panel behavior. This establishes a source/documentation-level native overwrite-confirmation path for the locked macOS implementation. Source: [Apple AppKit delegate method](https://developer.apple.com/documentation/appkit/nsopensavepaneldelegate/panel(_:userenteredfilename:confirmed:)); retrieved JSON receipt `79a8406612cf39fda933c97184edf810de5e5d98e616e5f813fdc782384a97d7`, SHA-256 `385876c4e270ef5ffcface187665b8f810a6369061d17e31647830425d09c313`.

These conclusions are about the pinned source and the documented platform APIs, not observations of a user's Windows/macOS runtime or physical device. Once the chooser returns a path, Kotoha still writes to it directly; the audit does not establish atomic replacement, protection against intervening filesystem changes, or behavior for every OS version and configuration.

## Existing test coverage and hosted accessibility limit

`test/text_export_test.dart` checks exact UTF-8 output,
selected-translation-only writing, save-dialog arguments, cancellation, and
write-error behavior using a fake selector; it does not show native UI or
exercise overwrite confirmation. `macos/RunnerUITests/NativeExportPanelUITests.swift`
is intended to verify the accessible native save panel, cancellation, and
preservation of the in-memory translation. It does not select an existing file
or exercise the confirm-replacement alert. There is no equivalent end-to-end
overwrite-dialog test in the Windows probe.

The latest exact hosted macOS job, run `43680441354` on publication
`f462494dd6dd2306c8bb763f9a1b7703e8325ee9e84db767b1f4f658b37693ef` / SHA
`53809a016da85eb2394e63ffcdfafdf1003e133d`, failed at
`NativeExportPanelUITests.swift:114` after one window-coordinate drag and the
VoiceOver-focus key attempt. The diagnostic reports VoiceOver enabled,
`AXIsProcessTrusted() == false`, AX enhanced-UI status `-25211`, zero exposed
scroll views, and no translation/source fields while the application window is
present (`vcs-read/14f452ce42e2462f8b25a623f9f3cf92`,
`vcs-read/8e5d616f9aca45e4bc0d24cae8c63c11`). The test therefore fails before
filling a field or reaching the native save panel, Cancel, or draft-preservation
assertions. This is strong evidence that the hosted accessibility-query path is
untrusted/unavailable, not a product root-cause diagnosis or proof of how a
user-run Mac exposes the app to VoiceOver.

The operator confirmed hosted CI is the only available macOS test context and
no TCC-authorized runner will be provided (response to question
`fb5e1fcf557f4c7c9e2f9e94d50094aa`). Therefore, save-panel
accessibility/cancellation/draft-preservation coverage is currently
**unverifiable in that hosted context**. Preserve the assertions and OS privacy
controls; do not bypass TCC or call this a pass. If a supported verification
route that works within the hosted context cannot be established, retain this
as an explicit coverage gap rather than attributing it to the product.

Source/API inspection still finds no export-code change required to retain the
documented default overwrite prompt. That does not substitute for a runtime UI
result: do not claim end-to-end overwrite behavior was observed. A future UI
test would need a bounded, stable way to create/select a unique existing
temporary file and verify both cancel-preserves-bytes and confirmed-replacement
behavior; current tests do not provide that route.
