import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/language_roles.dart';

void main() {
  group('LanguageTag.parse', () {
    test('accepts language, script and region and canonicalizes case', () {
      final tag = LanguageTag.parse('ja-Jpan-JP');
      expect(tag, isNotNull);
      expect(tag!.language, 'ja');
      expect(tag.script, 'Jpan');
      expect(tag.region, 'JP');
      expect(tag.canonical, 'ja-Jpan-JP');
      expect(tag.toString(), 'ja-Jpan-JP');
    });

    test('canonical identity ignores input case', () {
      final lower = LanguageTag.parse('en-latn-us');
      final upper = LanguageTag.parse('EN-Latn-US');
      expect(lower, isNotNull);
      expect(upper, isNotNull);
      expect(lower, upper);
      expect(lower.hashCode, upper.hashCode);
    });

    test('accepts a plain primary language with no script or region', () {
      final tag = LanguageTag.parse('fr');
      expect(tag, isNotNull);
      expect(tag!.script, isNull);
      expect(tag.region, isNull);
      expect(tag.subtags, ['fr']);
      expect(tag.canonical, 'fr');
    });

    test('preserves BCP-47 extensions and variants (design §2.1)', () {
      final calendar = LanguageTag.parse('ja-JP-u-ca-japanese');
      expect(calendar, isNotNull);
      expect(calendar!.language, 'ja');
      expect(calendar.region, 'JP');
      expect(calendar.canonical, 'ja-JP-u-ca-japanese');
      expect(calendar.subtags, ['ja', 'JP', 'u', 'ca', 'japanese']);

      final numerals = LanguageTag.parse('sr-Latn-RS-u-nu-latn');
      expect(numerals, isNotNull);
      expect(numerals!.script, 'Latn');
      expect(numerals.region, 'RS');
      expect(numerals.canonical, 'sr-Latn-RS-u-nu-latn');
      expect(numerals.subtags, ['sr', 'Latn', 'RS', 'u', 'nu', 'latn']);

      final variant = LanguageTag.parse('de-DE-1996');
      expect(variant, isNotNull);
      expect(variant!.canonical, 'de-DE-1996');
      expect(variant.subtags, ['de', 'DE', '1996']);

      final private = LanguageTag.parse('en-US-x-private');
      expect(private, isNotNull);
      expect(private!.canonical, 'en-US-x-private');
      expect(private.subtags, ['en', 'US', 'x', 'private']);
    });

    test(
      'accepts private-use and longer primary subtags from the spec pattern',
      () {
        final private = LanguageTag.parse('x-private');
        expect(private, isNotNull);
        expect(private!.language, 'x');
        expect(private.subtags, ['x', 'private']);

        final longPrimary = LanguageTag.parse('qaa-Qaaa-QM-x-southern');
        expect(longPrimary, isNotNull);
        expect(longPrimary!.canonical, 'qaa-Qaaa-QM-x-southern');
      },
    );

    test('rejects malformed entries fail-closed', () {
      for (final bad in <String>[
        '',
        '   ',
        'e', // primary shorter than two letters
        '123', // primary is not alphabetic
        'en-', // empty subtag
        'en--US', // empty subtag
        'en-!!!', // non-alphanumeric subtag
        'en-US-abcdefghi', // subtag longer than eight characters
        'x', // private-use primary needs at least one subtag
      ]) {
        expect(LanguageTag.parse(bad), isNull, reason: bad);
      }
    });
  });

  group('LanguageProfile', () {
    test('roles are independent and unbound roles stay null', () {
      final ja = LanguageTag.parse('ja')!;
      final en = LanguageTag.parse('en')!;
      final profile = const LanguageProfile()
          .withTag(LanguageRole.uiDisplay, ja)
          .withTag(LanguageRole.input, en);
      expect(profile.tag(LanguageRole.uiDisplay), ja);
      expect(profile.tag(LanguageRole.input), en);
      expect(profile.tag(LanguageRole.voice), isNull);
      expect(
        profile.boundRoles,
        unorderedEquals(<LanguageRole>[
          LanguageRole.uiDisplay,
          LanguageRole.input,
        ]),
      );
    });

    test(
      'a correction overwrites only that role and leaves the original intact',
      () {
        final ja = LanguageTag.parse('ja')!;
        final en = LanguageTag.parse('en')!;
        final original = const LanguageProfile().withTag(
          LanguageRole.input,
          ja,
        );
        final corrected = original.withTag(LanguageRole.input, en);
        expect(original.tag(LanguageRole.input), ja);
        expect(corrected.tag(LanguageRole.input), en);
      },
    );

    test('clearing a role removes only that binding', () {
      final ja = LanguageTag.parse('ja')!;
      final en = LanguageTag.parse('en')!;
      final profile = const LanguageProfile()
          .withTag(LanguageRole.uiDisplay, ja)
          .withTag(LanguageRole.voice, en);
      final cleared = profile.withTag(LanguageRole.voice, null);
      expect(cleared.tag(LanguageRole.uiDisplay), ja);
      expect(cleared.tag(LanguageRole.voice), isNull);
    });

    test(
      'from() defensively copies so a caller map cannot mutate a profile',
      () {
        final ja = LanguageTag.parse('ja')!;
        final en = LanguageTag.parse('en')!;
        final backing = <LanguageRole, LanguageTag>{LanguageRole.uiDisplay: ja};
        final profile = LanguageProfile.from(backing);
        expect(profile.tag(LanguageRole.uiDisplay), ja);

        backing[LanguageRole.uiDisplay] = en;
        backing[LanguageRole.input] = en;
        expect(profile.tag(LanguageRole.uiDisplay), ja);
        expect(profile.tag(LanguageRole.input), isNull);
      },
    );
  });

  group('LanguageEstimate', () {
    final ja = LanguageTag.parse('ja')!;
    final en = LanguageTag.parse('en')!;

    test('undetermined until confirmed and unambiguous', () {
      final unconfirmed = LanguageEstimate(<LanguageTag>[ja], evidenceRef: 'd');
      expect(unconfirmed.isDetermined, isFalse);
      expect(unconfirmed.resolved, isNull);

      final ambiguous = LanguageEstimate(<LanguageTag>[
        ja,
        en,
      ], confirmed: true);
      expect(ambiguous.isDetermined, isFalse);
      expect(ambiguous.resolved, isNull);

      final determined = LanguageEstimate(<LanguageTag>[ja], confirmed: true);
      expect(determined.isDetermined, isTrue);
      expect(determined.resolved, ja);
    });

    test('empty candidates never resolve', () {
      const empty = LanguageEstimate(<LanguageTag>[], confirmed: true);
      expect(empty.isDetermined, isFalse);
      expect(empty.resolved, isNull);
    });
  });
}
