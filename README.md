# Kotoha (ことは)

Kotoha is an on-device multilingual workspace. The first runnable interface is a
manual text-workspace draft: enter a source text, add one or more target languages,
and write translations without an installed model. It does not claim to translate
text automatically.

For keyboard navigation, use Tab and Shift+Tab to move between controls. With a
toolbar button focused, Page Up and Page Down scroll the workspace to reveal
lazy-loaded translation cards; Tab then reaches their fields and actions. Text
fields retain their standard editing keys, and Space/Enter still activate buttons.

The source editor can import UTF-8 `.txt`, `.md` and `.markdown` documents through
an explicit system picker on macOS/Windows and the Android/iOS adapters.
Import replaces only source text after consent; translations remain manual and
all drafts stay in memory. Kotoha does not stage a cache copy, persist document
grants, or add a network client, but the OS/provider may download or stage a file.
Typed or imported source text also gets a local outline of headings,
paragraphs, list items and fenced code blocks. A local search filters the
outlined entries as you type, without changing the source. Choosing an entry
selects that block in the source editor; the outline is derived from the current
text and neither translates nor renders rich formatting. To keep editing
responsive, the outline parses only a bounded prefix (128 × 1024 UTF-16 code
units) plus a 4 KiB lookahead for boundary checks, and shows at most 200 blocks
or matches; a notice appears when that bound
hides any content. The full text stays editable, and export and restore still
operate on it unchanged. A short capability note beside the outline states which
blocks are recognized, that the flat source and its exact ranges remain canonical,
and that inline formatting, numbers, links and placeholders need manual review.
Outline entries carrying digits, web/email links or brace/percent placeholders
get a local “Review” hint; it is only a navigation aid and never rewrites text.
A “Review only” toggle filters the same cached entries without reparsing the source.

Between the format note and the “Find and replace” control is a collapsed “Structured JSON values” tile. Expand it to edit string values in a valid JSON source of at most 131,072 UTF-16 code units (128 × 1024) and 200 string values; applying edits rewrites only string values, preserves the source formatting, and leaves an empty field unchanged; the source caret is mapped through the rewritten ranges so it stays at the corresponding position when translation lengths differ. Editing the source in place keeps pending fields only while the ordered JSON paths and decoded source string values stay unchanged and the source remains valid; changing a value, reordering entries, or making the source invalid clears them, as do importing or restoring another document.

Below the source editor’s outline and format note, a “Find and replace” button (also Ctrl+F / ⌘+F) opens one compact panel for the source text field and every current translation field; the shortcut focuses and selects the query, and Escape closes the panel. Pick Source or Translation N, enter a query and replacement, then use Find next (also press Enter in the Find field, which stays focused for repeated finds; Shift+Enter inserts a line break so queries and replacements can span lines), Replace (only when the selected text exactly equals the query) or Replace all. Search is literal and case-sensitive — no patterns — and the panel reports match found, no-match and replacement counts. These actions edit only the chosen text field and leave language fields, import/export and restore untouched; drafts stay temporary and in memory, with no save path. Growing Replace All results are atomically refused above the configured limit (default 8,388,608 UTF-16 code units): no text changes, non-growing replacements are unaffected, and the status reports the refusal.
The limit is build-time policy: deployments can change it without editing Dart source by passing `--dart-define=KOTOHA_REPLACE_ALL_OUTPUT_LIMIT=<UTF-16 code units>` to the Flutter build or test command, for example `flutter build <target> --dart-define=KOTOHA_REPLACE_ALL_OUTPUT_LIMIT=16777216`. Without the define, the budget is 8,388,608 UTF-16 code units.

On macOS and Windows, each translation can be explicitly exported as UTF-8 text
to a user-selected `.txt` file; that writes only that translation, not the
workspace. The same platforms can export the whole workspace as a lossless,
reversible v2 text document containing the source language, source text and
every translation; even unpaired UTF-16 surrogates survive parsing and
re-export. The earlier v1 format is no longer produced or restorable.
Kotoha shows its own in-app “Replace existing file?” confirmation when the
selected path already exists; Cancel writes nothing. This check does not rely
on native save-panel behavior (whose confirmation UI hosted CI does not
automate). A workspace whose UTF-8 v2 bytes exceed Restore's 8 MiB
limit is disclosed before saving; the file can still be saved as text, but a
distinct success notice says Kotoha cannot restore it. Mobile builds have no export action.

On every platform, a v2 workspace export can be restored through the same
explicit text-document picker (`.txt`, `.md` or `.markdown`). If the export has
unpaired UTF-16 code units, a disclosure explains that editable fields will get
U+FFFD instead; the exported file is unchanged, and canceling keeps the current
workspace. If the current workspace holds text or an added translation card, a
further confirmation precedes replacement of all fields.
Cancellation is silent; an edit made after picking, a wrong file type, an
oversized document, a malformed document and a read failure all leave the drafts
intact, with distinct notices where the cause is known. Exports use LF line
endings, and the parser also accepts CRLF files re-saved by a Windows text editor while still
rejecting other malformed content. Restore changes only in-memory session state.
Hosted Android Emulator and iOS Simulator CI now validates the native builds and
configured import adapter tests, including picker-cancellation/error preservation.
It does not establish reads from live file providers or behavior on physical devices
and OEM launchers; see `design/text_import_audit.md` for the data flow and evidence
boundaries.

