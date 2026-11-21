import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/workspace.dart';
import 'package:kotoha/workspace_export.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(
    () => binding.platformDispatcher.localesTestValue = const [Locale('en')],
  );
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  TextWorkspaceDraft expectedDraft() => TextWorkspaceDraft(
    sourceLanguage: 'ja',
    sourceText: '原文',
    translations: const [
      ManualTranslationDraft(targetLanguage: 'en', text: 'Bonjour'),
      ManualTranslationDraft(targetLanguage: 'fr', text: 'Hello, 🌏'),
    ],
  );

  void mockClipboard(
    WidgetTester tester,
    List<MethodCall> calls, {
    Object? failure,
  }) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          calls.add(call);
          if (failure != null) throw failure;
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
  }

  Future<void> withPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pumpWorkspace(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const KotohaApp());
  }

  Future<void> fillWorkspace(WidgetTester tester) async {
    await tester.enterText(find.byKey(const ValueKey('source-language')), 'ja');
    await tester.enterText(find.byKey(const ValueKey('source-text')), '原文');
    await tester.enterText(
      find.byKey(const ValueKey('target-language-0')),
      'en',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-0')),
      'Bonjour',
    );
    final add = find.text('Add translation');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('target-language-1')),
      'fr',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-1')),
      'Hello, 🌏',
    );
  }

  Future<void> tapCopy(WidgetTester tester) async {
    final button = find.byKey(const ValueKey('copy-workspace'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
  }

  for (final platform in [TargetPlatform.macOS, TargetPlatform.android]) {
    testWidgets('$platform copies the whole workspace verbatim', (
      tester,
    ) async {
      await withPlatform(platform, () async {
        final calls = <MethodCall>[];
        mockClipboard(tester, calls);
        await pumpWorkspace(tester);
        await fillWorkspace(tester);

        expect(
          find.text(
            'Copy writes the source and all translations to the OS clipboard; '
            'the workspace stays temporary.',
          ),
          findsOneWidget,
        );
        await tapCopy(tester);

        expect(calls, hasLength(1));
        expect(calls.single.method, 'Clipboard.setData');
        expect(calls.single.arguments, {
          'text': formatWorkspaceExport(expectedDraft()),
        });
        expect(find.text('Workspace copied.'), findsOneWidget);
      });
    });
  }

  testWidgets('copy survives a NUL-terminated clipboard consumer', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    mockClipboard(tester, calls);
    await pumpWorkspace(tester);
    await tester.enterText(find.byKey(const ValueKey('source-language')), 'ja');
    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'A\u0000B',
    );
    await tester.enterText(
      find.byKey(const ValueKey('target-language-0')),
      'en',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-0')),
      'bonjour',
    );
    await tapCopy(tester);

    expect(calls, hasLength(1));
    final payload = calls.single.arguments!['text'] as String;
    // Win32 CF_UNICODETEXT consumers stop at the first NUL.
    final delivered = payload.split('\u0000').first;
    expect(parseWorkspaceExport(delivered).sourceText, 'A\u0000B');
    expect(parseWorkspaceExport(delivered).translations.single.text, 'bonjour');
  });

  testWidgets('Windows refuses to copy a translation containing NUL', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final calls = <MethodCall>[];
      mockClipboard(tester, calls);
      await pumpWorkspace(tester);
      await tester.enterText(
        find.byKey(const ValueKey('translation-text-0')),
        'A\u0000B',
      );
      final copy = find.byKey(const ValueKey('copy-translation-0'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();

      expect(calls, isEmpty);
      expect(
        find.text(
          'The Windows clipboard cannot paste a NUL character. Export the translation instead.',
        ),
        findsOneWidget,
      );
      expect(find.text('Translation copied.'), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('translation-text-0')))
            .controller!
            .text,
        'A\u0000B',
      );
    });
  });

  testWidgets('Windows copies an ordinary translation verbatim', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final calls = <MethodCall>[];
      mockClipboard(tester, calls);
      await pumpWorkspace(tester);
      await tester.enterText(
        find.byKey(const ValueKey('translation-text-0')),
        'Hello, 🌏',
      );
      final copy = find.byKey(const ValueKey('copy-translation-0'));
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pump();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'Clipboard.setData');
      expect(calls.single.arguments, {'text': 'Hello, 🌏'});
      expect(find.text('Translation copied.'), findsOneWidget);
    });
  });

  testWidgets('an empty workspace is not copied', (tester) async {
    final calls = <MethodCall>[];
    mockClipboard(tester, calls);
    await pumpWorkspace(tester);

    await tapCopy(tester);

    expect(calls, isEmpty);
    expect(
      find.text('Enter source text or a translation to copy.'),
      findsOneWidget,
    );
    expect(find.text('Workspace copied.'), findsNothing);
  });

  testWidgets('a clipboard rejection is reported without changing drafts', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    mockClipboard(
      tester,
      calls,
      failure: PlatformException(code: 'clipboard-unavailable'),
    );
    await pumpWorkspace(tester);
    await fillWorkspace(tester);

    await tapCopy(tester);

    expect(calls, hasLength(1));
    expect(find.text('Could not copy to the clipboard.'), findsOneWidget);
    expect(find.text('Workspace copied.'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('source-text')))
          .controller!
          .text,
      '原文',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('translation-text-1')))
          .controller!
          .text,
      'Hello, 🌏',
    );
  });
}
