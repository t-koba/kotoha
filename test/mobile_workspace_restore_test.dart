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

  Map<String, Object> bytes(Uint8List data, {String name = 'workspace.txt'}) =>
      {'name': name, 'bytes': data};

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

    Future<void> populate(WidgetTester tester) async {
      await tester.enterText(field('source-language'), 'current-language');
      await tester.enterText(field('target-language-0'), 'current-target');
      await tester.enterText(
        field('translation-text-0'),
        'current translation',
      );
    }

    mobileTest('confirmation replaces a populated workspace', (tester) async {
      reply = () async => document(formatWorkspaceExport(draft()));
      await open(tester, source: 'current source');
      await populate(tester);

      await restore(tester);

      expect(
        find.byKey(const ValueKey('restore-workspace-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('restore-workspace-confirm')));
      await tester.pumpAndSettle();

      expectRestored(tester);
    });

    mobileTest('restoring an empty export clears every stale field', (
      tester,
    ) async {
      reply = () async =>
          document(formatWorkspaceExport(TextWorkspaceDraft.empty()));
      await open(tester, source: 'stale source');
      await populate(tester);
      final addTranslation = find.text('Add translation');
      await tester.ensureVisible(addTranslation);
      await tester.tap(addTranslation);
      await tester.pumpAndSettle();
      await tester.enterText(field('target-language-1'), 'fr');
      await tester.enterText(field('translation-text-1'), 'second');

      await restore(tester);
      await tester.tap(field('restore-workspace-confirm'));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'source-language'), isEmpty);
      expect(textOf(tester, 'source-text'), isEmpty);
      expect(textOf(tester, 'target-language-0'), isEmpty);
      expect(textOf(tester, 'translation-text-0'), isEmpty);
      expect(find.byKey(const ValueKey('target-language-1')), findsNothing);
      expect(find.byKey(const ValueKey('translation-text-1')), findsNothing);
      expect(find.text('Workspace restored.'), findsOneWidget);
    });

    mobileTest('canceling confirmation keeps a populated workspace', (
      tester,
    ) async {
      reply = () async => document(formatWorkspaceExport(draft()));
      await open(tester, source: 'current source');
      await populate(tester);

      await restore(tester);

      expect(
        find.byKey(const ValueKey('restore-workspace-cancel')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('restore-workspace-cancel')));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'source-language'), 'current-language');
      expect(textOf(tester, 'source-text'), 'current source');
      expect(textOf(tester, 'target-language-0'), 'current-target');
      expect(textOf(tester, 'translation-text-0'), 'current translation');
      expect(find.text('Workspace restored.'), findsNothing);
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
      reply = () async => throw PlatformException(
        code: 'unsupported_type',
        message: 'private/path',
      );
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(
        find.text('Choose a .txt, .md, or .markdown file to restore.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    });

    mobileTest('a valid export named .pdf is rejected before parsing', (
      tester,
    ) async {
      reply = () async =>
          document(formatWorkspaceExport(draft()), name: 'workspace.PDF');
      await open(tester, source: 'keep me');

      await restore(tester);

      expect(
        find.text('Choose a .txt, .md, or .markdown file to restore.'),
        findsOneWidget,
      );
      expect(find.text('Workspace restored.'), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(textOf(tester, 'source-text'), 'keep me');
    });

    mobileTest('an oversized document is rejected with its own notice', (
      tester,
    ) async {
      reply = () async =>
          throw PlatformException(code: 'too_large', message: 'private/path');
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

    mobileTest('restores a v2 document with a UTF-8 BOM', (tester) async {
      reply = () async => bytes(
        Uint8List.fromList([
          0xef,
          0xbb,
          0xbf,
          ...utf8.encode(formatWorkspaceExport(draft())),
        ]),
      );
      await open(tester);

      await restore(tester);

      expect(textOf(tester, 'source-language'), 'ja');
      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
      expect(textOf(tester, 'target-language-1'), 'fr');
      expect(textOf(tester, 'translation-text-1'), 'bonjour');
      expect(find.text('Workspace restored.'), findsOneWidget);
    });

    mobileTest('malformed UTF-8 bytes keep drafts without leaking details', (
      tester,
    ) async {
      final valid = formatWorkspaceExport(draft());
      final at = valid.indexOf('bonjour');
      expect(at, greaterThan(0));
      final invalid = Uint8List.fromList([
        ...utf8.encode(valid.substring(0, at)),
        0xff,
        ...utf8.encode(valid.substring(at + 'bonjour'.length)),
      ]);
      reply = () async => bytes(invalid);
      await open(tester, source: 'existing source');

      await restore(tester);

      expect(
        find.text('This file is not a Kotoha v2 workspace export.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'existing source');
      expect(find.text('Workspace restored.'), findsNothing);
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
