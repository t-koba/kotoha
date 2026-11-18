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

// Count nodes in the *live* semantics tree (rootSemanticsNode), not the stale
// debugSemantics nodes that widgets retain after ExcludeSemantics drops them.
int _liveNodesWithLocale(String tag) => find.semantics
    .byPredicate(
      (node) => node.attributedValue.attributes
          .whereType<LocaleStringAttribute>()
          .any((a) => a.locale.toLanguageTag() == tag),
    )
    .evaluate()
    .length;

int _liveNodesWithValue(String value) =>
    find.semantics.byPredicate((node) => node.value == value).evaluate().length;

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
    // Reject non-ASCII letters even if lowercasing would turn them into ASCII.
    expect(parseContentLocale('\u212Ao'), isNull);
    expect(parseContentLocale('\u0130a'), isNull);
    // Mis-ordered subtags: BCP-47 requires script before region. These must
    // not be reordered by Locale.fromSubtags into valid-looking locales.
    expect(parseContentLocale('en-US-Hant'), isNull);
    expect(parseContentLocale('zh-CN-Hant'), isNull);
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

  testWidgets(
    'paused shield hides the locale hint and resume restores the exact tag',
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

        // Live tree while active: exact voice hints and byte-identical values.
        expect(_liveNodesWithLocale('ja'), 1);
        expect(_liveNodesWithLocale('en-US'), 1);
        expect(
          tester.getSemantics(find.bySemanticsIdentifier('source-text')).value,
          sourceText,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsIdentifier('translation-text-0'))
              .value,
          translation,
        );

        // The shield excludes semantics across the full inactive sequence.
        for (final state in const <AppLifecycleState>[
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
          expect(
            tester
                .widget<ExcludeSemantics>(
                  find.byKey(const ValueKey('workspace-semantics-shield')),
                )
                .excluding,
            isTrue,
          );
          // Neither the draft text nor its voice hint reaches the live tree.
          expect(_liveNodesWithValue(sourceText), 0);
          expect(_liveNodesWithValue(translation), 0);
          expect(_liveNodesWithLocale('ja'), 0);
          expect(_liveNodesWithLocale('en-US'), 0);
        }

        // Resume restores the exact tags and byte-identical values.
        for (final state in const <AppLifecycleState>[
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
          await tester.pump();
        }
        expect(_liveNodesWithLocale('ja'), 1);
        expect(_liveNodesWithLocale('en-US'), 1);
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
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('IME composing text and locale hint are shielded and restored', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();
    try {
      const language = 'en-US';
      // 'draft かな' is eight UTF-16 code units (two kana plus six ASCII).
      const draft = 'draft かな';
      const composingRange = TextRange(start: 0, end: 8);
      await tester.enterText(
        find.byKey(const ValueKey('source-language')),
        language,
      );
      await tester.pump();
      final source = find.byKey(const ValueKey('source-text'));
      await tester.tap(source);
      await tester.pump();

      // An active IME composition is an uncommitted draft value.
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: 8),
          composing: composingRange,
        ),
      );
      await tester.pumpAndSettle();

      // While resumed, the composing text and its exact voice hint are exposed.
      expect(_liveNodesWithValue(draft), greaterThanOrEqualTo(1));
      expect(_liveNodesWithLocale(language), 1);
      final active = tester.getSemantics(
        find.bySemanticsIdentifier('source-text'),
      );
      expect(active.value, draft);
      expect(_onlyLocale(active).locale.toLanguageTag(), language);
      expect(_onlyLocale(active).range, composingRange);

      // The shield covers the whole inactive sequence, including a live IME.
      for (final state in const <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(
          tester
              .widget<ExcludeSemantics>(
                find.byKey(const ValueKey('workspace-semantics-shield')),
              )
              .excluding,
          isTrue,
        );
        expect(_liveNodesWithValue(draft), 0);
        expect(_liveNodesWithLocale(language), 0);
      }

      // Resume restores the exact draft, hint and active composing region.
      for (final state in const <AppLifecycleState>[
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      expect(_liveNodesWithLocale(language), 1);
      final restored = tester.getSemantics(
        find.bySemanticsIdentifier('source-text'),
      );
      expect(restored.value, draft);
      expect(_onlyLocale(restored).locale.toLanguageTag(), language);
      expect(_onlyLocale(restored).range, composingRange);
      expect(
        tester.widget<TextField>(source).controller!.value.composing,
        composingRange,
      );
      expect(find.bySemanticsIdentifier('source-text'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