This development build does not save drafts. Saved content must use encrypted
storage and a validated key lifecycle, recovery, and encrypted backup/restore path.
Persistence remains disabled until native dependency provenance and licenses are
verified and the complete flow is tested on every supported platform. Do not enter
sensitive text in this temporary build.

Mobile task-switcher previews receive a best-effort privacy mask: Android temporarily
sets the secure-window flag while the activity is paused; iOS displays an opaque
window cover while its scene is inactive. CI checks the native pause/resume callback
state on a pinned Android API 35 emulator and iPhone 17/iOS 26.2 simulator, while a
Flutter lifecycle test checks in-memory draft and focus continuity. These tests do
not inspect the OS task-switcher thumbnail or establish behavior on physical devices,
OEM launchers, every OS version, external cameras, keyboards, or screen sharing.
Kotoha removes its mask on resume and does not intentionally block ordinary foreground
screenshots; Android may suppress capture while paused.

On Android, the editor asks the input method not to update personalized typing data
by default; users can opt in for the current session. A change applies when a text
field is focused again. Kotoha provides no equivalent keyboard-learning control on
iOS or other platforms. Input methods control their own behavior, so this flag does
not guarantee that an external keyboard will never process or retain entered text;
check the keyboard's privacy settings.

On Android, the workspace also offers an explicit “Review model package terms” action. It reads only a selected package's `model_manifest.json` and declared terms files, shows the declared publisher and usage/attribution terms without treating them as verified, and accepts only for the current session by retaining digests. No model is installed: no bytes are copied or persisted, and no translation route is enabled. The session acceptance can be cleared at any time. After acceptance, “Verify model files” streams the declared non-terms files in place and compares SHA-256 hashes with the manifest; a match proves only that the bytes read matched those digests, not origin, authenticity, license approval, or runtime support, and records an in-memory digest binding for the session without enabling an engine or runtime. Other platforms do not offer these actions.

The interface follows the operating system's light/dark appearance; Kotoha does not
persist a theme preference.

## Development

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
python3 design/specs/validate_specs.py
```

## Continuous integration

`.github/workflows/ci.yml` runs the design-contract validator, Dart formatting,
Flutter analysis and tests on pushes to `dev` and `mizu/dev`, pull requests, and
manual dispatch. The `mizu` integration branch is excluded from automatic push
runs; reviewed `mizu` publications use explicit exact-publication CI requests.
The workflow also builds debug apps on Android, iOS/macOS, and Windows runners.
A separate, path-scoped `Native engine probe` workflow runs on reviewed `mizu`
publications with changed probe inputs. It builds an isolated Windows CPU candidate
and runs an Android API 35 x86_64 owned-emulator feasibility probe; neither is product
inference. The Android ABI is a developer probe, not a selected product build or
physical-device support. Configuring a job is not evidence that a run succeeded or
that an engine was adopted. See `design/archive/engine_probe.md` for its evidence
and gates.
On the same pinned mobile profiles used for privacy callback tests, CI runs the
native privacy and import checks that can pass on hosted runners. Flutter widget
tests cover localized language-field semantics, bidirectional entry and focus,
keyboard traversal, and picker cancellation with draft preservation.

Two native checks remain in the sources but are not CI gates because their
result depends on the runner rather than the product: Android's
`MainActivityAccessibilityTest` (shell-injected key delivery varies between
identical runs) and `macos/RunnerUITests/NativeExportPanelUITests` (the hosted
XCUI client lacks Accessibility trust). CI does gate the iOS
`LanguageFieldAccessibilityTests` XCUI target on a pinned iPhone 17/iOS 26.2
Simulator: it checks localized native field labels and values, synthesized
input, focus continuity between fields, and system-picker presentation with
Cancel preserving the draft. It does not use software-keyboard visibility as
an assertion. CI still does not observe Android native language-field behaviour
with shell-injected key delivery, or the macOS save panel's accessibility and
cancel-preserves-draft path. Those behaviours need runners with the required
key-delivery and accessibility conditions; the audits below record the evidence.
All retained native checks still fail on missing profiles or inaccessible fields
rather than skipping.

None of these checks validates TalkBack/VoiceOver speech or gestures,
physical-device or physical-keyboard behavior. Native execution requires the CI
profiles; no local widget-test result substitutes for it. Wait budgets are
configured in the workflow and passed to the native tests.
These are validation builds, not signed release artifacts. Linux remains
intentionally unscaffolded: Kotoha has not adopted or verified a GTK-free host
against its pinned Flutter version, dependencies, accessibility needs, and CI.
Flutter's generic Engine API is not a complete host, and Flutter's
`file_selector_linux` package links GTK. The Ubuntu test job does not claim a Linux desktop build; see
`design/text_import_audit.md` for the assessed host and import blockers.
