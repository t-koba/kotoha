# Translation-route audit

## Current product state

`lib/main.dart` implements a manual text workspace: users can enter text, import supported text documents, edit separate translation fields, and copy or export field contents. The UI labels translation entry as manual and explicitly says that automatic translation is not provided. This describes the current route; it does not claim that the app processes no material.

The iOS deployment target is iOS 15. No translation engine is currently adopted. The design target and current route must not be confused: see `design/kotoha_design.md` §§7.1, 11, 18 and 21.

## Apple Translation candidate (installed-only initializer; iOS 26+)

Apple documents the `TranslationSession` class and `LanguageAvailability` on iOS/iPadOS 18.0+, with translation performed on-device. This class-level availability does not make every initializer available on that OS. Apple may collect API usage and performance metrics including the app bundle ID and language pair, but not translation content. This is an iOS-specific candidate, not a cross-platform route. [Sources: `mizu_fetch/db359b8259e53fa176ab79d1ef163c7c6e21f6507581d71326e34493b82450bb`, SHA-256 `254229dc21a6fda52d7d8dd91827b093cfb1f599df3a5e25e0e95e4b883082bf`; `mizu_fetch/37a6ec8dfaea96307b1ff4787e064ce9c25eb3a77e3f06f9545a191873a691ca`, SHA-256 `135641e5da8dd8808d99e76f336a55d2a12b3f0c553ff0f7ac6bc31ad17b3860`]

`LanguageAvailability.status(from:to:)` and its `.installed` state are available on iOS/iPadOS 18.0+ and report language-pair installation status; do not infer support from a static list or guess which pairs work. A status check does not configure a session to forbid downloads. [Sources: `mizu_fetch/e148ee2b93edbda461050f7bb0d4bef2e81164506fa148eca2f5bcba8a402b4b`, SHA-256 `f6f96d32b9df197a6c552440e53cd5ea9e79bddf793f76e9a953393ab997d380`; installed state `mizu_fetch/9a9507c236ab8525d6948fd64bccb8dd740bbf5250f1e6bd4399dae1db498965`, SHA-256 `64c08cccc2968e9996d604106efcd15f16a7ee892b960760f1181f1d4b451345`]

The direct `TranslationSession.init(installedSource:target:)` initializer is introduced in iOS/iPadOS 26.0, not iOS 18; it requires the languages to be installed and throws if they are absent. SwiftUI `.translationTask` is available earlier but can always request system-authorized downloads when assets are missing. The documented `canRequestDownloads` property is also iOS/iPadOS 26.0+, so the reviewed API material does not establish an iOS 18 session that guarantees no download request. Do not describe the iOS 26 initializer as an iOS 18 route or offer an iOS 18 installed-only route until a distinct documented mechanism is established. [Sources: installed-source initializer `mizu_fetch/37a6ec8dfaea96307b1ff4787e064ce9c25eb3a77e3f06f9545a191873a691ca`, SHA-256 `135641e5da8dd8808d99e76f336a55d2a12b3f0c553ff0f7ac6bc31ad17b3860`; `canRequestDownloads` `mizu_fetch/aebd3f29c1535b123d3e66320b19c0654154cfcd136acd5903823e2186399826`, SHA-256 `b7714005f67d7479a1aee8369157f747866f674bd844c9ee635f5f45b3cbe801`]

### Smallest candidate flow

- One explicit action translates one text field for one selected source/target pair.
- Offer the action only when dynamic availability says the pair is supported and already installed.
- Preserve the source unchanged; put the result in a separate editable field.
- Limit this slice to text; do not imply support for documents, images, audio, video, or other modalities.

### Evidence and release gates not met

- Physical iOS/iPadOS 26+ runtime test on an actually available pair, including translation quality. No physical test device/session is currently available; no distinct installed-only iOS 18 route is established.
- Offline behavior, error handling and cancellation.
- For an iOS 26 installed-only route, test the no-download error behavior when assets are absent. For an earlier `.translationTask` route, test the system download-consent flow; its documented session can request downloads and is not equivalent to an installed-only initializer.
- Disclose relevant system metrics and review the privacy policy and telemetry disclosures.
- The public API material reviewed exposes neither model identity/version, provenance, nor model license/redistribution terms. Kotoha would not package OS assets; do not represent this as an open model or claim rights to redistribute it.

No route is evidence-complete now. Keep automatic translation and all engine adoption disabled.

## Browser built-in translation API candidate (desktop only)

MDN documents experimental `Translator` and `LanguageDetector` web APIs that translate text and detect language through a browser-managed internal AI model, which may differ between browsers, instead of an app-bundled engine. Creation requires a secure context and recent user activation; access is gated by the `Permissions-Policy` `translator`/`language-detector` directives; pending `create()`/`detect()`/`translate()` operations can be cancelled with an `AbortController`; and `destroy()` releases the model's resources. These are documented interface capabilities, not a Kotoha runtime observation. [Source: `mizu_fetch/2527a783438876e7678799ae50f5654b69ccec6a6a5086d629f1cd074420dfc6`, SHA-256 `6674a38b8da881a83557de69a8004a486ac2d28ff99d5b5e6a8ae3df1daada45`]

MDN browser-compat data records `Translator` and each reviewed member (`availability()`, `create()`, `destroy()`, `inputQuota`, `measureInputUsage()`) as Chrome 138 and Edge 148, with `chrome_android: false`, `webview_android: "mirror"` (so Android WebView is unsupported), Firefox/Safari/Deno/Node.js `false`, status experimental, and the note that availability "may be subject to geographical restrictions." Chrome's own developer documentation states these APIs "work in Chrome on desktop" and "don't work on mobile devices." [Sources: `mizu_fetch/4fd386da4c10eeffa5d0df898ed36c4703e75cd4d3db57c6f5b599adfb7d6ba1`, SHA-256 `258db1f5486eb438701ba04b0c99045815722fda8edea4957f55245cc7bc2799`; Chrome documentation excerpt from search `sources/search-a25cb2f76d70ea3f5b6a313833f836e6a3ee4673ebb8b31629bd820871b82420`, external-untrusted]

Consequence for this Android-first product: the browser-managed on-device translation API, a browser route that would avoid an app-bundled engine and model weights, is unavailable on Android Chrome and Android WebView. A browser path on the target platform would still require the separately inspected WASM/worker engine route, whose real inference, offline reload, cancellation cleanup, model consent, resource and mobile evidence remain unproven. Even that route's acceleration prerequisites are constrained on mobile: WebGPU has limited availability (Android Chrome 121+ only on Android 12+ with Qualcomm/ARM GPUs), and multithreaded WASM needs cross-origin isolation (COOP/COEP) for `SharedArrayBuffer`. [External-untrusted search excerpts: `sources/search-c3118c94f6dc815f0a42fc078a300600a87bff169460e61391712f011ba41b13`]

The built-in API also exposes no documented model identity/version, provenance or redistribution terms, and depends on browser/OS-managed language-pack downloads whose consent and offline lifecycle are not established here. No browser support claim, model-rights conclusion or adoption follows. Rights, offline, consent and adoption gates stay unresolved; automatic translation and engine adoption remain disabled.

## Other engine route and decision

Existing llama.cpp/NDK/model provenance, notice, and redistribution gates remain unresolved. No weights were downloaded or bundled. Do not infer model licenses, language-pair support, or device behavior without evidence.

The current decision is to retain the manual text workspace and not enable automatic translation or adopt an engine until the evidence and release gates above are met. This is consistent with the on-device, rights-boundary, privacy, and acceptance requirements in `design/kotoha_design.md` §§7.1, 11, 18 and 21.
