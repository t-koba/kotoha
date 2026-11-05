import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
  for (final (locales, title, source, notice, language, licenses) in [
    (
      [const Locale('ja', 'JP')],
      'テキスト作業',
      '原文',
      'この下書きは一時的なものです。このアプリには保存されません。',
      '表示言語',
      'ライセンス',
    ),
    (
      [const Locale('fr', 'FR'), const Locale('en', 'GB')],
      'Text workspace',
      'Source text',
      'This draft is temporary. It is not saved in this app.',
      'Interface language',
      'Licenses',
    ),
    (
      [const Locale('fr', 'FR')],
      'テキスト作業',
      '原文',
      'この下書きは一時的なものです。このアプリには保存されません。',
      '表示言語',
      'ライセンス',
    ),
  ]) {
    testWidgets('resolves device locales $locales', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = locales;
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const KotohaApp());
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(find.text(source), findsOneWidget);
      expect(find.text(notice), findsOneWidget);
      expect(find.byTooltip(language), findsOneWidget);
      expect(find.byTooltip(licenses), findsOneWidget);
    });
  }

  testWidgets(
    'localized editor exposes field labels and actions to assistive technology',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(1000, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

        for (final (
              locale,
              fieldLabels,
              notice,
              tooltips,
              copyLabels,
              removeLabels,
              addLabel,
            )
            in [
              (
                const Locale('ja'),
                ['原文の言語', '原文', '訳先の言語', '手入力した訳文'],
                'この下書きは一時的なものです。このアプリには保存されません。',
                ['表示言語', 'ライセンス'],
                ['1件目の訳文をコピー', '2件目の訳文をコピー'],
                ['1件目の訳先を削除', '2件目の訳先を削除'],
                '訳先を追加',
              ),
              (
                const Locale('en'),
                [
                  'Source language',
                  'Source text',
                  'Target language',
                  'Manual translation',
                ],
                'This draft is temporary. It is not saved in this app.',
                ['Interface language', 'Licenses'],
                ['Copy translation 1', 'Copy translation 2'],
                ['Remove translation 1', 'Remove translation 2'],
                'Add translation',
              ),
            ]) {
          tester.binding.platformDispatcher.localesTestValue = [locale];
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(const KotohaApp());
          await tester.pumpAndSettle();

          for (final label in fieldLabels) {
            expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
          }
          expect(find.bySemanticsLabel(notice), findsOneWidget);
          expect(find.bySemanticsLabel(addLabel), findsOneWidget);
          for (final tooltip in tooltips) {
            final control = find.byTooltip(tooltip);
            expect(control, findsOneWidget, reason: tooltip);
            expect(
              tester.getSemantics(control).getSemanticsData().tooltip,
              tooltip,
            );
          }
          final firstCopy = find.byTooltip(copyLabels.first);
          expect(firstCopy, findsOneWidget);
          expect(
            tester.getSemantics(firstCopy).getSemanticsData().tooltip,
            copyLabels.first,
          );

          await tester.tap(find.text(addLabel));
          await tester.pumpAndSettle();
          for (final label in [...copyLabels, ...removeLabels]) {
            final control = find.byTooltip(label);
            expect(control, findsOneWidget, reason: label);
            expect(
              tester.getSemantics(control).getSemanticsData().tooltip,
              label,
            );
          }
          await tester.tap(find.byTooltip(removeLabels.first));
          await tester.pumpAndSettle();
          expect(find.byTooltip(copyLabels.first), findsOneWidget);
          expect(find.byTooltip(copyLabels.last), findsNothing);
          expect(find.byTooltip(removeLabels.first), findsNothing);
          expect(find.byTooltip(removeLabels.last), findsNothing);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('session language switches preserve all manual fields', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ja')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('訳先を追加'));
    await tester.pumpAndSettle();
    const values = ['ja-JP', '原文 👋', 'en-GB', 'Hello\nこんにちは', 'fr', 'Bonjour'];
    final controllers = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((field) => field.controller!)
        .toList();
    expect(controllers, hasLength(values.length));
    for (var index = 0; index < values.length; index++) {
      await tester.enterText(find.byType(TextField).at(index), values[index]);
    }

    for (final (choice, title) in [
      ('English', 'Text workspace'),
      ('日本語', 'テキスト作業'),
    ]) {
      await tester.tap(find.byKey(const ValueKey('ui-language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(choice));
      await tester.pumpAndSettle();

      expect(find.text(title), findsOneWidget);
      expect(
        tester
            .widgetList<TextField>(find.byType(TextField))
            .map((field) => field.controller),
        orderedEquals(controllers),
      );
      expect(
        controllers.map((controller) => controller.text),
        orderedEquals(values),
      );
    }

    // A fresh app session follows the device again and starts with empty fields.
    await tester.tap(find.byKey(const ValueKey('ui-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();
    expect(find.text('テキスト作業'), findsOneWidget);
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .map((field) => field.controller!.text),
      everyElement(isEmpty),
    );
  });

  testWidgets('keeps both locales usable at a narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );

    for (final textScale in [1.0, 2.0]) {
      tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;
      for (final (locale, copyTooltip, switchTo, title) in [
        (const Locale('ja'), '1件目の訳文をコピー', 'English', 'Kotoha'),
        (const Locale('en'), 'Copy translation 1', '日本語', 'ことは | Kotoha'),
      ]) {
        await tester.pumpWidget(const SizedBox());
        tester.binding.platformDispatcher.localesTestValue = [locale];
        await tester.pumpWidget(const KotohaApp());
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('ui-language')), findsOneWidget);
        expect(find.byKey(const ValueKey('show-licenses')), findsOneWidget);
        final scrollable = find.byType(Scrollable).first;
        await tester.dragUntilVisible(
          find.byKey(const ValueKey('source-text')),
          scrollable,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('source-text')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.dragUntilVisible(
          find.byKey(const ValueKey('translation-text-0')),
          scrollable,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byTooltip(copyTooltip), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('ui-language')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(switchTo));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byKey(const ValueKey('show-licenses')));
        await tester.pumpAndSettle();
        expect(find.byType(LicensePage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets('English copy notice and SDK license page remain accessible', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No automatic translation is performed.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Copied translations are sent to the OS clipboard'),
      findsOneWidget,
    );
    final copy = find.byTooltip('Copy translation 1');
    await tester.dragUntilVisible(
      copy,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pump();
    expect(find.text('Enter a translation to copy.'), findsOneWidget);
    await tester.tap(find.byTooltip('Licenses'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
