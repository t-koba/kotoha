# Editor localization

`app_ja.arb` and `app_en.arb` own the app's Japanese and English messages.
Regenerate the committed Dart files with `flutter gen-l10n` using the configured
Flutter 3.47.9 SDK; `flutter pub get` also generates them. `l10n.yaml` puts Japanese
first, so device locales resolve to Japanese or English (including regional
variants) and unsupported locales fall back to Japanese. iOS and macOS bundle
metadata and Xcode known-region lists also include `ja` and `en`.
The app-bar language menu overrides the device choice for the current session
only; it neither changes source/target language fields nor saves text or preferences.

## Dependency and license evidence

- `flutter_localizations` comes from Flutter 3.47.9, revision
  `c197ca5199e9ee5661e865596c9c07294dfab51c`,
  <https://github.com/flutter/flutter/tree/c197ca5199e9ee5661e865596c9c07294dfab51c/packages/flutter_localizations>.
  Its library headers refer to the root `LICENSE`, which permits source and
  binary redistribution with modification subject to notice retention,
  disclaimer reproduction and no endorsement. Selected expression/term:
  BSD-3-Clause; classification: permissive; no excluded or unknown terms.
  Root `LICENSE` SHA-256:
  `a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20`.
  Package `pubspec.yaml` SHA-256:
  `b2acbef033f4674f0b862daa4127146e6025566ee0045bc733cc8107756fb957`.
- The generated localization code imports `intl`, which is required by
  `flutter_localizations`; `intl: any` is therefore declared directly. The
  versioned upstream record is <https://pub.dev/packages/intl/versions/0.20.3>;
  source `LICENSE` and `pubspec.yaml` are at
  <https://github.com/dart-lang/i18n/tree/intl-v0.20.3/pkgs/intl>. The full
  license permits source and binary redistribution with modification subject
  to notice retention, disclaimer reproduction and no endorsement. Selected
  expression/term: BSD-3-Clause; classification: permissive. `LICENSE` SHA-256:
  `7e124af6a556f045cb3a20cafbdaa31602ac2c82cbcb3c3b15faaaf514b06028`;
  `pubspec.yaml` SHA-256:
  `e4dd54c2d05d7d9c0cf7a38ba91f7687d92f30dabbd1232bcc2b0786e36800d4`.
  `pubspec.lock` pins version 0.20.3 and archive SHA-256
  `1ca20c894b1717686a2319b8548763d812bc0aabdac580420a44c5178c57a867`.
  Its `clock`, `meta`, and `path` dependencies were already locked.

The only new hosted package is the SDK-required `intl`; localization adds no
native libraries or model assets. The existing license page exposes the bundled
notices and disclaimers. Framework controls and the license page use Flutter's
localization delegates.
