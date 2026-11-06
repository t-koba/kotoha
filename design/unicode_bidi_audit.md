# Unicode bidi data and license audit

Kotoha uses Unicode 18.0.0 `DerivedBidiClass.txt` for UAX #9 P2/P3
first-strong paragraph direction. The projection in
`lib/unicode_bidi_data.dart` contains 634 coalesced non-L intervals. It is
bundled data, not a new dependency or a runtime/build download.

## Dependency-policy evidence

The fields below implement [dependency_policy.json](specs/dependency_policy.json)
for this data and its generated Dart representation only.

| Field | Evidence |
| --- | --- |
| `license_expression` | `Unicode-3.0` (Unicode License V3; exact notice bundled below) |
| `selected_terms` | Unicode License V3, with no alternative branch or additional AND terms |
| `term_classifications` | `permissive`: the full notice grants use, copying, modification, merging, publication, distribution and sale without restriction, subject to notice delivery; includes warranty/liability disclaimers and restriction on promotional use of copyright-holder names |
| `source` | Unicode 18.0.0, <https://unicode.org/Public/18.0.0/ucd/extracted/DerivedBidiClass.txt> |
| `content_digest` | Source SHA-256 `d9e23222522551348ea1ccfbb4f62efbf98982afb95840f8959c08ed992c5607`; normalized projected data SHA-256 `69712a92c89809280008948c79da6da675a980a490eee024a379aeb6f5fb5034` |
| `notices` | Copyright © 1991-2026 Unicode, Inc.; full permission, disclaimer and name-use notice in [`assets/licenses/Unicode-3.0.txt`](../assets/licenses/Unicode-3.0.txt), bundled and exposed as **Unicode Bidi Data** via the existing app license action |
| `distribution_scope` | All Kotoha platforms shipping the generated Dart data; required notice accompanies both the source tree and app assets; no native linkage, platform service or external runtime acquisition |

License source: <https://unicode.org/license.txt>, exact source receipt
`30c8613584b2a80b16f93bfce4c0a85a393a1ba590928db630bb304d589e2d68`.
The byte-exact bundled UTF-8 notice has SHA-256 `e7a93b009565cfce55919a381437ac4db883e9da2126fa28b91d12732bc53d96`, matching the
upstream receipt. The classification above is based on the full Unicode License
V3 text, not on the SPDX identifier alone.

## Reproduction and direction scope

From the repository root, with the exact local source file:

```sh
python3 tools/generate_unicode_bidi.py /path/to/DerivedBidiClass-18.0.0.txt
# To regenerate instead of checking byte-for-byte:
python3 tools/generate_unicode_bidi.py /path/to/DerivedBidiClass-18.0.0.txt --write
```

The offline tool verifies the source hash before writing anything, applies all
commented `@missing` rules in order before explicit records, projects classes
(default L; R/AL=1, B=2, LRI/RLI/FSI=3, PDI=4, other=5), coalesces non-L runs,
and verifies the normalized digest. Digest serialization is one interval per
line: six-digit uppercase hexadecimal start and end, then decimal class,
separated by single spaces, with final LF. The exact UCD source receipt
`1a3eafc29d316b84b41ce4e0e3d8b87ead6243c2c9905225ed896cbc45e65f18` was checked
by a read-only generator run (`b2528998dfa948b2b693fa9c47c1f801`), which
verified both the source hash and byte-for-byte generated Dart output. The raw UCD file is not included in the app or repository; regeneration requires
a local copy of the pinned source and the documented hash check. The normalized
projection is 10,144 bytes across 634 intervals; the generated Dart source is
16,489 bytes. Compiled release-artifact size delta was not measured.

The scanner iterates Unicode scalar values, skips nested/unmatched isolate
contents, stops at the first paragraph separator (even inside an isolate), and
uses the first L, R or AL outside isolates, defaulting to LTR. This sets one base
direction for the entire TextField: subsequent paragraphs share that direction.
It is not per-paragraph automatic direction; Flutter still performs bidi layout.
The Flutter engine's Unicode-data version was not verified in this change, so a
version difference for newly assigned characters is possible. Text, UTF-16
editing offsets, selection, focus and clipboard content are not rewritten. Text
remains manual and memory-only, without translation inference.

The scanner iterates Unicode scalar values, skips nested/unmatched isolate
contents, stops at the first paragraph separator (even inside an isolate), and
uses the first L, R or AL outside isolates, defaulting to LTR. This sets one base
direction for the entire TextField: subsequent paragraphs share that direction.
It is not per-paragraph automatic direction; Flutter still performs bidi layout.
Text, UTF-16 editing offsets, selection, focus and clipboard content are not
rewritten. Text remains manual and memory-only, without translation inference.
