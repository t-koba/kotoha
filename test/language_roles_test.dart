import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/content_locale.dart' show parseContentLocale;
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
      expect(tag.canonical, 'fr');
    });

    test('rejects malformed entries fail-closed', () {
      for (final bad in <String>[
        '',
        '   ',
        'english',
        'e',
        '123',
        'en-US-Latn', // script after region is malformed
        'en-QQQ', // three-letter region
        'en-Latn-US-extra', // too many subtags
      ]) {
        expect(LanguageTag.parse(bad), isNull, reason: bad);
      }
    });

    test('acceptance matches the reused fail-closed validator', () {
      for (final entry in <String>['ja', 'zh-Hans-CN', 'pt-BR', 'de']) {
        expect(parseContentLocale(entry), isNotNull, reason: entry);
        expect(LanguageTag.parse(entry), isNotNull, reason: entry);
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
