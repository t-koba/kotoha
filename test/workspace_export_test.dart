import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_document_picker.dart';
import 'package:kotoha/workspace.dart';
import 'package:kotoha/workspace_export.dart';

class _Selector extends FileSelectorPlatform {
  FileSaveLocation? result;
  int calls = 0;
  List<XTypeGroup>? acceptedTypeGroups;
  SaveDialogOptions? options;

  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async {
    calls++;
    this.acceptedTypeGroups = acceptedTypeGroups;
    this.options = options;
    return result;
  }
}

class _Writer {
  final writes = <(String, String)>[];
  Object? failure;

  Future<void> write(String path, String text) async {
    writes.add((path, text));
    final error = failure;
    if (error != null) throw error;
  }
}

TextWorkspaceDraft _draft() => TextWorkspaceDraft(
  sourceLanguage: 'ja',
  sourceText: '原文',
  translations: const [
    ManualTranslationDraft(targetLanguage: 'en', text: 'Bonjour'),
    ManualTranslationDraft(targetLanguage: 'fr', text: 'Hello, 🌏'),
  ],
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;
  late _Selector selector;

  setUp(() {
    original = FileSelectorPlatform.instance;
    selector = _Selector();
    FileSelectorPlatform.instance = selector;
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
  });

  tearDown(() {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Finder field(String key) => find.byKey(ValueKey(key));

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

  Future<void> pumpWorkspace(WidgetTester tester, _Writer writer) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KotohaApp(exportText: writer.write));
  }

  Future<void> openWorkspace(WidgetTester tester, _Writer writer) async {
    await pumpWorkspace(tester, writer);
    await tester.enterText(field('source-language'), 'ja');
    await tester.enterText(field('source-text'), '原文');
    await tester.enterText(field('target-language-0'), 'en');
    await tester.enterText(field('translation-text-0'), 'Bonjour');
    final addTranslation = find.text('Add translation');
    await tester.ensureVisible(addTranslation);
    await tester.tap(addTranslation);
    await tester.pumpAndSettle();
    await tester.enterText(field('target-language-1'), 'fr');
    await tester.enterText(field('translation-text-1'), 'Hello, 🌏');
  }

  test('formats and parses multiline, emoji and RTL text', () {
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: '一行目\n二行目 🌏',
      translations: [
        const ManualTranslationDraft(
          targetLanguage: 'en',
          text: 'line one\nline two',
        ),
        const ManualTranslationDraft(
          targetLanguage: 'he',
          text: 'שלום 🌷\nline two',
        ),
      ],
    );

    final output = formatWorkspaceExport(draft);
    expect(
      output,
      'Kotoha workspace export v2\n'
      'Source language: ja\n'
      r'Source text: 一行目\n二行目 🌏'
      '\n'
      'Translation 1 language: en\n'
      r'Translation text: line one\nline two'
      '\n'
      'Translation 2 language: he\n'
      r'Translation text: שלום 🌷\nline two'
      '\n',
    );
    expect(parseWorkspaceExport(output).toJson(), draft.toJson());
  });

  test('escapes every field so no body can become a header', () {
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'a\\b\nc\rd',
      sourceText: 'keep\nthis',
      translations: [
        const ManualTranslationDraft(targetLanguage: 'x\\y\nz', text: '🌏\r\n'),
      ],
    );

    final output = formatWorkspaceExport(draft);
    expect(
      output,
      'Kotoha workspace export v2\n'
      r'Source language: a\\b\nc\rd'
      '\n'
      r'Source text: keep\nthis'
      '\n'
      r'Translation 1 language: x\\y\nz'
      '\n'
      r'Translation text: 🌏\r\n'
      '\n',
    );
    expect(parseWorkspaceExport(output).toJson(), draft.toJson());
  });

  test('an empty workspace still formats and parses every field', () {
    final output = formatWorkspaceExport(TextWorkspaceDraft.empty());
    expect(
      output,
      'Kotoha workspace export v2\n'
      'Source language: \n'
      'Source text: \n'
      'Translation 1 language: \n'
      'Translation text: \n',
    );
    expect(
      parseWorkspaceExport(output).toJson(),
      TextWorkspaceDraft.empty().toJson(),
    );
  });

  test('a body that looked like a v1 header stays one field', () {
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: 'original',
      translations: [
        ManualTranslationDraft(
          targetLanguage: 'en',
          text:
              'hello\n\nTranslation 2 language: fr\nTranslation text:\nbonjour',
        ),
      ],
    );

    final output = formatWorkspaceExport(draft);
    expect(
      output,
      isNot(contains('Translation 2 language: fr\nTranslation text:')),
    );
    expect(parseWorkspaceExport(output).toJson(), draft.toJson());
  });

  test('accepts CRLF-normalized exports without changing field content', () {
    final draft = _draft();
    final output = formatWorkspaceExport(draft).replaceAll('\n', '\r\n');

    expect(output, contains('\r\n'));
    expect(output.replaceAll('\r\n', ''), isNot(contains('\n')));
    expect(parseWorkspaceExport(output).toJson(), draft.toJson());
  });

  test('rejects malformed CRLF documents instead of guessing fields', () {
    final crlf = formatWorkspaceExport(_draft()).replaceAll('\n', '\r\n');
    final documents = <String>[
      crlf.replaceFirst('Source text: ', 'Source text: raw\r'),
      crlf.replaceAll('\r\n', '\r'),
      crlf.replaceFirst('🌏', r'\q'),
      crlf.substring(0, crlf.length - 2),
    ];
    for (final document in documents) {
      expect(
        () => parseWorkspaceExport(document),
        throwsFormatException,
        reason: document,
      );
    }
  });

  test('rejects malformed documents instead of guessing fields', () {
    final valid = formatWorkspaceExport(_draft());
    final documents = <String>[
      valid.replaceFirst('v2', 'v1'),
      valid.substring(0, valid.length - 1),
      valid.replaceFirst('Source text: ', 'Source body: '),
      '$valid extra line\n',
      valid.replaceFirst(
        'Translation 2 language: ',
        'Translation 3 language: ',
      ),
      valid.replaceFirst('🌏', r'\q'),
      valid.replaceFirst('🌏', r'ending\'),
    ];
    for (final document in documents) {
      expect(
        () => parseWorkspaceExport(document),
        throwsFormatException,
        reason: document,
      );
    }
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform exports the whole workspace to one chosen file', (
      tester,
    ) async {
      await withPlatform(platform, () async {
        final writer = _Writer();
        selector.result = FileSaveLocation('/user/chosen/workspace.txt');
        await openWorkspace(tester, writer);
        final exportButton = field('export-workspace');
        await tester.ensureVisible(exportButton);

        await tester.tap(exportButton);
        await tester.pump();

        expect(writer.writes, [
          ('/user/chosen/workspace.txt', formatWorkspaceExport(_draft())),
        ]);
        expect(selector.calls, 1);
        expect(selector.acceptedTypeGroups, hasLength(1));
        expect(selector.acceptedTypeGroups!.single.extensions, ['txt']);
        expect(selector.acceptedTypeGroups!.single.uniformTypeIdentifiers, [
          'public.utf8-plain-text',
        ]);
        expect(selector.options!.suggestedName, 'workspace.txt');
        expect(selector.options!.confirmButtonText, 'Export');
        expect(find.text('Workspace exported.'), findsOneWidget);
      });
    });
  }

  testWidgets('cancelling the picker writes nothing and keeps drafts', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.macOS, () async {
      final writer = _Writer();
      await openWorkspace(tester, writer);
      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(selector.calls, 1);
      expect(writer.writes, isEmpty);
      expect(find.text('Workspace exported.'), findsNothing);
      expect(find.text('Could not export the workspace.'), findsNothing);
      expect(
        tester.widget<TextField>(field('source-text')).controller!.text,
        '原文',
      );
      expect(
        tester.widget<TextField>(field('translation-text-0')).controller!.text,
        'Bonjour',
      );
      expect(
        tester.widget<TextField>(field('translation-text-1')).controller!.text,
        'Hello, 🌏',
      );
    });
  });

  testWidgets('an empty workspace is not written', (tester) async {
    await withPlatform(TargetPlatform.macOS, () async {
      final writer = _Writer();
      await pumpWorkspace(tester, writer);
      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(
        find.text('Enter source text or a translation to export.'),
        findsOneWidget,
      );
      expect(selector.calls, 0);
      expect(writer.writes, isEmpty);
    });
  });

  testWidgets('a write failure is reported without changing drafts', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer()..failure = const FileSystemException('denied');
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await openWorkspace(tester, writer);
      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(find.text('Could not export the workspace.'), findsOneWidget);
      expect(writer.writes, hasLength(1));
      expect(
        tester.widget<TextField>(field('source-text')).controller!.text,
        '原文',
      );
      expect(
        tester.widget<TextField>(field('translation-text-0')).controller!.text,
        'Bonjour',
      );
      expect(
        tester.widget<TextField>(field('translation-text-1')).controller!.text,
        'Hello, 🌏',
      );
    });
  });

  testWidgets('an export too large to restore is refused before writing', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await pumpWorkspace(tester, writer);
      tester.widget<TextField>(field('source-text')).controller!.text =
          '\\' * (maxTextImportBytes ~/ 2 + 1);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(
        find.text(
          'This workspace export would be too large to restore. Shorten the text and export again.',
        ),
        findsOneWidget,
      );
      expect(selector.calls, 0);
      expect(writer.writes, isEmpty);
    });
  });

  testWidgets('Android has no whole-workspace export action', (tester) async {
    await withPlatform(TargetPlatform.android, () async {
      final writer = _Writer();
      await pumpWorkspace(tester, writer);

      expect(field('export-workspace'), findsNothing);
      expect(find.text('Export workspace'), findsNothing);
      expect(writer.writes, isEmpty);
    });
  });
}
