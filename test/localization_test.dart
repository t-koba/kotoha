import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        debugDefaultTargetPlatformOverride = TargetPlatform.android;

        for (final (
              locale,
              fieldLabels,
              notice,
              imeSetting,
              imeDescription,
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
                'Androidキーボードの個人学習を許可',
                '各セッションの初期設定では無効です。設定変更は次にテキスト欄へフォーカスしたときに反映されます。有効にすると、Androidの入力方法に入力履歴やユーザー辞書などの個人データの更新を許可します。実際の動作はキーボード側で管理されます。',
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
                'Allow Android keyboard learning',
                'Off by default each session. Changes apply the next time you focus a text field. When enabled, the Android input method may update personalized typing history or dictionaries; actual behavior is controlled by the keyboard.',
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
          expect(
            tester
                .getSemantics(find.bySemanticsLabel(notice))
                .getSemanticsData()
                .flagsCollection
                .isLiveRegion,
            isTrue,
          );
          expect(find.text(imeDescription), findsOneWidget);
          final imeSwitch = find.byKey(
            const ValueKey('android-ime-personalized-learning'),
          );
          expect(imeSwitch, findsOneWidget);
          final imeData = tester.getSemantics(imeSwitch).getSemanticsData();
          expect(imeData.label, contains(imeSetting));
          expect(imeData.flagsCollection.isToggled, Tristate.isFalse);
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
        debugDefaultTargetPlatformOverride = null;
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'Android IME personalized learning is opt-in for source and translation',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1000, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      try {
        for (final (locale, title, description) in [
          (
            const Locale('ja'),
            'Androidキーボードの個人学習を許可',
            '各セッションの初期設定では無効です。設定変更は次にテキスト欄へフォーカスしたときに反映されます。有効にすると、Androidの入力方法に入力履歴やユーザー辞書などの個人データの更新を許可します。実際の動作はキーボード側で管理されます。',
          ),
          (
            const Locale('en'),
            'Allow Android keyboard learning',
            'Off by default each session. Changes apply the next time you focus a text field. When enabled, the Android input method may update personalized typing history or dictionaries; actual behavior is controlled by the keyboard.',
          ),
        ]) {
          tester.binding.platformDispatcher.localesTestValue = [locale];
          await tester.pumpWidget(const SizedBox());
          await tester.pumpWidget(const KotohaApp());
          await tester.pumpAndSettle();

          final setting = find.byKey(
            const ValueKey('android-ime-personalized-learning'),
          );
          expect(find.text(title), findsOneWidget);
          expect(find.text(description), findsOneWidget);
          expect(setting, findsOneWidget);

          final sourceField = tester.widget<TextField>(
            find.byKey(const ValueKey('source-text')),
          );
          final translationField = tester.widget<TextField>(
            find.byKey(const ValueKey('translation-text-0')),
          );
          expect(sourceField.enableIMEPersonalizedLearning, isFalse);
          expect(translationField.enableIMEPersonalizedLearning, isFalse);

          final sourceFinder = find.byKey(const ValueKey('source-text'));
          await tester.showKeyboard(sourceFinder);
          expect(
            tester
                .testTextInput
                .setClientArgs!['enableIMEPersonalizedLearning'],
            isFalse,
          );

          await tester.tap(setting);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('source-text')))
                .enableIMEPersonalizedLearning,
            isTrue,
          );
          expect(
            tester
                .widget<TextField>(
                  find.byKey(const ValueKey('translation-text-0')),
                )
                .enableIMEPersonalizedLearning,
            isTrue,
          );
          await tester.showKeyboard(sourceFinder);
          expect(
            tester
                .testTextInput
                .setClientArgs!['enableIMEPersonalizedLearning'],
            isTrue,
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('discloses keyboard privacy control limits outside Android', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    try {
      for (final (locale, notice) in [
        (
          const Locale('ja'),
          'このプラットフォームでは、ことはからキーボードの学習を制御できません。入力方法のプライバシー設定をご確認ください。',
        ),
        (
          const Locale('en'),
          "Kotoha cannot control keyboard learning on this platform. Check your input method's privacy settings.",
        ),
      ]) {
        tester.binding.platformDispatcher.localesTestValue = [locale];
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const KotohaApp());
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('android-ime-personalized-learning')),
          findsNothing,
        );
        expect(find.text(notice), findsOneWidget);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('supports localized keyboard traversal and actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      for (final (
            locale,
            sourceLanguage,
            sourceText,
            targetLanguage,
            translation,
            interfaceLanguage,
            licenses,
            copyOne,
            copyTwo,
            removeOne,
            removeTwo,
            addTranslation,
          )
          in [
            (
              const Locale('ja'),
              '原文の言語',
              '原文',
              '訳先の言語',
              '手入力した訳文',
              '表示言語',
              'ライセンス',
              '1件目の訳文をコピー',
              '2件目の訳文をコピー',
              '1件目の訳先を削除',
              '2件目の訳先を削除',
              '訳先を追加',
            ),
            (
              const Locale('en'),
              'Source language',
              'Source text',
              'Target language',
              'Manual translation',
              'Interface language',
              'Licenses',
              'Copy translation 1',
              'Copy translation 2',
              'Remove translation 1',
              'Remove translation 2',
              'Add translation',
            ),
          ]) {
        tester.binding.platformDispatcher.localesTestValue = [locale];
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const KotohaApp());
        await tester.pumpAndSettle();

        Future<void> pressTab() async {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }

        Future<void> pressShiftTab() async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.pump();
        }

        void expectFocused(Finder finder, String label) {
          expect(
            tester
                .getSemantics(finder)
                .getSemanticsData()
                .flagsCollection
                .isFocused,
            Tristate.isTrue,
            reason: 'Keyboard focus should be on $label.',
          );
        }

        // Bidi direction updates must not replace the accessible name/value or
        // break keyboard focus order for these dynamically rebuilt fields.
        const rtlLanguageName = 'العربية';
        final languageFields = [
          (find.byKey(const ValueKey('source-language')), sourceLanguage),
          (find.byKey(const ValueKey('target-language-0')), targetLanguage),
        ];
        for (final (field, label) in languageFields) {
          tester.widget<TextField>(field).controller!.text = rtlLanguageName;
          await tester.pump();
          final semanticField = find.bySemanticsLabel(label);
          expect(semanticField, findsOneWidget);
          final data = tester.getSemantics(semanticField).getSemanticsData();
          expect(data.label, label);
          expect(data.value, rtlLanguageName);
          expect(data.flagsCollection.isTextField, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(data.hasAction(SemanticsAction.focus), isTrue);
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          expect(
            tester.widget<EditableText>(editable).textDirection,
            TextDirection.rtl,
          );
        }

        final firstCardOrder = [
          find.byTooltip(interfaceLanguage),
          find.byTooltip(licenses),
          find.byKey(const ValueKey('android-ime-personalized-learning')),
          find.bySemanticsLabel(sourceLanguage),
          find.bySemanticsLabel(sourceText),
          find.bySemanticsLabel(targetLanguage),
          find.byTooltip(copyOne),
          find.bySemanticsLabel(translation),
          find.bySemanticsLabel(addTranslation),
        ];
        for (var index = 0; index < firstCardOrder.length; index++) {
          await pressTab();
          expectFocused(firstCardOrder[index], 'initial control $index');
          if (index == 2) {
            await tester.sendKeyEvent(LogicalKeyboardKey.space);
            await tester.pumpAndSettle();
            expectFocused(
              firstCardOrder[index],
              'IME setting after keyboard activation',
            );
          }
          if (index == 3) {
            await pressTab();
            expectFocused(firstCardOrder[4], 'source text after RTL language');
            await pressShiftTab();
            expectFocused(
              firstCardOrder[3],
              'source language after reverse tab',
            );
          } else if (index == 5) {
            await pressTab();
            expectFocused(
              firstCardOrder[6],
              'copy action after RTL target language',
            );
            await pressShiftTab();
            expectFocused(
              firstCardOrder[5],
              'target language after reverse tab',
            );
          }
        }

        // The add action is operable from the keyboard, not only discoverable.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expectFocused(
          find.bySemanticsLabel(addTranslation),
          'add translation after adding a card',
        );
        expect(find.byTooltip(copyTwo), findsOneWidget);
        expect(find.byTooltip(removeOne), findsOneWidget);
        expect(find.byTooltip(removeTwo), findsOneWidget);

        // Start again at the first control and verify forward/reverse order for
        // both translation cards, including their individually named actions.
        final twoCardOrder = [
          find.byTooltip(interfaceLanguage),
          find.byTooltip(licenses),
          find.byKey(const ValueKey('android-ime-personalized-learning')),
          find.bySemanticsLabel(sourceLanguage),
          find.bySemanticsLabel(sourceText),
          find.bySemanticsLabel(targetLanguage).at(0),
          find.byTooltip(copyOne),
          find.byTooltip(removeOne),
          find.bySemanticsLabel(translation).at(0),
          find.bySemanticsLabel(targetLanguage).at(1),
          find.byTooltip(copyTwo),
          find.byTooltip(removeTwo),
          find.bySemanticsLabel(translation).at(1),
          find.bySemanticsLabel(addTranslation),
        ];
        await pressTab();
        expectFocused(twoCardOrder.first, 'first control after adding a card');
        for (var index = 1; index < twoCardOrder.length; index++) {
          await pressTab();
          expectFocused(twoCardOrder[index], 'two-card control $index');
        }
        await pressShiftTab();
        expectFocused(
          find.bySemanticsLabel(translation).at(1),
          'second translation',
        );
        await pressShiftTab();
        expectFocused(find.byTooltip(removeTwo), 'remove second translation');

        // The remove action is also keyboard-operable.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byTooltip(copyOne), findsOneWidget);
        expect(find.byTooltip(copyTwo), findsNothing);
        expect(find.byTooltip(removeOne), findsNothing);
        expect(find.byTooltip(removeTwo), findsNothing);
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      semantics.dispose();
    }
  });

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
      await tester.tap(
        find
            .byType(CheckedPopupMenuItem<Locale>)
            .at(choice == 'English' ? 1 : 0),
      );
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
    await tester.tap(find.byType(CheckedPopupMenuItem<Locale>).at(1));
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
        await tester.tap(
          find
              .byType(CheckedPopupMenuItem<Locale>)
              .at(switchTo == 'English' ? 1 : 0),
        );
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
    final clipboardNotice = find.textContaining(
      'Copied translations are sent to the OS clipboard',
    );
    await tester.dragUntilVisible(
      clipboardNotice,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    expect(clipboardNotice, findsOneWidget);
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
