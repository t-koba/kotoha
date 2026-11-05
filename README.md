# Kotoha (ことは)

Kotoha is an on-device multilingual workspace. The first runnable interface is a
manual text-workspace draft: enter a source text, add one or more target languages,
and write translations without an installed model. It does not claim to translate
text automatically.

This development build does not yet save drafts. The product design requires saved
content to use encrypted storage and protected key management; persistence will be
added when its reviewed dependencies are available. Do not enter sensitive text in
this temporary build.

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
runners. These are validation builds, not signed release artifacts. Linux remains
intentionally unscaffolded until its host can use the designed non-GTK Flutter
Engine embedding; the Ubuntu test job does not claim a Linux desktop build.
