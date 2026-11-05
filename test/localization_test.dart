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
    final copy = find.byTooltip('Copy translation');
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
