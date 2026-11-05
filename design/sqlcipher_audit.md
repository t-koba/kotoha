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
reports SLSA level 3 attestations for released binaries and CycloneDX SBOMs retrievable
through GitHub attestations. This audit has not retrieved or verified either artifact;
the exact build provenance and native component inventory are still open.

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

For Android, the candidate platform provider is Android/Bionic; for Apple it is
Apple's system runtime/frameworks (including CommonCrypto); for Windows it is
the Microsoft Windows system DLL set. Linux's `libc.so.6`, `libm.so.6` and loaders
are host runtime dependencies, **not** a permissive-license finding: identify the
actual distribution and applicable runtime terms before approval. Kotoha does
not currently build a Linux desktop app. None of the listed OS libraries is
proposed for bundling by this audit. For every platform, applicable terms and
redistribution evidence remain uncollected and approval is pending. A system
linkage classification does not approve any GPL-family selected term or waive
policy. OpenSSL code included inside a candidate is not platform-runtime code.

## License closure under the policy

Unknown below means **no selected license branch and no approval**, not a
permissive default. Native source identities and complete license/notice bytes
must be tied to the build that produced these exact artifact hashes.

| Component / distribution scope | License expression / selected terms | Classification and full-text evidence | Notices / missing evidence |
|---|---|---|---|
| `sqlite3` 3.9.0 Dart wrapper and hook; prospective bundled product dependency | `MIT` / `MIT` | Permissive: inspected the complete package `LICENSE` (digest above). It grants use, modification and redistribution, requires preservation of copyright and permission notice, and disclaims warranty. | Preserve the complete MIT text, including Copyright (c) 2020 Simon Binder. This covers the wrapper/hook, not the native closure. Not presently bundled. |
| SQLCipher 4.20.0 native code; prospective bundled product dependency | `BSD-3-Clause` / `BSD-3-Clause` (provisional source selection) | Permissive: full upstream tag text at <https://raw.githubusercontent.com/sqlcipher/sqlcipher/v4.20.0/LICENSE.md>, SHA-256 `2a2826f6acf46fa650730cf42cbb22a642be33a7ef119c9c4f4bf6daf3bef48e`. It contains source/binary notice requirements, a no-endorsement condition, and warranty/liability disclaimers. Candidate version string matches `4.20.0`, but source-to-binary provenance is not verified. | Bundle the complete text, including Copyright (c) 2025, ZETETIC LLC. This provisional source classification is not approval of the full binary closure; no native notice is delivered yet. |
| SQLite code inside SQLCipher; prospective bundled product dependency | SQLite public-domain dedication / `public-domain` (provisional) | Public-domain: official <https://sqlite.org/copyright.html> text, SHA-256 `44ca9f793055c8e32fc65f65a4f5bcf813a33f5bdaaa084067dd617a4ed3cc70`. [SQLCipher 4.20.0 release notes](https://www.zetetic.net/blog/2026/10/27/sqlcipher-4.20.0-release/) identify SQLite 3.54.1, and the candidate contains `s3.54.1`; the exact incorporated source revision and extensions are not verified. | Retain the public-domain dedication as a user-accessible notice if included; inspect extensions separately and tie the code to the release source before approval. |
| OpenSSL code included in Android, Linux and Windows candidates; prospective bundled product dependency | `Apache-2.0` / `Apache-2.0` (provisional source selection) | Permissive: full upstream `openssl-4.1.0/LICENSE.txt` text at <https://raw.githubusercontent.com/openssl/openssl/openssl-4.1.0/LICENSE.txt>, SHA-256 `7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a`. Candidate binaries contain the `OpenSSL 4.1.0` version string and OpenSSL implementation symbols; source-to-binary provenance and the complete embedded component set remain unverified. | Bundle the complete Apache license and determine whether the build has applicable NOTICE or third-party texts. This provisional classification is not approval of the complete binary closure. |
| Apple CommonCrypto and all direct OS dependencies above; platform-provided runtime candidates | Unknown / none selected | Provider/linkage recorded above; applicable terms, redistribution evidence and approval pending for each target runtime. | Review the supported platform's SDK/runtime terms and notice obligations; do not copy OS libraries into the application as a substitute. |

The versioned upstream evidence provisionally classifies the Dart wrapper as MIT,
SQLCipher as BSD-3-Clause, OpenSSL as Apache-2.0, and SQLite as public domain. These
source-level selections do not approve a bundled candidate: source/build provenance,
the complete embedded component set, platform-runtime terms and native notice delivery
remain unresolved. No paid, unknown or GPL-family term is approved for distribution.

## Completion gate

Retrieve and verify the package's advertised SLSA provenance and CycloneDX SBOM
for each exact asset, then bind their SQLCipher/SQLite revisions, OpenSSL 4.1.0
configuration and every embedded component to the asset hashes. Inspect and retain
the complete license/NOTICE texts; complete the policy's expression, selected-term,
classification, source, digest, notice and distribution-scope evidence. Review each
supported platform runtime. Bundle every required native text in a user-accessible
notice route; Flutter's collected Dart package licenses alone do not cover this set.

The inspected inputs contain binaries and the Dart package, not the native source
closure; approval is blocked until that evidence is supplied. Target encryption,
key-management, backup exclusion and save/reopen tests remain separate gates even
after license approval. Persistence stays disabled.
