import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

Future<void> _verifyLazyKeyboardTraversal(
  WidgetTester tester, {
  required double textScale,
  required Size viewSize,
  required int translationCount,
  bool verifyPageDown = false,
}) async {
  tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
  tester.binding.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  addTearDown(tester.binding.platformDispatcher.clearTextScaleFactorTestValue);
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  try {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(const KotohaApp());
    final scrollable = find.byType(Scrollable).first;
    if (verifyPageDown) {
      var focusedButton = false;
      for (var tab = 0; tab < 12 && !focusedButton; tab++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        focusedButton =
            tester.binding.focusManager.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<OutlinedButton>() !=
            null;
      }
      expect(focusedButton, isTrue);
      final position = tester.state<ScrollableState>(scrollable).position;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      position.jumpTo(0);
      await tester.pumpAndSettle();
    }
    for (var index = 1; index < translationCount; index++) {
      final addTranslation = find.text('Add translation');
      await tester.dragUntilVisible(
        addTranslation,
        scrollable,
        const Offset(0, -800),
      );
      await tester.pumpAndSettle();
      await tester.tap(addTranslation);
      await tester.pumpAndSettle();
    }
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();

    final expected = <String>{
      for (var index = 0; index < translationCount; index++) ...[
        'target-language-$index',
        'translation-text-$index',
      ],
    };
    final reached = <String>{};
    var maximumMountedFields = 0;
    for (var tab = 0; tab < 240 && !reached.containsAll(expected); tab++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final mountedFields = find.byType(TextField).evaluate().length;
      if (mountedFields > maximumMountedFields) {
        maximumMountedFields = mountedFields;
      }
      for (final key in expected) {
        final field = find.byKey(ValueKey(key));
        if (field.evaluate().isEmpty) {
          continue;
        }
        final editable = find.descendant(
          of: field,
          matching: find.byType(EditableText),
        );
        if (editable.evaluate().isNotEmpty &&
            identical(
              tester.binding.focusManager.primaryFocus,
              tester.widget<EditableText>(editable).focusNode,
            )) {
          reached.add(key);
        }
      }
    }

    expect(reached, containsAll(expected));
    if (translationCount > 1) {
      expect(maximumMountedFields, lessThan(expected.length + 2));
    } else {
      expect(maximumMountedFields, lessThanOrEqualTo(4));
    }
    expect(tester.takeException(), isNull);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => binding.platformDispatcher.localesTestValue = [const Locale('ja')],
  );
  tearDown(binding.platformDispatcher.clearLocalesTestValue);

  testWidgets('keeps the source separate while adding manual translations', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());

    expect(find.textContaining('自動翻訳は行いません'), findsOneWidget);
    expect(find.textContaining('このアプリには保存されません'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('source-text')), 'こんにちは');
    await tester.dragUntilVisible(
      find.text('訳先を追加'),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('訳先を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-1')),
      'Hello',
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('source-text')))
          .controller!
          .text,
      'こんにちは',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('translation-text-1')))
          .controller!
          .text,
      'Hello',
    );
    expect(find.byKey(const ValueKey('translation-text-0')), findsOneWidget);
  });

  testWidgets('hides draft content while inactive and restores it on resume', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());
    await tester.enterText(find.byKey(const ValueKey('source-text')), 'こんにちは');
    final translationField = find.byKey(const ValueKey('translation-text-0'));
    await tester.dragUntilVisible(
      translationField,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.enterText(translationField, 'Hello');
    final focusedNode = tester.binding.focusManager.primaryFocus;
    expect(focusedNode, isNotNull);

    for (final state in const <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
      if (state == AppLifecycleState.resumed) {
        expect(
          find.text('下書きはメモリ内にのみ保持され、Kotohaが非アクティブの間は非表示です。'),
          findsNothing,
        );
        expect(
          tester
              .widget<ExcludeSemantics>(
                find.byKey(const ValueKey('workspace-semantics-shield')),
              )
              .excluding,
          isFalse,
        );
        expect(
          tester
              .widget<AbsorbPointer>(
                find.byKey(const ValueKey('workspace-input-shield')),
              )
              .absorbing,
          isFalse,
        );
      } else {
        expect(
          find.text('下書きはメモリ内にのみ保持され、Kotohaが非アクティブの間は非表示です。'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<ExcludeSemantics>(
                find.byKey(const ValueKey('workspace-semantics-shield')),
              )
              .excluding,
          isTrue,
        );
        expect(
          tester
              .widget<AbsorbPointer>(
                find.byKey(const ValueKey('workspace-input-shield')),
              )
              .absorbing,
          isTrue,
        );
      }
    }

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('source-text')))
          .controller!
          .text,
      'こんにちは',
    );
    expect(
      tester.widget<TextField>(translationField).controller!.text,
      'Hello',
    );
    expect(tester.binding.focusManager.primaryFocus, same(focusedNode));
  });

  testWidgets('blocks hardware and IME edits while inactive', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await tester.pumpWidget(const KotohaApp());
      for (final key in ['source-text', 'translation-text-0']) {
        final field = find.byKey(ValueKey(key));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, 'secret');
        final controller = tester.widget<TextField>(field).controller!;
        controller.selection = const TextSelection(
          baseOffset: 1,
          extentOffset: 4,
        );
        final draft = controller.value;
        final focusedNode = tester.binding.focusManager.primaryFocus;
        expect(focusedNode, isNotNull);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        // Exercise both the transition before readOnly rebuilds and the cover.
        for (final covered in [false, true]) {
          if (covered) await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
          expect(controller.value, draft, reason: '$key inactive Backspace');
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          expect(
            controller.value,
            draft,
            reason: '$key inactive caret movement',
          );
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: 'replacement',
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: 0, end: 3),
            ),
          );
          expect(controller.value, draft, reason: '$key inactive IME');
          tester.testTextInput.updateEditingValue(
            draft.copyWith(selection: const TextSelection.collapsed(offset: 0)),
          );
          expect(
            controller.value,
            draft,
            reason: '$key inactive IME selection',
          );
        }
        await tester.pump();
        expect(controller.value, draft);
        expect(tester.binding.focusManager.primaryFocus, same(focusedNode));

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(controller.value, draft);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(
          controller.text,
          'set',
          reason: '$key resumed selection editing',
        );
        tester.testTextInput.enterText('resumed');
        await tester.pump();
        expect(controller.text, 'resumed');
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'resume');
        expect(tester.binding.focusManager.primaryFocus, same(focusedNode));
      }

      final addTranslation = find.text('訳先を追加');
      await tester.dragUntilVisible(
        addTranslation,
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.tap(addTranslation);
      await tester.pumpAndSettle();
      final buttonFocus = tester.binding.focusManager.primaryFocus;
      expect(buttonFocus, isNotNull);
      expect(find.byKey(const ValueKey('translation-text-1')), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('translation-text-2')), findsNothing);
      expect(tester.binding.focusManager.primaryFocus, same(buttonFocus));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('translation-text-2')), findsNothing);
      expect(tester.binding.focusManager.primaryFocus, same(buttonFocus));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps the lifecycle key shield out of tab traversal', (
    tester,
  ) async {
    try {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await tester.pumpWidget(const KotohaApp());
      final shield = tester.widget<Focus>(
        find.byKey(const ValueKey('workspace-keyboard-shield')),
      );

      expect(shield.skipTraversal, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('keeps lazy translation fields keyboard-reachable at 2x scale', (
    tester,
  ) async {
    await _verifyLazyKeyboardTraversal(
      tester,
      textScale: 2.0,
      viewSize: const Size(320, 640),
      translationCount: 5,
    );
  });

  testWidgets('keeps lazy translation fields keyboard-reachable at 4x scale', (
    tester,
  ) async {
    await _verifyLazyKeyboardTraversal(
      tester,
      textScale: 4.0,
      viewSize: const Size(420, 760),
      translationCount: 5,
    );
  });

  testWidgets('reaches initial fields in a short high-scale viewport', (
    tester,
  ) async {
    await _verifyLazyKeyboardTraversal(
      tester,
      textScale: 4.0,
      viewSize: const Size(420, 200),
      translationCount: 1,
      verifyPageDown: true,
    );
  });

  testWidgets('pages the lazy workspace from the toolbar using only keys', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    tester.view.physicalSize = const Size(420, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      await tester.pumpWidget(const KotohaApp());

      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      bool hasFocus(Finder finder) {
        final elements = finder.evaluate();
        final context = tester.binding.focusManager.primaryFocus?.context;
        if (elements.isEmpty || context == null) return false;
        var found = context == elements.single;
        context.visitAncestorElements((element) {
          if (element == elements.single) found = true;
          return !found;
        });
        return found;
      }

      bool focused(String key) => hasFocus(find.byKey(ValueKey(key)));

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      // Toolbar focus is outside the Scrollable: it must still be possible to
      // page the workspace without a pointer or stealing text-editing keys.
      await press(LogicalKeyboardKey.tab);
      expect(focused('ui-language'), isTrue);
      final toolbarFocus = tester.binding.focusManager.primaryFocus;
      await press(LogicalKeyboardKey.pageDown);
      expect(position.pixels, greaterThan(0));
      expect(tester.binding.focusManager.primaryFocus, same(toolbarFocus));
      await press(LogicalKeyboardKey.pageUp);
      expect(position.pixels, 0);

      for (var tab = 0; tab < 10 && !focused('source-text'); tab++) {
        await press(LogicalKeyboardKey.tab);
      }
      expect(focused('source-text'), isTrue);
      tester.testTextInput.enterText('first\nsecond');
      await tester.pumpAndSettle();
      final editingOffset = position.pixels;
      await press(LogicalKeyboardKey.arrowDown);
      await press(LogicalKeyboardKey.space);
      expect(focused('source-text'), isTrue);
      expect(position.pixels, editingOffset);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('source-text')))
            .controller!
            .text,
        'first\nsecond',
      );

      // Reach Add translation by Tab, and activate it without pointer scrolling.
      final addTranslation = find.widgetWithText(
        OutlinedButton,
        'Add translation',
      );
      for (var tab = 0; tab < 30 && !hasFocus(addTranslation); tab++) {
        await press(LogicalKeyboardKey.tab);
      }
      expect(hasFocus(addTranslation), isTrue);
      final addFocus = tester.binding.focusManager.primaryFocus;
      for (var index = 1; index < 12; index++) {
        await press(
          index.isEven ? LogicalKeyboardKey.space : LogicalKeyboardKey.enter,
        );
      }

      // Return to the toolbar. Page back to the top so later cards leave the
      // bounded cache; then visit every field/action by paging and tabbing.
      for (var tab = 0; tab < 100 && !focused('ui-language'); tab++) {
        await press(LogicalKeyboardKey.tab);
      }
      expect(focused('ui-language'), isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await press(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(tester.binding.focusManager.primaryFocus, same(addFocus));
      for (var page = 0; page < 10 && position.extentAfter > 0; page++) {
        await press(LogicalKeyboardKey.pageDown);
      }
      expect(hasFocus(addTranslation), isTrue);
      expect(
        tester
            .getRect(addTranslation)
            .overlaps(tester.getRect(find.byType(Scrollable).first)),
        isTrue,
      );
      await press(LogicalKeyboardKey.tab);
      expect(focused('ui-language'), isTrue);
      for (var page = 0; page < 40 && position.pixels > 0; page++) {
        await press(LogicalKeyboardKey.pageUp);
      }
      expect(position.pixels, 0);
      expect(find.byKey(const ValueKey('translation-text-11')), findsNothing);
      final expected = <String>{
        'ui-language',
        'show-licenses',
        'source-language',
        'import-source',
        'source-text',
        for (var index = 0; index < 12; index++) ...[
          'target-language-$index',
          'copy-translation-$index',
          'export-translation-$index',
          'remove-translation-$index',
          'translation-text-$index',
        ],
      };
      final reached = <String>{};
      for (var tab = 0; tab < 100 && !reached.containsAll(expected); tab++) {
        for (final key in expected) {
          if (focused(key)) {
            expect(
              tester
                  .getRect(find.byKey(ValueKey(key)))
                  .overlaps(Offset.zero & tester.view.physicalSize),
              isTrue,
              reason: '$key must be visible when reached',
            );
            reached.add(key);
          }
        }
        await press(LogicalKeyboardKey.tab);
        if (focused('ui-language')) await press(LogicalKeyboardKey.pageDown);
      }
      expect(reached, containsAll(expected));
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('does not allow deleting the final translation field', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());
    await tester.dragUntilVisible(
      find.text('訳先を追加'),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('訳先を追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-translation-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('translation-text-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-text-1')), findsNothing);
  });

  testWidgets(
    'repeated activation of one rendered Remove callback is harmless',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const KotohaApp());

      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('translation-text-2')), findsOneWidget);

      // Invoke the same rendered callback twice with no rebuild in between.
      // The first removal shrinks the list; a stale index would make the
      // second invocation throw RangeError before any controller is read.
      final button = tester.widget<IconButton>(
        find.byKey(const ValueKey('remove-translation-2')),
      );
      final onPressed = button.onPressed!;
      onPressed();
      onPressed();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('translation-text-2')), findsNothing);
      expect(find.byKey(const ValueKey('translation-text-1')), findsOneWidget);
    },
  );

  testWidgets(
    'removing a middle target keeps the surviving translations aligned',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const KotohaApp());

      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      for (final entry in const <(String, String)>[
        ('translation-text-0', 'first'),
        ('translation-text-1', 'middle'),
        ('translation-text-2', 'last'),
      ]) {
        await tester.enterText(find.byKey(ValueKey(entry.$1)), entry.$2);
      }
      await tester.tap(find.byKey(const ValueKey('remove-translation-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remove-translation-confirm')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('translation-text-0')))
            .controller!
            .text,
        'first',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('translation-text-1')))
            .controller!
            .text,
        'last',
      );
      expect(find.byKey(const ValueKey('translation-text-2')), findsNothing);
    },
  );

  testWidgets(
    'removing a middle translation keeps focus on the field that shifts in',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const KotohaApp());

      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      for (final entry in const <(String, String)>[
        ('translation-text-0', 'first'),
        ('translation-text-1', 'middle'),
        ('translation-text-2', 'last'),
      ]) {
        await tester.enterText(find.byKey(ValueKey(entry.$1)), entry.$2);
      }

      // Pointer removal of the middle field must not drop focus back to the
      // enclosing scope: the following field shifts into this slot and keeps
      // focus, with its exact text preserved.
      await tester.tap(find.byKey(const ValueKey('remove-translation-1')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('remove-translation-confirm')),
      );
      await tester.pumpAndSettle();
      final survivor = find.byKey(const ValueKey('translation-text-1'));
      final survivorFocus = tester
          .widget<EditableText>(
            find.descendant(of: survivor, matching: find.byType(EditableText)),
          )
          .focusNode;
      expect(survivorFocus.hasFocus, isTrue);
      expect(tester.widget<TextField>(survivor).controller!.text, 'last');
      expect(find.byKey(const ValueKey('translation-text-2')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling removal of a nonempty translation keeps it and its focus',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const KotohaApp());

      await tester.tap(find.text('訳先を追加'));
      await tester.pumpAndSettle();
      final language = find.byKey(const ValueKey('target-language-1'));
      final translation = find.byKey(const ValueKey('translation-text-1'));
      const languageTag = 'ja-JP';
      const text = '日本語と English\nالعربية';
      await tester.enterText(language, languageTag);
      await tester.enterText(translation, text);
      await tester.tap(find.byKey(const ValueKey('remove-translation-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('remove-translation-cancel')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('remove-translation-1')),
        findsOneWidget,
      );
      expect(tester.widget<TextField>(language).controller!.text, languageTag);
      final translationField = tester.widget<TextField>(translation);
      expect(translationField.controller!.text, text);
      expect(translationField.focusNode!.hasFocus, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copies exact multilingual manual text', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(const KotohaApp());
    final clipboardNotice = find.text(
      'コピーした訳文はOSのクリップボードに渡され、OSやクリップボード機能によって参照・保持・共有される場合があります。',
    );
    await tester.dragUntilVisible(
      clipboardNotice,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(clipboardNotice, findsOneWidget);

    final copyButton = find.byKey(const ValueKey('copy-translation-0'));
    await tester.dragUntilVisible(
      copyButton,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    const translation = 'Bonjour 👋\nこんにちは';
    final translationField = find.byKey(const ValueKey('translation-text-0'));
    await tester.dragUntilVisible(
      translationField,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.enterText(translationField, translation);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('translation-text-0')))
          .controller!
          .text,
      translation,
    );
    expect(tester.widget<IconButton>(copyButton).onPressed, isNotNull);
    await tester.tap(copyButton);
    await tester.pump();

    final clipboardCall = calls.singleWhere(
      (call) => call.method == 'Clipboard.setData',
    );
    expect(clipboardCall.arguments, {'text': translation});
    expect(find.text('訳文をコピーしました'), findsOneWidget);
  });
  testWidgets('explains why an empty translation cannot be copied', (
    tester,
  ) async {
    var copyWrites = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') copyWrites++;
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(const KotohaApp());
    final copyButton = find.byKey(const ValueKey('copy-translation-0'));
    await tester.dragUntilVisible(
      copyButton,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pump();

    expect(copyWrites, 0);
    expect(find.text('コピーする訳文を入力してください'), findsOneWidget);
  });
  testWidgets('reports when the operating system rejects clipboard access', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard-unavailable');
        }
        if (call.method == 'Clipboard.hasStrings') return {'value': false};
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(const KotohaApp());
    final translationField = find.byKey(const ValueKey('translation-text-0'));
    await tester.dragUntilVisible(
      translationField,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.enterText(translationField, 'Hello');
    final copyButton = find.byKey(const ValueKey('copy-translation-0'));
    await tester.dragUntilVisible(
      copyButton,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(copyButton);
    await tester.pump();

    expect(find.text('クリップボードにコピーできませんでした'), findsOneWidget);
    expect(find.text('訳文をコピーしました'), findsNothing);
  });

  testWidgets('supports multiple targets at narrow width and large text', (
    tester,
  ) async {
    binding.platformDispatcher.localesTestValue = [const Locale('en')];
    binding.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(binding.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const KotohaApp());
    final scrollable = find.byType(Scrollable).first;
    await tester.dragUntilVisible(
      find.text('Add translation'),
      scrollable,
      const Offset(0, -400),
    );
    await tester.tap(find.text('Add translation'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('target-language-1')),
      scrollable,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('copy-translation-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('remove-translation-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
