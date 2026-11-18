# Translation-route audit

## Current product state

`lib/main.dart` implements a manual text workspace: users can enter text, import supported text documents, edit separate translation fields, and copy or export field contents. The UI labels translation entry as manual and explicitly says that automatic translation is not provided. This describes the current route; it does not claim that the app processes no material.

The iOS deployment target is iOS 15. No translation engine is currently adopted. The design target and current route are distinct (`design/kotoha_design.md` §§7.1, 11, 18 and 21).

## Apple Translation candidate (installed-only initializer; iOS 26+)

Apple documents the `TranslationSession` class and `LanguageAvailability` on iOS/iPadOS 18.0+, with translation performed on-device. This class-level availability does not make every initializer available on that OS. Apple may collect API usage and performance metrics including the app bundle ID and language pair, but not translation content. This is an iOS-specific candidate, not a cross-platform route.

`LanguageAvailability.status(from:to:)` and its `.installed` state are available on iOS/iPadOS 18.0+ and report language-pair installation status. A static list or a guess does not establish which pairs are supported. A status check does not configure a session to forbid downloads.

The direct `TranslationSession.init(installedSource:target:)` initializer is introduced in iOS/iPadOS 26.0, not iOS 18; it requires the languages to be installed and throws if they are absent. SwiftUI `.translationTask` is available earlier but can always request system-authorized downloads when assets are missing. The documented `canRequestDownloads` property is also iOS/iPadOS 26.0+, so the reviewed API material does not establish an iOS 18 session that guarantees no download request. The iOS 26 initializer is not an iOS 18 route. An iOS 18 installed-only route remains out of scope until a distinct documented mechanism is established.

### Smallest candidate flow

- One explicit action translates one text field for one selected source/target pair.
- The action is available only when dynamic availability says the pair is supported and already installed.
- The source stays unchanged; the result goes into a separate editable field.
- This slice covers only text, not documents, images, audio, video, or other modalities.

### Evidence and release gates not met

- Physical iOS/iPadOS 26+ runtime test on an actually available pair, including translation quality. No physical test device/session is currently available; no distinct installed-only iOS 18 route is established.
- Offline behavior, error handling and cancellation.
- An iOS 26 installed-only route requires testing no-download error behavior when assets are absent. An earlier `.translationTask` route requires testing the system download-consent flow; its documented session can request downloads and is not equivalent to an installed-only initializer.
- Disclosure of relevant system metrics and review of the privacy policy and telemetry disclosures.
- The public API material reviewed exposes neither model identity/version, provenance, nor model license/redistribution terms. Kotoha would not package OS assets; the API material does not establish that the model is open or that Kotoha may redistribute it.

No route is evidence-complete now. Automatic translation and all engine adoption remain disabled.

## Browser built-in translation API candidate (desktop only)

MDN documents experimental `Translator` and `LanguageDetector` web APIs that translate text and detect language through a browser-managed internal AI model, which may differ between browsers, instead of an app-bundled engine. Creation requires a secure context and recent user activation; access is gated by the `Permissions-Policy` `translator`/`language-detector` directives; pending `create()`/`detect()`/`translate()` operations can be cancelled with an `AbortController`; and `destroy()` releases the model's resources. These are documented interface capabilities, not a Kotoha runtime observation.

MDN browser-compat data records `Translator` and each reviewed member (`availability()`, `create()`, `destroy()`, `inputQuota`, `measureInputUsage()`) as Chrome 138 and Edge 148, with `chrome_android: false`, `webview_android: "mirror"` (so Android WebView is unsupported), Firefox/Safari/Deno/Node.js `false`, status experimental, and the note that availability "may be subject to geographical restrictions." A search excerpt of Chrome's developer documentation states these APIs "work in Chrome on desktop" and "don't work on mobile devices." The excerpt is not independently verified here.

