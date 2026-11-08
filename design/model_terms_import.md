# Android model-package terms review (initial increment)

Android uses the system SAF directory picker with a temporary read-only grant;
Kotoha never requests or takes persistable URI permission. It reads the
package-root `model_manifest.json`, then only terms files declared in the
manifest and bound to `files` rows with role `terms`. The directory pick uses
the shared 16-bit `SharedActivityRequestCodes` pool with text import, so picks
never collide; detached selections leave late-result tombstones.

`ModelTermsImport` strictly validates the full `model_manifest.schema.json`
structure used here: required top-level keys with no extras, `id`/`engine_id`/
`adapter_id`/capability/`terms.id` patterns, executor/tasks/resources shapes
including the `storage_bytes` total, and exact complete terms coverage with
unique term IDs, and unique covered paths per entry. Multiple term records may
refer to the same terms file; each unique terms-role file must be represented by
a review record. Safe relative paths, exact byte lengths and SHA-256 values, and
strict UTF-8 are required before rendering. Every declared terms file is verified
once before the reviewer runs; unreferenced terms-role files fail closed. Package
ID and publisher are shown as unverified manifest claims.

Bounds are 1 MiB for the manifest, 1 MiB per terms file, and 4 MiB total
unique terms bytes (configurable in `ModelTermsImport`). Native reads enforce
the supplied per-file bound, consuming at most one sentinel byte to detect an
over-limit stream; the protocol ceiling is 4 MiB. No weight file is read,
copied, installed, or inferred, and no engine is invoked.

Consent is session-only: acceptance returns only an in-memory SHA-256 binding
for manifest and terms, held as `EphemeralModelAuthorization` in volatile
widget state, cleared on a new, declined, or failed review and on disposal, and
never persisted. The temporary directory grant is released after review; that
does not clear the digest binding for this app session. The binding is not runtime
authorization.

The review UI presents every verified document with its full text, usage
requirements, and required attributions, plus the unique verified terms-file
count, a runtime-disabled notice, and an integrity-only notice: hashes prove only that
the bytes read match the manifest; they do not prove origin, authenticity,
signature/provenance, or license approval. The engine remains disabled.

SHA-256 uses Dart `crypto` 3.0.8 (direct dependency). Pub archive
`sha256:e3626ae6270383c9e3a549f34c9e4cd26c09ae6a9adaab2bf4737a00340efdc4`
from `pubspec.lock`; upstream `LICENSE` at
`dart-lang/core/crypto-v3.0.8/pkgs/crypto/LICENSE` has
`SHA-256:ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`
with BSD-3-Clause terms (permissive). The full notice is bundled at
`assets/licenses/crypto-3.0.8.txt` and user-accessible through
`LicenseRegistry`/`showLicensePage` alongside the Unicode notice.

Use synthetic package providers only.
