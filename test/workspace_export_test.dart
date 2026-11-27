import 'dart:async';
import 'dart:convert';
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
  Completer<FileSaveLocation?>? pending;
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
    final pendingPicker = pending;
    return pendingPicker != null ? pendingPicker.future : result;
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

  test('keeps embedded NUL out of the portable document', () {
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: 'A\u0000B',
      translations: const [
        ManualTranslationDraft(targetLanguage: 'en', text: r'\0 literal'),
      ],
    );
    final output = formatWorkspaceExport(draft);
    expect(output, isNot(contains('\u0000')));
    expect(parseWorkspaceExport(output).toJson(), draft.toJson());
  });

  test('unpaired surrogates survive parse and re-export', () {
    final high = String.fromCharCode(0xD800);
    final low = String.fromCharCode(0xDC00);
    final draft = TextWorkspaceDraft(
      sourceLanguage: '$high-language',
      sourceText: '$high A $low ${high}9 🌏',
      translations: [
        ManualTranslationDraft(targetLanguage: 'en', text: '$low 1$high'),
        const ManualTranslationDraft(targetLanguage: 'fr', text: '🌏 ok'),
      ],
    );

    final output = formatWorkspaceExport(draft);
    final restored = parseWorkspaceExport(utf8.decode(utf8.encode(output)));
    expect(restored.sourceLanguage.codeUnits, draft.sourceLanguage.codeUnits);
    expect(restored.sourceText.codeUnits, draft.sourceText.codeUnits);
    for (var index = 0; index < draft.translations.length; index++) {
      expect(
        restored.translations[index].targetLanguage.codeUnits,
        draft.translations[index].targetLanguage.codeUnits,
      );
      expect(
        restored.translations[index].text.codeUnits,
        draft.translations[index].text.codeUnits,
      );
    }
    expect(formatWorkspaceExport(restored), output);
  });

  test('editor normalization replaces only unpaired surrogates', () {
    final high = String.fromCharCode(0xD800);
    final low = String.fromCharCode(0xDC00);
    expect(normalizeWorkspaceDraftForEditing(_draft()), isNull);

    final draft = TextWorkspaceDraft(
      sourceLanguage: 'x$high-y',
      sourceText: '$high$low A $high 🌏',
      translations: [ManualTranslationDraft(targetLanguage: low, text: 'body')],
    );
    final normalized = normalizeWorkspaceDraftForEditing(draft);
    expect(normalized, isNotNull);
    expect(normalized!.sourceLanguage.codeUnits, [0x78, 0xFFFD, 0x2D, 0x79]);
    expect(normalized.sourceText.codeUnits, [
      0xD800,
      0xDC00,
      0x20,
      0x41,
      0x20,
      0xFFFD,
      0x20,
      0xD83C,
      0xDF0F,
    ]);
    expect(normalized.translations.single.targetLanguage.codeUnits, [0xFFFD]);
    expect(normalized.translations.single.text, 'body');
    expect(draft.sourceText.codeUnits.first, 0xD800);
    expect(normalizeWorkspaceDraftForEditing(normalized), isNull);
  });

  test('unpaired surrogates are escaped as four uppercase hex digits', () {
    final high = String.fromCharCode(0xD800);
    final low = String.fromCharCode(0xDFFF);
    final output = formatWorkspaceExport(
      TextWorkspaceDraft(
        sourceLanguage: high,
        sourceText: '$high A $low',
        translations: [
          ManualTranslationDraft(targetLanguage: low, text: '$low$high'),
        ],
      ),
    );

    expect(output, contains(r'\uD800'));
    expect(output, contains(r'\uDFFF'));
    expect(output.codeUnits.every((unit) => unit < 0x80), isTrue);
    expect(utf8.decode(utf8.encode(output)), output);
    final parsed = parseWorkspaceExport(output);
    expect(parsed.sourceText.codeUnits, [0xD800, 0x20, 0x41, 0x20, 0xDFFF]);
    expect(formatWorkspaceExport(parsed), output);
  });

  test('rejects truncated and non-hex unicode escapes', () {
    final valid = formatWorkspaceExport(_draft());
    final documents = <String>[
      valid.replaceFirst('🌏', r'\u'),
      valid.replaceFirst('🌏', r'\uD8'),
      valid.replaceFirst('🌏', r'\uD80Z'),
      valid.replaceFirst('🌏', r'\uZZZZ'),
    ];
    for (final document in documents) {
      expect(
        () => parseWorkspaceExport(document),
        throwsFormatException,
        reason: document,
      );
    }
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

  testWidgets('workspace export writes text edited while the picker is open', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.macOS, () async {
      final writer = _Writer();
      final picker = Completer<FileSaveLocation?>();
      selector.pending = picker;
      await openWorkspace(tester, writer);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      await tester.enterText(field('source-text'), 'Picker 中');
      await tester.pump();
      expect(writer.writes, isEmpty);

      picker.complete(FileSaveLocation('/user/chosen/workspace.txt'));
      await tester.pumpAndSettle();

      expect(writer.writes, [
        (
          '/user/chosen/workspace.txt',
          formatWorkspaceExport(
            TextWorkspaceDraft(
              sourceLanguage: 'ja',
              sourceText: 'Picker 中',
              translations: _draft().translations,
            ),
          ),
        ),
      ]);
      expect(find.text('Workspace exported.'), findsOneWidget);
    });
  });

  testWidgets('workspace export grown past the cap while the picker is pending '
      'reports a non-restorable notice', (tester) async {
    await withPlatform(TargetPlatform.macOS, () async {
      final writer = _Writer();
      final picker = Completer<FileSaveLocation?>();
      selector.pending = picker;
      await openWorkspace(tester, writer);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      tester.widget<TextField>(field('source-text')).controller!.text =
          '\\' * (maxTextImportBytes ~/ 2 + 1);
      await tester.pump();

      picker.complete(FileSaveLocation('/user/chosen/workspace.txt'));
      await tester.pumpAndSettle();

      expect(writer.writes, hasLength(1));
      expect(
        utf8.encode(writer.writes.single.$2).length,
        greaterThan(maxTextImportBytes),
      );
      expect(
        find.text('Saved as text, but too large for Kotoha to restore.'),
        findsOneWidget,
      );
      expect(find.text('Workspace exported.'), findsNothing);
    });
  });

  testWidgets(
    'translation export writes the text edited while the picker is open',
    (tester) async {
      await withPlatform(TargetPlatform.macOS, () async {
        final writer = _Writer();
        final picker = Completer<FileSaveLocation?>();
        selector.pending = picker;
        await openWorkspace(tester, writer);

        final exportButton = field('export-translation-1');
        await tester.ensureVisible(exportButton);
        await tester.tap(exportButton);
        await tester.pump();

        await tester.enterText(field('translation-text-1'), 'Edited, 🌏');
        await tester.pump();
        expect(writer.writes, isEmpty);

        picker.complete(FileSaveLocation('/user/chosen/translation.txt'));
        await tester.pumpAndSettle();

        expect(writer.writes, [('/user/chosen/translation.txt', 'Edited, 🌏')]);
        expect(find.text('Translation exported.'), findsOneWidget);
      });
    },
  );

  testWidgets(
    'translation cleared while the picker is pending writes nothing',
    (tester) async {
      await withPlatform(TargetPlatform.macOS, () async {
        final writer = _Writer();
        final picker = Completer<FileSaveLocation?>();
        selector.pending = picker;
        await openWorkspace(tester, writer);

        final exportButton = field('export-translation-1');
        await tester.ensureVisible(exportButton);
        await tester.tap(exportButton);
        await tester.pump();

        tester.widget<TextField>(field('translation-text-1')).controller!.text =
            '';
        await tester.pump();

        picker.complete(FileSaveLocation('/user/chosen/translation.txt'));
        await tester.pumpAndSettle();

        expect(writer.writes, isEmpty);
        expect(find.text('Enter a translation to export.'), findsOneWidget);
        expect(find.text('Translation exported.'), findsNothing);
      });
    },
  );

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

  testWidgets('a language-only workspace is exported and round-trips', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await pumpWorkspace(tester, writer);
      await tester.enterText(field('source-language'), 'ja');

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(selector.calls, 1);
      expect(writer.writes, hasLength(1));
      final parsed = parseWorkspaceExport(writer.writes.single.$2);
      expect(parsed.sourceLanguage, 'ja');
      expect(parsed.sourceText, isEmpty);
      expect(parsed.translations, hasLength(1));
      expect(parsed.translations.single.text, isEmpty);
    });
  });

  testWidgets('added blank cards export and round-trip', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await pumpWorkspace(tester, writer);
      final addTranslation = find.text('Add translation');
      await tester.ensureVisible(addTranslation);
      await tester.tap(addTranslation);
      await tester.pumpAndSettle();
      expect(field('translation-text-1'), findsOneWidget);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(selector.calls, 1);
      expect(writer.writes, hasLength(1));
      final parsed = parseWorkspaceExport(writer.writes.single.$2);
      expect(parsed.sourceLanguage, isEmpty);
      expect(parsed.sourceText, isEmpty);
      expect(parsed.translations, hasLength(2));
      expect(parsed.translations.every((t) => t.text.isEmpty), isTrue);
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

  Future<void> fillOversizedWorkspace(
    WidgetTester tester,
    _Writer writer,
  ) async {
    await pumpWorkspace(tester, writer);
    tester.widget<TextField>(field('source-text')).controller!.text =
        '\\' * (maxTextImportBytes ~/ 2 + 1);
  }

  testWidgets('an over-limit export warns before saving and can be canceled', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      await fillOversizedWorkspace(tester, writer);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.text('Save a non-restorable export?'), findsOneWidget);
      expect(find.textContaining('Restore will reject it'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(selector.calls, 0);
      expect(writer.writes, isEmpty);
    });
  });

  testWidgets('an over-limit export can be saved with a distinct notice', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await fillOversizedWorkspace(tester, writer);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(field('workspace-export-too-large-confirm'));
      await tester.pumpAndSettle();

      expect(selector.calls, 1);
      expect(writer.writes, hasLength(1));
      expect(
        writer.writes.single.$2,
        startsWith('Kotoha workspace export v2\n'),
      );
      expect(
        find.text('Saved as text, but too large for Kotoha to restore.'),
        findsOneWidget,
      );
    });
  });

  testWidgets(
    'workspace export shrunk below the cap while the picker is pending '
    'reports a normal notice',
    (tester) async {
      await withPlatform(TargetPlatform.windows, () async {
        final writer = _Writer();
        final picker = Completer<FileSaveLocation?>();
        selector.pending = picker;
        await fillOversizedWorkspace(tester, writer);

        final exportButton = field('export-workspace');
        await tester.ensureVisible(exportButton);
        await tester.tap(exportButton);
        await tester.pumpAndSettle();

        expect(find.text('Save a non-restorable export?'), findsOneWidget);
        await tester.tap(field('workspace-export-too-large-confirm'));
        await tester.pumpAndSettle();

        tester.widget<TextField>(field('source-text')).controller!.text = '原文';
        await tester.pump();

        picker.complete(FileSaveLocation('/user/chosen/workspace.txt'));
        await tester.pumpAndSettle();

        expect(writer.writes, hasLength(1));
        expect(
          utf8.encode(writer.writes.single.$2).length,
          lessThanOrEqualTo(maxTextImportBytes),
        );
        expect(find.text('Workspace exported.'), findsOneWidget);
        expect(
          find.text('Saved as text, but too large for Kotoha to restore.'),
          findsNothing,
        );
      });
    },
  );

  testWidgets('uses the Japanese over-limit export disclosure', (tester) async {
    binding.platformDispatcher.localesTestValue = const [Locale('ja')];
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      selector.result = FileSaveLocation('/user/chosen/workspace.txt');
      await fillOversizedWorkspace(tester, writer);

      final exportButton = field('export-workspace');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pumpAndSettle();

      expect(find.text('復元できないファイルを保存しますか？'), findsOneWidget);
      expect(find.textContaining('復元では読み込めません'), findsOneWidget);
      await tester.tap(field('workspace-export-too-large-confirm'));
      await tester.pumpAndSettle();

      expect(find.text('テキストとして保存しましたが、Kotohaでは復元できません。'), findsOneWidget);
      expect(writer.writes, hasLength(1));
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
