# SQLCipher candidate dependency audit

**Status: blocked; not approved for distribution or draft persistence.**
This is a static review of the 17 SQLCipher candidates pinned by `sqlite3` 3.9.0,
not a claim about shipped Kotoha binaries. The current `pubspec.yaml` and lockfile
contain no `sqlite3` dependency or SQLCipher hook selection. No native library was
executed, no target-platform behavior was tested, and no user text was persisted.
The governing rules are [dependency_policy.json](specs/dependency_policy.json).

## Provider finding

Every candidate contains a NUL-terminated `4.20.0` string. All four Android,
five Linux and three Windows candidates contain `OpenSSL 4.1.0 23 Oct 2026`
and `sqlcipher_openssl_` implementation strings. All nine ELF candidates also
define `EVP_EncryptInit_ex` rather than importing it. None of these twelve
libraries names an external OpenSSL library in its inspected dependency table.
Together these are evidence that OpenSSL code is included, not merely supplied by
the OS. The Windows finding uses implementation/version strings and the PE import
table; it is not a reconstructed build manifest.

All five Apple candidates instead contain `_sqlcipher_cc_setup`,
`_CCCryptorCreate` and `_CCKeyDerivationPBKDF`, have system framework/library
load commands, and contain no `OpenSSL ` string. This supports CommonCrypto as
the platform-provided provider; absence of a string alone would not prove it.

The package's `doc/hook.md` says OpenSSL is linked on Android, Linux and Windows.
That agrees with these exact artifacts. A generic SQLCipher Community Android
matrix describing LibTomCrypt 1.18.2 does **not** identify the provider of these
sqlite3.dart binaries. Do not substitute that matrix's license closure for this
inventory. Static evidence settles this provider discrepancy, not the complete
build provenance or all embedded third-party code. The operator-approved LibTomCrypt
1.18.2 terms apply to the upstream Community Android package, not to this candidate;
they do not replace the OpenSSL review for these exact assets.

## Evidence and source identity

