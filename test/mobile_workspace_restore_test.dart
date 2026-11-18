import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_document_picker.dart';
import 'package:kotoha/workspace.dart';
import 'package:kotoha/workspace_export.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.kotoha/text_import');
  late Future<Object?> Function() reply;
  var calls = 0;

  Map<String, Object> document(String text, {String name = 'workspace.txt'}) =>
      {'name': name, 'bytes': Uint8List.fromList(utf8.encode(text))};

  Finder field(String key) => find.byKey(ValueKey(key));

  String textOf(WidgetTester tester, String key) =>
      tester.widget<TextField>(field(key)).controller!.text;

  TextWorkspaceDraft draft() => TextWorkspaceDraft(
    sourceLanguage: 'ja',
    sourceText: '第一行\nsecond 🌏',
    translations: [
      ManualTranslationDraft(
        targetLanguage: 'en',
        text: 'Translation 2 language: fr\nTranslation text:\nnot a header',
      ),
      const ManualTranslationDraft(targetLanguage: 'fr', text: 'bonjour'),
    ],
  );

  Future<void> open(WidgetTester tester, {String source = ''}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KotohaApp());
    if (source.isNotEmpty) {
      await tester.enterText(field('source-text'), source);
    }
  }

  Future<void> restore(WidgetTester tester) async {
    await tester.ensureVisible(field('restore-workspace'));
    await tester.tap(field('restore-workspace'));
    await tester.pumpAndSettle();
  }

  void expectRestored(WidgetTester tester) {
    expect(textOf(tester, 'source-language'), 'ja');
    expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
    expect(textOf(tester, 'target-language-0'), 'en');
    expect(
      textOf(tester, 'translation-text-0'),
      'Translation 2 language: fr\nTranslation text:\nnot a header',
    );
    expect(textOf(tester, 'target-language-1'), 'fr');
    expect(textOf(tester, 'translation-text-1'), 'bonjour');
    expect(find.text('Workspace restored.'), findsOneWidget);
  }

  setUp(() {
    calls = 0;
    reply = () async => null;
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'open');
      expect(call.arguments, {'maxBytes': maxTextImportBytes});
      calls++;
      return reply();
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.platformDispatcher.clearLocalesTestValue();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    void mobileTest(String name, WidgetTesterCallback body) {
      testWidgets('$platform $name', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        try {
          await body(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    mobileTest('restores a v2 document with all fields', (tester) async {
      reply = () async =>
          document(formatWorkspaceExport(draft()), name: 'workspace.MaRkDoWn');
      await open(tester);

      await restore(tester);

      expectRestored(tester);
      expect(calls, 1);
    });

    mobileTest('cancellation keeps drafts silently', (tester) async {
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(textOf(tester, 'source-text'), 'keep me');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, 1);
    });

    mobileTest('an unsupported document keeps drafts', (tester) async {
      reply = () async => document('not a workspace export');
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(
        find.text('This file is not a Kotoha v2 workspace export.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    });

    mobileTest('an unsupported file type is rejected with its own notice', (
      tester,
    ) async {
      reply = () async =>
          document(formatWorkspaceExport(draft()), name: 'private.pdf');
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(
        find.text('Choose a .txt, .md, or .markdown file to restore.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    });

    mobileTest('an oversized document is rejected with its own notice', (
      tester,
    ) async {
      reply = () async => {
        'name': 'workspace.txt',
        'bytes': Uint8List(maxTextImportBytes + 1),
      };
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(
        find.text(
          'This file is too large to restore. Choose a smaller workspace export.',
        ),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    });

    mobileTest('a native failure keeps drafts without leaking details', (
      tester,
    ) async {
      reply = () async =>
          throw PlatformException(code: 'read_failed', message: 'private/path');
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(find.text('Could not restore the workspace.'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(textOf(tester, 'source-text'), 'keep me');
    });
  }
}
