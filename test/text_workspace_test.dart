import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

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

  testWidgets('retains in-memory drafts through background transitions', (
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
