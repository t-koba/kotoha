# Kotoha (ことは)

Kotoha is an on-device multilingual workspace. The first runnable interface is a
manual text-workspace draft: enter a source text, add one or more target languages,
and write translations without an installed model. It does not claim to translate
text automatically.

The source editor can import UTF-8 `.txt`, `.md` and `.markdown` documents through
an explicit system picker on macOS/Windows and the Android/iOS adapters.
Import replaces only source text after consent; translations remain manual and
all drafts stay in memory. Kotoha does not stage a cache copy, persist document
grants, or add a network client, but the OS/provider may download or stage a file.
Mobile native compilation and picker execution still need hosted validation;
see `design/text_import_audit.md` for the data flow and evidence boundaries.

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
Flutter analysis and tests on pushes to `dev`, `mizu`, or `mizu/dev`, pull requests,
and manual dispatch. It also builds debug apps on Android, iOS/macOS, and Windows
runners. On the same pinned mobile profiles used for privacy callback tests,
native tests inspect localized source/target language-field names and values during
Arabic-to-Latin edits under English and Japanese app UI locales, and check
synthesized text input/focus continuity (Android also checks forward/reverse Tab).
iOS uses a minimal XCUI test target; the hosted unit-test target still checks
privacy callbacks.

These tests do not validate TalkBack/VoiceOver speech or gestures, physical-device
or physical-keyboard behavior. Native execution requires those CI profiles; no local
widget-test result substitutes for it. Wait budgets are configured in the workflow
and passed to the native tests; missing profiles and inaccessible fields fail, not skip.
These are validation builds, not signed release artifacts. Linux remains
intentionally unscaffolded until its host can use the designed non-GTK Flutter
Engine embedding; the Ubuntu test job does not claim a Linux desktop build.