Consequence for this Android-first product: the browser-managed on-device translation API, a browser route that would avoid an app-bundled engine and model weights, is unavailable on Android Chrome and Android WebView. A browser path on the target platform would still require the separately inspected WASM/worker engine route, whose real inference, offline reload, cancellation cleanup, model consent, resource and mobile evidence remain unproven. Search excerpts, not independently verified here, indicate that even that route's acceleration prerequisites are constrained on mobile: WebGPU has limited availability (Android Chrome 121+ only on Android 12+ with Qualcomm/ARM GPUs), and multithreaded WASM needs cross-origin isolation (COOP/COEP) for `SharedArrayBuffer`.

The built-in API also exposes no documented model identity/version, provenance or redistribution terms, and depends on browser/OS-managed language-pack downloads whose consent and offline lifecycle are not established here. No browser support claim, model-rights conclusion or adoption follows. Rights, offline, consent and adoption gates stay unresolved; automatic translation and engine adoption remain disabled.

## PLaMo model license terms (candidate model rights)

The candidate model family discussed in the browser and native probes, PLaMo 3 Translate, is licensed separately from any engine runtime. PFN's own [`plamo-translate-cli` README](https://github.com/pfnet/plamo-translate-cli/blob/main/README.md) states that the CLI source is Apache-2.0, while the models it downloads — `pfnet/plamo-3-translate-2b`, its GGUF, the `0.8b-GGUF` draft and the PLaMo 2 Translate models — are distributed under the PLaMo Community License, not Apache-2.0.

That first-party README summarizes the license terms as: personal and non-commercial use, including academic use, is free and needs no registration; commercial use is free when the revenue or sales of the user or its affiliates in the most recent fiscal year were 1 billion yen or less, after registering through PFN's commercial-use form, with use inside an organization counted as commercial use, and a separate PFN agreement required above that threshold; published translations must be indicated as model output (Article 5); and providing the models or their output to others requires a copy of the license for recipients, "Built with PLaMo" in related websites/interfaces/documentation, and "PLaMo" in the names of derived models (Article 4). The README expressly states that the license text is authoritative and its summary is not. The authoritative license host (`plamo.preferredai.jp`) and the model-card license were refused by this environment's destination decider, so the exact binding text was not retrieved here; search excerpts of the agreement (not independently verified here) corroborate the non-exclusive, worldwide, non-transferable, royalty-free grant, the registration and revenue threshold, and the redistribution/attribution obligations, but are not the authoritative text.

Attempts to bind the authoritative full text failed within this environment's fetch policy: `plamo.preferredai.jp`, `huggingface.co` and `imoz.jp` were each refused by the destination decider, and PFN's own `plamo-translate-cli` git tree contains only the Apache-2.0 CLI `LICENSE` and the summary README, no vendored copy of the Community License (tree root `82788925ce64b5ec15abb25a650ccf4616eff57a`; repository/author searches returned no vendored full-text mirror). Verbatim Articles 1–5 text appears only in search excerpts, which are not independently verified or bound to exact source bytes. Those excerpts also report that the agreement is a moving document: established 2025-02-25 and revised 2026-11-09 (Hugging Face commit `8b797b290907c84403877cb9d03150929f10b467`), with PFN able to modify it after notice and terminate on breach. Any future binding must therefore pin an exact revision, not just a URL. No authoritative full-text SHA-256 is established here.

These documented terms do not close the rights gate. No evidence establishes that Kotoha or its operator qualifies for the no-registration or <=1-billion-yen free commercial tier, or has completed PFN registration. Adopting the model would carry the Article 4 attribution/naming and Article 5 output-labeling obligations into product notices and UI; no such notice is added here, no weights were downloaded or bundled, and no engine is adopted. The authoritative license text, the exact language pair and conversion/GGUF route, translation quality, and the platform runtime evidence remain to be established before any rights or adoption decision.

## Other engine route and decision

Existing llama.cpp/NDK/model provenance, notice, and redistribution gates remain unresolved. No weights were downloaded or bundled. Model licenses, language-pair support, and device behavior remain unestablished without evidence.

The current decision is to retain the manual text workspace and not enable automatic translation or adopt an engine until the evidence and release gates above are met. This is consistent with the on-device, rights-boundary, privacy, and acceptance requirements in `design/kotoha_design.md` §§7.1, 11, 18 and 21.
