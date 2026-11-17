import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show LocaleStringAttribute, TextRange;
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/content_locale.dart';
import 'package:kotoha/main.dart';

LocaleStringAttribute _onlyLocale(SemanticsNode node) {
  final attributes = node.attributedValue.attributes
      .whereType<LocaleStringAttribute>()
      .toList();
  expect(attributes, hasLength(1));
  return attributes.single;
}

void main() {
  testWidgets('free-form language entries normalize conservatively', (
    tester,
  ) async {
    expect(parseContentLocale('ja')?.toLanguageTag(), 'ja');
    expect(parseContentLocale('en-US')?.toLanguageTag(), 'en-US');
    expect(parseContentLocale('zh-Hant-TW')?.toLanguageTag(), 'zh-Hant-TW');
    expect(parseContentLocale('  fr  ')?.toLanguageTag(), 'fr');
    // Arbitrary names and malformed tags must never be guessed into a locale.
    expect(parseContentLocale('Japanese'), isNull);
    expect(parseContentLocale('日本語'), isNull);
    expect(parseContentLocale('en US'), isNull);
    expect(parseContentLocale('a'), isNull);
    expect(parseContentLocale('en-US-x-private'), isNull);
    expect(parseContentLocale(''), isNull);
  });

  testWidgets(
    'content fields carry their language tag without changing the value',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const KotohaApp());
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        const sourceText = 'こんにちは';
        const translation = 'Hello there';
        await tester.enterText(
          find.byKey(const ValueKey('source-language')),
          'ja',
        );
        await tester.enterText(
          find.byKey(const ValueKey('source-text')),
          sourceText,
        );
        await tester.enterText(
          find.byKey(const ValueKey('target-language-0')),
          'en-US',
        );
        await tester.enterText(
          find.byKey(const ValueKey('translation-text-0')),
          translation,
        );
        await tester.pump();

        final sourceNode = tester.getSemantics(
          find.bySemanticsIdentifier('source-text'),
        );
        expect(sourceNode.value, sourceText);
        expect(_onlyLocale(sourceNode).locale.toLanguageTag(), 'ja');
        expect(
          _onlyLocale(sourceNode).range,
          TextRange(start: 0, end: sourceText.length),
        );

        final translationNode = tester.getSemantics(
          find.bySemanticsIdentifier('translation-text-0'),
        );
        expect(translationNode.value, translation);
        expect(_onlyLocale(translationNode).locale.toLanguageTag(), 'en-US');

        // Labels, identifiers and traversal handles remain intact.
        expect(find.bySemanticsIdentifier('source-text'), findsOneWidget);
        expect(find.bySemanticsLabel('Manual translation'), findsWidgets);
        expect(find.bySemanticsIdentifier('source-language'), findsOneWidget);

        // A free-form language value leaves the field unannotated.
        await tester.enterText(
          find.byKey(const ValueKey('source-language')),
          'Japanese',
        );
        await tester.pump();
        final updated = tester.getSemantics(
          find.bySemanticsIdentifier('source-text'),
        );
        expect(updated.value, sourceText);
        expect(
          updated.attributedValue.attributes.whereType<LocaleStringAttribute>(),
          isEmpty,
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
