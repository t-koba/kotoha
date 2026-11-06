# Unicode bidi data and license audit

Kotoha uses Unicode 17.0.0 `DerivedBidiClass.txt` for UAX #9 P2/P3
first-strong paragraph direction, matching the Unicode data version observed in
the local Linux engine artifact from the Flutter 3.47.9 stable toolchain also
pinned in CI. The engine revision is
`89c39edfdfae2949f6806e4a315c0c08522238b7` (content hash
`9e025265bef30b838c0c1b68cad19decf97048f2`). Its `icudtl.dat` has SHA-256
`325a86063d26334c2eabe1743cea073b612540fbf3d8fc2ef0b5708e3763a8c7`; its
`icuver.res` reports ICU 78.2.0.0, and the `uemoji.icu` and `ulayout.icu` data
headers report Unicode 17.0.0.0. CI pins Flutter 3.47.9 across its platform
jobs, but target-specific engine artifacts were not separately inspected. These
headers establish the bundled ICU data version, not a separately extracted
digest of its internal Bidi_Class property table; matching UCD 17 avoids
choosing a newer classifier than the pinned renderer's data.

A bounded comparison of the exact Unicode 17 source with the prior Unicode 18
projection found 112 changed scalars: 17 R/AL-to-other, 92 L-to-other, and
3 other-to-L transitions. This showed a real version-dependent first-strong
classification difference, so the generated projection now tracks the pinned
engine data version (comparison evidence `ef6706f5971547509de9e65db89f1276`).

## Dependency-policy evidence

The fields below implement [dependency_policy.json](specs/dependency_policy.json)
for this data and its generated Dart representation only.

| Field | Evidence |
| --- | --- |
| `license_expression` | `Unicode-3.0` (Unicode License V3; exact notice bundled below) |
| `selected_terms` | Unicode License V3, with no alternative branch or additional AND terms |
| `term_classifications` | `permissive`: the full notice grants use, copying, modification, merging, publication, distribution and sale without restriction, subject to notice delivery; includes warranty/liability disclaimers and restriction on promotional use of copyright-holder names |
| `source` | Unicode 17.0.0, <https://unicode.org/Public/17.0.0/ucd/extracted/DerivedBidiClass.txt> |
| `content_digest` | Source SHA-256 `4867b4b7f0731ed1bfcd34cc6251211ff1542541fce0734b6fbda139ee80b3a4`; normalized projected data SHA-256 `77c6391f0a107c5ec774c4b62e9a4bfb80f3bbf284244f62d01a2b08c8044a8c` |
| `notices` | Source copyright © 2025 Unicode, Inc.; full current Unicode License V3 notice in [`assets/licenses/Unicode-3.0.txt`](../assets/licenses/Unicode-3.0.txt), bundled and exposed as **Unicode Bidi Data** via the existing app license action |
| `distribution_scope` | All Kotoha platforms shipping the generated Dart data; required notice accompanies both the source tree and app assets; no native linkage, platform service or external runtime acquisition |

License source: <https://unicode.org/license.txt>, exact source receipt
`30c8613584b2a80b16f93bfce4c0a85a393a1ba590928db630bb304d589e2d68`.
The byte-exact bundled UTF-8 notice has SHA-256
`e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96`, matching
the upstream receipt. The classification is based on the full Unicode License
V3 text, not on the SPDX identifier alone.

## Reproduction and direction scope

From the repository root, with the exact local source file:

```sh
python3 tools/generate_unicode_bidi.py /path/to/DerivedBidiClass-17.0.0.txt
# To regenerate instead of checking byte-for-byte:
python3 tools/generate_unicode_bidi.py /path/to/DerivedBidiClass-17.0.0.txt --write
```

The offline tool verifies the source hash before writing anything, applies all
commented `@missing` rules in order before explicit records, projects classes
(default L; R/AL=1, B=2, LRI/RLI/FSI=3, PDI=4, other=5), coalesces non-L runs,
and verifies the normalized digest. Digest serialization is one interval per
line: six-digit uppercase hexadecimal start and end, then decimal class,
separated by single spaces, with final LF. The exact UCD 17 source receipt
`9b6aa632cb15ca22ff90ddd8230a1ad3e61b1c1d3065f2f84ea1f41348f16255` was checked
by the read-only repository generator (`2c30af24dea044d4a34eb67aed475894`),
which verified the source hash and byte-for-byte Dart output. The raw UCD file
is not included in the app or repository; regeneration requires a local copy of
the pinned source and the documented hash check. The normalized projection is
10,112 bytes across 632 intervals; the generated Dart source is 16,439 bytes.
Compiled release-artifact size delta was not measured.

The scanner iterates Unicode scalar values, skips nested and unmatched isolate
contents, stops at the first paragraph separator (even inside an isolate), and
uses the first L, R or AL outside isolates, defaulting to LTR. A TextField has
one base direction, so later paragraphs share the first paragraph's direction;
this is not per-paragraph automatic direction. Flutter remains responsible for
bidi layout. Text, UTF-16 editing offsets, selection, focus and clipboard content
are not rewritten. Text remains manual and memory-only, without inference.
