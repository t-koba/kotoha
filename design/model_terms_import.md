# Android model-package terms review (initial increment)

Android uses the system SAF directory picker with a temporary read-only grant;
Kotoha never requests or takes persistable URI permission. The plugin keeps the
selected tree URI only in volatile state and drops that reference when released,
replaced by a new selection, or detached. It does not call
`Context.revokeUriPermission(Uri, int)`: Android 15 `Context.java` documents that
overload as removing matching grants for any package and grant mechanism, so it
could revoke another app's matching access. The target-package overload is not
equivalent; its documented scope excludes activity-launch and other
non-`grantUriPermission` mechanisms. Because the SAF result grant is temporary
and no persistable flag is requested, Kotoha drops its own handle rather than
causing cross-package revocation. The OS controls the grant's remaining lifetime;
this implementation does not claim immediate platform-level revocation. A
rejected `content:` result is not retained or read. Synthetic instrumentation
verifies that release/reselection stop further plugin reads and that no global
revoke call is made; it does not exercise live DocumentsUI/provider grant
behavior. Source: Android 15
[`Context.java`](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-15.0.0_r1/core/java/android/content/Context.java#6830).

It reads the
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
over-limit stream; the protocol ceiling is 4 MiB. Terms review itself opens no
weight file, and accepting terms enables nothing.

After acceptance, the user can separately and explicitly choose **Verify model
files**. A distinct session-only dialog explains that declared non-terms files
will be streamed and hashed in place. The user is asked for a fresh temporary
(read-only, non-persistable) directory selection for that one check; no URI is
kept past the operation. The native plugin validates each declared path,
positive length and lowercase SHA-256, then streams the file through a fixed
8 KiB buffer with one sentinel byte after the declared length to catch extra
data. Per-file and total bounds are 2 GiB and 4 GiB, with at most 64 files.
Only a boolean reply crosses back to Dart: no weight bytes are copied into
Dart, stored, cached, bundled, downloaded, or handed to an engine. A hash
matching the manifest is not proof of origin, authenticity, or licensing, and
this check adds no runtime, platform-support, quality, or adoption claim.

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

Model-status notices use fixed localized text only: package-supplied names, paths, digests, exceptions and caller text are never echoed. Starting a new review invalidates the prior digest binding and removes any tracked model-status notice; the same flush runs before showing a newer model status. Because Flutter's public `ScaffoldMessengerState` API cannot remove one specific queued `SnackBar`, clearing a tracked status also clears the whole shared queue, so an ordinary notice queued behind it is dropped. This documented tradeoff keeps a stale acceptance or integrity message from resurfacing after its binding is gone.

Native verification uses `MessageDigest.getInstance("SHA-256")`. Native reads
and streaming hashes share the plugin's single busy slot: release, detach,
reselect, and a missing selection stop the operation, close the stream, and
reply with an error (`released`, `detached`, `busy`, or `cancelled`); mismatches
reply false. There is no retry, cache, or persisted result.

SHA-256 uses Dart `crypto` 3.0.8 (direct dependency). Pub archive
`sha256:e3626ae6270383c9e3a549f34c9e4cd26c09ae6a9adaab2bf4737a00340efdc4`
from `pubspec.lock`; upstream `LICENSE` at
`dart-lang/core/crypto-v3.0.8/pkgs/crypto/LICENSE` has
`SHA-256:ad6a71997da90924b2cfb1fb47ec46537f70faf469efe016168794ae45ed6888`
with BSD-3-Clause terms (permissive). The full notice is bundled at
`assets/licenses/crypto-3.0.8.txt` and user-accessible through
`LicenseRegistry`/`showLicensePage` alongside the Unicode notice.

Instrumentation uses synthetic package providers only; it does not exercise
live DocumentsUI/provider grant behavior. The only path that opens a declared
weight file is the explicit integrity check above: it streams bytes in place
and returns only a status, never the bytes or a stored artifact.
