# Translation-route audit

## Current product state

`lib/main.dart` implements a manual text workspace: users can enter text, import supported text documents, edit separate translation fields, and copy or export field contents. The UI labels translation entry as manual and explicitly says that automatic translation is not provided. This describes the current route; it does not claim that the app processes no material.

The iOS deployment target is iOS 15. No translation engine is currently adopted. The design target and current route must not be confused: see `design/kotoha_design.md` §§7.1, 11, 18 and 21.

## Apple Translation candidate (iOS only)

Apple's official `TranslationSession` documentation states that the API is available on iOS/iPadOS 18 and translates on-device. Apple may collect API usage and performance metrics including the app bundle ID and language pair, but not translation content. This is an iOS-specific candidate, not a cross-platform route. [Source: `mizu_fetch/db359b8259e53fa176ab79d1ef163c7c6e21f6507581d71326e34493b82450bb`; SHA-256 `254229dc21a6fda52d7d8dd91827b093cfb1f599df3a5e25e0e95e4b883082bf`]

`LanguageAvailability` reports the actual status of a requested language pair dynamically; do not infer support from a static list or guess which pairs work. [Source: `mizu_fetch/631091c59978e16a93bdf07b1543b5ed2cf2532199fb79769975f46cdac5b176`; SHA-256 `c2969bb7d256956a259d1b85c3d3f44310e3c953e614860809677cc4c89f4d2b`]

The `TranslationSession` installed-source initializer requires languages to be installed and reports errors if they are absent. SwiftUI `.translationTask` can request that the system authorize downloads for missing languages. The API page's `canRequestDownloads` property is iOS 26+; it must not be presented as available on iOS 18. An iOS 18 slice can avoid app-triggered downloads by using the installed-source initializer. [Source: `mizu_fetch/4c78559f1a2845d10b9df299da8aef20555e21112ff05242a80723cacc47754b`; SHA-256 `b7714005f67d7479a1aee8369157f747866f674bd844c9ee635f5f45b3cbe801`]

### Smallest candidate flow

- One explicit action translates one text field for one selected source/target pair.
- Offer the action only when dynamic availability says the pair is supported and already installed.
- Preserve the source unchanged; put the result in a separate editable field.
- Limit this slice to text; do not imply support for documents, images, audio, video, or other modalities.

### Evidence and release gates not met

- Physical iOS 18+ runtime test on an actually available pair, including translation quality. No physical test device/session is currently available.
- Offline behavior, error handling and cancellation.
- If system downloads are permitted in a future route, the system's download-consent flow and its effect must be tested; the installed-only candidate avoids app-triggered downloads.
- Disclose relevant system metrics and review the privacy policy and telemetry disclosures.
- The public API material reviewed exposes neither model identity/version, provenance, nor model license/redistribution terms. Kotoha would not package OS assets; do not represent this as an open model or claim rights to redistribute it.

No route is evidence-complete now. Keep automatic translation and all engine adoption disabled.

## Other engine route and decision

Existing llama.cpp/NDK/model provenance, notice, and redistribution gates remain unresolved. No weights were downloaded or bundled. Do not infer model licenses, language-pair support, or device behavior without evidence.

The current decision is to retain the manual text workspace and not enable automatic translation or adopt an engine until the evidence and release gates above are met. This is consistent with the on-device, rights-boundary, privacy, and acceptance requirements in `design/kotoha_design.md` §§7.1, 11, 18 and 21.