Candidate URLs are
`https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.9.0/<filename>`.
The filenames below are the exact release names, including `ios_sim` and `ia32`.
Every cached asset was rehashed and matched both its filename's entry in
`lib/src/hook/asset_hashes.dart` and the complete 17-entry SQLCipher set there.
A package pin is an integrity reference, not independent authentication of the
publisher or a source-to-binary reproducibility proof. The package's `doc/hook.md`
advertises SLSA level 3 attestations and CycloneDX SBOMs through GitHub
attestations. The [GitHub release API response](https://api.github.com/repos/simolus3/sqlite3.dart/releases/tags/sqlite3-3.9.0)
has SHA-256
`059f48b2cad716889157567106ca3a89df6b45d05cf2b5e0ffb29f734ddb8423`, reports
`immutable: true`, 53 assets including 17 SQLCipher candidates, and the exact
Android ARM64 asset digest `e615e2750c5fa455d5a7e70fe4df86c3a2f5696367ceb021d46a9262120df046`.
The upstream `asset_hashes.dart` at [package commit
`28bd9b4cd33f02cff3ded6836459ba609a6016cc`](https://github.com/simolus3/sqlite3.dart/commit/28bd9b4cd33f02cff3ded6836459ba609a6016cc)
hashes to `f95b40332e3087c1a0f5c1a75729b511305903ee0e07e5ebfb70b6d4b22b37fc`,
the same digest as the cached file below. These are API/source-content claims;
the [GitHub commit API](https://api.github.com/repos/simolus3/sqlite3.dart/commits/sqlite3-3.9.0)
reports that package commit unsigned. Hash agreement alone establishes neither
source authenticity nor the release response.

The GitHub attestations API response for the target digest (SHA-256
`8c7ee7b34454186a02468b0bc115d85f23eeced6acc334c54281dc31ec25c023`, 140,873 bytes)
was parsed in an isolated experiment; signatures and the trust chain were not
verified. The response contains one release statement, three SLSA provenance
statements and three CycloneDX 1.7 BOM statements. Every decoded, unverified
subject set includes the exact Android ARM64 hash. The three decoded BOMs have
the same component/version inventory: 17 SQLCipher binary assets and version-only
SQLCipher 4.20.0 / OpenSSL 4.1.0 entries. Their declared SQLCipher/OpenSSL
license expressions use a singular `license` property. The official CycloneDX
1.7 schema requires component `type` and `name`, allows `licenses` (plural), and
rejects unknown properties, so these two BOM component entries do not satisfy
the schema. Do not use the fetched BOM as a valid license inventory.

The decoded SLSA predicates name the package source commit and
`compile_sqlite.yml` workflow, but list only the `sqlite3.dart` source commit as
a resolved dependency. They do not bind the SQLCipher/OpenSSL source archives
or build inputs.

The package downloads the SQLCipher v4.20.0 generated tag ZIP. GitHub's
[SQLCipher release API](https://api.github.com/repos/sqlcipher/sqlcipher/releases/tags/v4.20.0)
response (SHA-256 `461b6b7a5f99970f1267d297cd457f036fa3b203aead9830d706d65024c928f3`)
reports the release as mutable with no uploaded assets; the tag currently
resolves to unsigned commit `355d4db92d3404e71faa8088d071a71d767807f4` (commit
API response SHA-256
`9652931d4973fe6db271b166def0cdc906e5d8f3a3df79df0ecaafb5d9ea03af`). No
published digest for the generated ZIP was found.

The workflow downloads the OpenSSL 4.1.0 GitHub release asset at the exact URL
shown in `compile_sqlite.yml`. GitHub's [OpenSSL release API](https://api.github.com/repos/openssl/openssl/releases/tags/openssl-4.1.0)
response (SHA-256 `30d1fcc60452a43c2784094e076dbe3e56ab7ab0f4d36147b70503d6d040d5f1`)
reports the archive digest as `50c17baf54cb008f6ce42d50deb4b28050a1aad711636cabd4b241c7e90cc2fd`,
but the release is marked mutable and the build does not verify that digest.
The tag resolves to unsigned commit `2f4e3a5fec05394068cfa7379890ab552483a8a6`
(commit API response SHA-256
`d22a3269c15f93f8995e2b11ef62db02b013784e5359d0782774bdc39308cc2c`). These API
claims were not independently authenticated.

The pinned [`download_sqlite.dart`](https://github.com/simolus3/sqlite3.dart/blob/28bd9b4cd33f02cff3ded6836459ba609a6016cc/tool/download_sqlite.dart)
uses `curl -L` and `unzip` for the SQLite 3.54.1, SQLite3MultipleCiphers 2.6.1
and SQLCipher v4.20.0 archives without checking their hashes. For the SQLCipher
fork it runs `configure` and `make sqlite3.c -j`, then copies the amalgamation
for compilation; the other two source trees are separate forks. The package's
[`build_openssl.dart`](https://github.com/simolus3/sqlite3.dart/blob/28bd9b4cd33f02cff3ded6836459ba609a6016cc/tool/build_openssl.dart)
configures static libraries, disables SSL/TLS, engines/modules, FIPS, legacy
and multiple algorithms; `no-apps` is commented out. Its
[`build_sqlite.dart`](https://github.com/simolus3/sqlite3.dart/blob/28bd9b4cd33f02cff3ded6836459ba609a6016cc/tool/build_sqlite.dart)
links the OpenSSL `crypto` archive on Android, Linux and Windows, selects
CommonCrypto on Apple, sets the SQLCipher codec/temp-store/init flags, and adds
Windows system libraries. These source recipes corroborate linkage intent, but
do not prove which downloaded archive bytes or complete code closure reached
any candidate binary.

The workflow's source and binary caches key on the download/build scripts,
target and version, not external archive digests. The workflow therefore permits
cache reuse without checking the exact source bytes; no claim is made about a
cache hit for these release assets.

The SQLCipher source tree at the unsigned tag commit also contains
[`SQLITE_LICENSE.md`](https://github.com/sqlcipher/sqlcipher/blob/355d4db92d3404e71faa8088d071a71d767807f4/SQLITE_LICENSE.md)
(SHA-256 `595e823c2ada6c839679e693bee1f4d7f88e2d34ac99a913ae41e3d43fb10c7d`), which
states that SQLite source and the `sqlite3.c`/`sqlite3.h` products are public
domain; it identifies BSD-style licenses on helper build scripts that do not
reach those products. This supports the provisional SQLite classification, but
does not prove which source bytes reached the candidate binary.

The [OpenSSL tag's root listing](https://api.github.com/repos/openssl/openssl/contents?ref=2f4e3a5fec05394068cfa7379890ab552483a8a6)
(response SHA-256 `afbda0fea57670542fd980184eacda30c98eb72011e64f2a7fe58c8c0af68fc0`)
contains `LICENSE.txt` and [`ACKNOWLEDGEMENTS.md`](https://github.com/openssl/openssl/blob/2f4e3a5fec05394068cfa7379890ab552483a8a6/ACKNOWLEDGEMENTS.md)
among license/notice-named files. The latter (SHA-256
`58dee45791f007ced048114717f86672778fe75c551827c57e760861446ce3c3`)
points to a live acknowledgements page, not a static third-party license
inventory. No root-level `NOTICE` file appears in the listing; nested or
feature-specific notices in the source archive or exact static library closure
remain unresolved.

| Upstream source at [package commit `28bd9b4cd33f02cff3ded6836459ba609a6016cc`](https://github.com/simolus3/sqlite3.dart/commit/28bd9b4cd33f02cff3ded6836459ba609a6016cc) | SHA-256 |
|---|---|
| `.github/workflows/compile_sqlite.yml` | `aa1b6f704441343a0ae26b3105dc2547cce9bf618b2f8b0afffa6ad5bd40672b` |
| `tool/download_sqlite.dart` | `eee9da6fdb8a34938a635bcaa3ff2c682df0cfb414a0577dcf530f94ddbeb0d4` |
| `tool/build_openssl.dart` | `ba0abd6df0914be382767d4868c7818da7c77f349eabc9f87fe07ab05f405b3f` |
| `tool/build_sqlite.dart` | `9fae2ddddb8e01fd05236cc438e9bcf1e0d34acc0fdd7019ca8cefdc8c40f635` |
| `tool/generate_sbom.dart` | `be2930ea2f2b0a4d8e8ca19d50983566f8b8816ef8b54e1845d1a5f270f2ff9d` |

The SBOM generator itself emits SQLCipher/OpenSSL components with the singular
`license` property and without required `type`/`name`, matching the malformed
BOM payload. A schema-level check of the [CycloneDX 1.7 JSON
schema](https://raw.githubusercontent.com/CycloneDX/specification/1.7/schema/bom-1.7.schema.json),
SHA-256 `df472ef4aaf593904c479293723a1a5c191d6672715c93b3c0b5c318f3914221`,
confirmed those constraints. The fetched attestation response includes temporary
signed bundle URLs; only the response digest and safe parsed facts are recorded
here, not the raw body or those URLs. Treat all attestation payloads as
unverified until a trusted verifier checks them.

Package source: <https://pub.dev/packages/sqlite3/versions/3.9.0>.
The local pub-cache archive-hash record is
`b1ec21d306ddbec59a88ae3682ad81728561f7105db78fea0fdd67f06911a519`;
the archive itself was not rehashed. The following are SHA-256
hashes of the actual cached package-file bytes inspected, relative to that
package (not hashes inferred from documentation):

| Package file | SHA-256 |
|---|---|
| `LICENSE` | `67e5d73a3a0c6e41f33d688a672b1161bf7f16e04da9ae48a7a14f1ba7436a4d` |
| `doc/hook.md` | `ee110e35a7885a1b81bbab2b263a694d491f0d65d277e70a70878ab2c1b9151c` |
| `lib/src/hook/asset_hashes.dart` | `f95b40332e3087c1a0f5c1a75729b511305903ee0e07e5ebfb70b6d4b22b37fc` |
| `lib/src/hook/assets.dart` | `2934c9e63b5cd9205d460ce2a08347c06352e92b91ccc1527eff87326b0cad69` |

## Exact candidate inventory

`OpenSSL` below denotes the observed 4.1.0 version string, not license approval.
Linkage groups resolve to the dependency table in the next section.

| Release filename | SHA-256 | Provider evidence | Linkage group |
|---|---|---|---|
| `libsqlcipher.arm.android.so` | `0999b58c9d7b08a08d840fecebe6a820d8cc9dfb59197ca68ff27e5514c768ba` | OpenSSL | Android |
| `libsqlcipher.arm.linux.so` | `e7beae4c21d22ceb9e15a910567b7c0047b3860a92f1a4885c73b623bbc9cbaa` | OpenSSL | Linux arm |
| `libsqlcipher.arm64.android.so` | `e615e2750c5fa455d5a7e70fe4df86c3a2f5696367ceb021d46a9262120df046` | OpenSSL | Android |
| `libsqlcipher.arm64.ios.dylib` | `3ce5dec3e52c008ec33eadfd45ae441ca6c2ca82643cf6fd191a8f228b7192e1` | CommonCrypto | iOS / simulator |
| `libsqlcipher.arm64.ios_sim.dylib` | `4449e5c5078e768bdf6ba874992a5b14770f83876cc84ebda7fa0b4ca3e8d900` | CommonCrypto | iOS / simulator |
| `libsqlcipher.arm64.linux.so` | `b1c9d3d0b7238dcd582b02cd4dbca1df1ec5b4dd8786925a4dab8740e65ebd59` | OpenSSL | Linux arm64 |
| `libsqlcipher.arm64.macos.dylib` | `aaf15ee60b099fbe9f582e6ef5b998836294be14ccfc0aa0a889534fd381b49c` | CommonCrypto | macOS |
| `libsqlcipher.ia32.android.so` | `4b0627b0be57b08691603f095006691d7751d04571f34335e934dccd80dea625` | OpenSSL | Android |
| `libsqlcipher.ia32.linux.so` | `479738249f4a284bd404b435e7f6f859367ec16186619eadc83e65cd56b9973e` | OpenSSL | Linux ia32 |
| `libsqlcipher.riscv64.linux.so` | `8adcac0d3e6d2ad50499102e44c487d095bcdc10076d697332a7d647594f9a2d` | OpenSSL | Linux riscv64 |
| `libsqlcipher.x64.android.so` | `bae3621c9f0417583e2234ec93eab65e85bf91d6c8131b7db38403a83a59507b` | OpenSSL | Android |
| `libsqlcipher.x64.ios_sim.dylib` | `8fbf45bfdcbbe22a28022da91f9495cc3a84f328ec552540b8f0213bb09ef212` | CommonCrypto | iOS / simulator |
| `libsqlcipher.x64.linux.so` | `e03c3c8aa519ce581bff88d7203bf7ef101f876750acd4e0a7bf2cf055aae0f1` | OpenSSL | Linux x64 |
| `libsqlcipher.x64.macos.dylib` | `83aa3d4af0685fae2f0f30aba7f0c9a424cdc5ae488e5d81377c8e6a441db76a` | CommonCrypto | macOS |
| `sqlcipher.arm64.windows.dll` | `da1d11406e219a7c3ad50df0b0fe931ea9e4533599cf203abf7e7a554f192011` | OpenSSL | Windows arm64 |
| `sqlcipher.ia32.windows.dll` | `8e4345254fcb1e8c4178a7499fad50aaa50326637e77a6aa6ca8656068155bcd` | OpenSSL | Windows ia32 |
| `sqlcipher.x64.windows.dll` | `b35f4c3f69f125e7fd6ac2983af8423915cc03aa17102be9abb801258c865122` | OpenSSL | Windows x64 |

## Platform-runtime boundary

These are direct ELF `DT_NEEDED`, PE import-directory or Mach-O dependent-dylib
entries, not a recursive dependency closure or an enumeration of libraries a
program could load dynamically. The PE delay-import directory was empty for all
three DLLs. ELF entries were inspected with `readelf`; PE RVA/section mapping and
Mach-O load commands were decoded directly from the binary headers, including
ARM64 Windows rather than assuming it matches x64. ARM64 Windows does not have
the `USER32.dll` / `ADVAPI32.dll` imports observed in the other two Windows ABIs.

| Linkage group | Direct dependencies |
|---|---|
| Android | `libm.so`, `liblog.so`, `libdl.so`, `libc.so` |
| Linux arm | `libm.so.6`, `libc.so.6`, `ld-linux-armhf.so.3` |
| iOS / simulator | `/System/Library/Frameworks/Foundation.framework/Foundation`, `/System/Library/Frameworks/Security.framework/Security`, `/usr/lib/libSystem.B.dylib`, `/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation` |
| Linux arm64 | `libm.so.6`, `libc.so.6`, `ld-linux-aarch64.so.1` |
| macOS | `/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation`, `/System/Library/Frameworks/Security.framework/Versions/A/Security`, `/usr/lib/libSystem.B.dylib`, `/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation` |
| Linux ia32 | `libm.so.6`, `libc.so.6`, `ld-linux.so.2` |
| Linux riscv64 | `libm.so.6`, `libc.so.6`, `ld-linux-riscv64-lp64d.so.1` |
| Linux x64 | `libm.so.6`, `libc.so.6`, `ld-linux-x86-64.so.2` |
| Windows arm64 | `CRYPT32.dll`, `WS2_32.dll`, `bcrypt.dll`, `KERNEL32.dll` |
| Windows ia32 | `CRYPT32.dll`, `USER32.dll`, `ADVAPI32.dll`, `WS2_32.dll`, `bcrypt.dll`, `KERNEL32.dll` |
| Windows x64 | `CRYPT32.dll`, `USER32.dll`, `ADVAPI32.dll`, `WS2_32.dll`, `bcrypt.dll`, `KERNEL32.dll` |

The platform providers are distinct from the SQLCipher/OpenSSL code inside the
candidate. The system libraries in the table above are not proposed for bundling;
these records classify their provider/linkage, not app distribution rights.

| Platform runtime | Provider and terms evidence | Distribution scope / status |
|---|---|---|
| Android | Android NDK's [stable native APIs](https://developer.android.com/ndk/guides/stable_apis) document libc, libm and libdl as platform APIs (page SHA-256 `58f5e7da230c40e739b21999c4c51790dc08be2b8f5b582ada3ce0bf465f2fb0`). AOSP Bionic's [`libc/Android.bp`](https://raw.githubusercontent.com/aosp-mirror/platform_bionic/731631f300090436d7f5df80d50b6275c8c60a93/libc/Android.bp) at commit `731631f300090436d7f5df80d50b6275c8c60a93` (SHA-256 `437ec370a9dc1aefdfda60f982954ba904a20ca4d0ee5e79ff124be1eb2687ea`) declares multiple license kinds for libc (Apache-2.0, BSD, ISC, MIT, legacy notice and unencumbered) and references a NOTICE file. | OS-provided; no Android system libraries are bundled by this audit. Exact device runtime and applicable app-distribution terms are not selected; approval pending. |
| Apple | Candidate load paths point to `/System/Library/Frameworks` and `/usr/lib/libSystem.B.dylib`. Apple's archived [system-framework overview](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/OSX_Technology_Overview/SystemFrameworks/SystemFrameworks.html) (SHA-256 `b9be6e8b350cda7a0b142455dd78f7353da1f41412aafad1765bd83417975380`) identifies `/System/Library/Frameworks` as the system framework location. | OS-provided; no Apple framework is bundled. Applicable current Apple platform/developer terms and approval remain unreviewed. |
| Windows | Candidate imports are Windows system DLLs. Microsoft documents that Windows functionality is provided by DLLs ([DLL overview](https://learn.microsoft.com/en-us/troubleshoot/windows-client/setup-upgrade-and-drivers/dynamic-link-library), SHA-256 `45491cca3a35f4095ae9902e2043435b78cd0ad1592172ab5765e922df0dc760`) and publishes a specific [Windows SDK redistributable list](https://learn.microsoft.com/en-us/legal/windows-sdk/redist) (SHA-256 `146ab6547cf7c274b00fbae7c4f67bba14281296bd0f24688841a46104e67a1e`). The listed imports do not appear in that SDK redist list. | OS-provided; the candidate does not bundle those DLLs. Applicable Windows OS terms and approval remain unreviewed. |
| Linux | ELF imports name host `libc.so.6`, `libm.so.6` and the dynamic loader. glibc [`COPYING.LESSERv2`](https://raw.githubusercontent.com/bminor/glibc/04e750e75b73957cf1c791535a3f4319534a52fc/COPYING.LESSERv2) at commit `04e750e75b73957cf1c791535a3f4319534a52fc` is LGPL-2.1 text (SHA-256 `20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95`); it is not a digest or license inventory for a particular host runtime. | Kotoha does not currently build a Linux desktop app. No Linux runtime is approved; identify the supported distribution and review its runtime terms before distribution. |

None of these system libraries is selected as a bundled product dependency. Platform
versions and the OS-specific terms applicable to a Kotoha distribution still require
review and approval; system linkage does not establish a permissive code category or
waive policy. The Linux runtime is specifically not treated as a permissive finding.

## License closure under the policy

Unknown below means **no selected license branch and no approval**, not a
permissive default. Native source identities and complete license/notice bytes
must be tied to the build that produced these exact artifact hashes.

| Component / distribution scope | License expression / selected terms | Classification and full-text evidence | Notices / missing evidence |
|---|---|---|---|
| `sqlite3` 3.9.0 Dart wrapper and hook; prospective bundled product dependency | `MIT` / `MIT` | Permissive: inspected the complete package `LICENSE` (digest above). It grants use, modification and redistribution, requires preservation of copyright and permission notice, and disclaims warranty. | Preserve the complete MIT text, including Copyright (c) 2020 Simon Binder. This covers the wrapper/hook, not the native closure. Not presently bundled. |
| SQLCipher 4.20.0 native code; prospective bundled product dependency | `BSD-3-Clause` / `BSD-3-Clause` (provisional source selection) | Permissive: full upstream text at <https://raw.githubusercontent.com/sqlcipher/sqlcipher/355d4db92d3404e71faa8088d071a71d767807f4/LICENSE.md>, SHA-256 `2a2826f6acf46fa650730cf42cbb22a642be33a7ef119c9c4f4bf6daf3bef48e`. It contains source/binary notice requirements, a no-endorsement condition, and warranty/liability disclaimers. Candidate version string matches `4.20.0`, but source-to-binary provenance is not verified. | Bundle the complete text, including Copyright (c) 2025, ZETETIC LLC. This provisional source classification is not approval of the full binary closure; no native notice is delivered yet. |
| SQLite code inside SQLCipher; prospective bundled product dependency | SQLite public-domain dedication / `public-domain` (provisional) | Public-domain: upstream SQLCipher v4.20.0 `SQLITE_LICENSE.md` at commit `355d4db92d3404e71faa8088d071a71d767807f4`, SHA-256 `595e823c2ada6c839679e693bee1f4d7f88e2d34ac99a913ae41e3d43fb10c7d`, states that SQLite source and `sqlite3.c`/`sqlite3.h` products are public domain. Official <https://sqlite.org/copyright.html> text, SHA-256 `44ca9f793055c8e32fc65f65a4f5bcf813a33f5bdaaa084067dd617a4ed3cc70`, agrees. SQLCipher release notes identify SQLite 3.54.1, and the candidate contains `s3.54.1`; exact incorporated source revision and extensions are not verified. | Retain the public-domain dedication as a user-accessible notice if included; inspect extensions separately and tie the code to the release source before approval. |
| OpenSSL code included in Android, Linux and Windows candidates; prospective bundled product dependency | `Apache-2.0` / `Apache-2.0` (provisional source selection) | Permissive: full upstream `openssl-4.1.0/LICENSE.txt` text at <https://raw.githubusercontent.com/openssl/openssl/2f4e3a5fec05394068cfa7379890ab552483a8a6/LICENSE.txt>, SHA-256 `7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a`. Candidate binaries contain the `OpenSSL 4.1.0` version string and OpenSSL implementation symbols; source-to-binary provenance and the complete embedded component set remain unverified. | Bundle the complete Apache license and determine whether the build has applicable NOTICE or third-party texts. This provisional classification is not approval of the complete binary closure. |
| Apple CommonCrypto and all direct OS dependencies above; platform-provided runtime candidates | Unknown / none selected | Provider/linkage recorded above; applicable terms, redistribution evidence and approval pending for each target runtime. | Review the supported platform's SDK/runtime terms and notice obligations; do not copy OS libraries into the application as a substitute. |

The versioned upstream evidence provisionally classifies the Dart wrapper as MIT,
SQLCipher as BSD-3-Clause, OpenSSL as Apache-2.0, and SQLite as public domain. These
source-level selections do not approve a bundled candidate: source/build provenance,
the complete embedded component set, platform-runtime terms and native notice delivery
remain unresolved. No paid, unknown or GPL-family term is approved for distribution.

## Completion gate

Obtain trusted verification of the exact asset attestations and a schema-valid
CycloneDX inventory; the currently retrieved BOM is malformed and its signature is
unverified. Bind the generated SQLCipher ZIP and OpenSSL source tarball, versions,
build configuration and every embedded component to the artifact hashes with
verified source/build evidence. The OpenSSL release API reports a tarball digest,
but the build does not check it; no published digest for the generated SQLCipher
ZIP was found. Inspect and retain complete license/NOTICE texts, complete the
policy's expression, selected-term, classification, source, digest, notice and
distribution-scope evidence, and review each supported platform runtime. Bundle
every required native text in a user-accessible route; Flutter's collected Dart
package licenses alone do not cover this native set.

The inspected inputs contain binaries and the Dart package, not the native source
closure; approval is blocked until that evidence is supplied. Target encryption,
key-management, backup exclusion and save/reopen tests remain separate gates even
after license approval. Persistence stays disabled.
