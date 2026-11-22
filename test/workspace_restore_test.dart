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

class _Picker extends FileSelectorPlatform {
  Future<XFile?> Function() pick = () async => null;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => pick();
}

class _File extends XFile {
  _File(this.text, {this.failure, String name = 'workspace.txt'})
    : _bytes = utf8.encode(text),
      super('/not-stored/$name');

  final String text;
  final Uint8List _bytes;
  final Object? failure;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    if (failure != null) throw failure!;
    yield _bytes;
  }
}

class _BytesFile extends XFile {
  _BytesFile(this._bytes) : super('/not-stored/workspace.txt');

  final Uint8List _bytes;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield _bytes;
  }
}

class _LargeFile extends XFile {
  _LargeFile() : super('/not-stored/workspace.txt');

  @override
  Future<int> length() async => maxTextImportBytes + 1;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    throw StateError('An oversized document must be rejected before reading.');
  }
}

class _UnsupportedLargeFile extends XFile {
  _UnsupportedLargeFile() : super('/not-stored/workspace.pdf');

  bool lengthCalled = false;
  bool readCalled = false;

  @override
  Future<int> length() async {
    lengthCalled = true;
    return maxTextImportBytes + 1;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    readCalled = true;
    throw StateError(
      'An unsupported document must be rejected before reading.',
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;
  late _Picker picker;

  setUp(() {
    original = FileSelectorPlatform.instance;
    picker = _Picker();
    FileSelectorPlatform.instance = picker;
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
  });

  tearDown(() {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Finder field(String key) => find.byKey(ValueKey(key));

  String textOf(WidgetTester tester, String key) =>
      tester.widget<TextField>(field(key)).controller!.text;

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KotohaApp());
  }

  Future<void> restore(WidgetTester tester) async {
    final button = field('restore-workspace');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  TextWorkspaceDraft restoredDraft() => TextWorkspaceDraft(
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

  TextWorkspaceDraft surrogateDraft() {
    final high = String.fromCharCode(0xD800);
    return TextWorkspaceDraft(
      sourceLanguage: 'x$high-y',
      sourceText: 'first 🌏\nsecond',
      translations: [
        const ManualTranslationDraft(targetLanguage: 'en', text: 'plain'),
        ManualTranslationDraft(targetLanguage: 'fr', text: '$high-tail'),
      ],
    );
  }

  testWidgets('restores every field from a v2 document', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);

      await restore(tester);

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
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('editing a restored language label keeps its line break', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final draft = restoredDraft().copyWith(sourceLanguage: 'A\nB');
      picker.pick = () async => _File(formatWorkspaceExport(draft));
      await open(tester);
      await restore(tester);

      expect(textOf(tester, 'source-language'), 'A\nB');
      final language = field('source-language');
      await tester.ensureVisible(language);
      await tester.enterText(language, 'A\nBC');

      expect(textOf(tester, 'source-language'), 'A\nBC');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('restores a v2 document saved with CRLF line endings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(
        formatWorkspaceExport(restoredDraft()).replaceAll('\n', '\r\n'),
      );
      await open(tester);

      await restore(tester);

      expect(textOf(tester, 'source-language'), 'ja');
      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
      expect(
        textOf(tester, 'translation-text-0'),
        'Translation 2 language: fr\nTranslation text:\nnot a header',
      );
      expect(textOf(tester, 'translation-text-1'), 'bonjour');
      expect(find.text('Workspace restored.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('canceling replacement keeps the current workspace', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);
      await tester.tap(field('restore-workspace-cancel'));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'source-text'), 'keep me');
      expect(find.byKey(const ValueKey('translation-text-1')), findsNothing);
      expect(find.text('Workspace restored.'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('added blank cards get a replace confirmation on restore', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);
      final addTranslation = find.text('Add translation');
      await tester.ensureVisible(addTranslation);
      await tester.tap(addTranslation);
      await tester.pumpAndSettle();
      expect(field('translation-text-1'), findsOneWidget);

      await restore(tester);
      expect(field('restore-workspace-confirm'), findsOneWidget);

      await tester.tap(field('restore-workspace-cancel'));
      await tester.pumpAndSettle();
      expect(field('translation-text-1'), findsOneWidget);
      expect(find.text('Workspace restored.'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('confirming replacement installs the restored fields', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);
      await tester.enterText(field('source-text'), 'old');

      await restore(tester);
      await tester.tap(field('restore-workspace-confirm'));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
      expect(find.text('Workspace restored.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an edit during confirmation aborts replacement', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);
      await tester.enterText(field('source-text'), 'old source');
      await tester.enterText(field('target-language-0'), 'old target');

      await restore(tester);
      tester.widget<TextField>(field('source-text')).controller!.text =
          'edited during confirmation';
      await tester.tap(field('restore-workspace-confirm'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Workspace changed during restore. Your edits were kept; choose Restore workspace again to retry.',
        ),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'edited during confirmation');
      expect(textOf(tester, 'target-language-0'), 'old target');
      expect(find.text('Workspace restored.'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('restoring an empty export clears every stale field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async =>
          _File(formatWorkspaceExport(TextWorkspaceDraft.empty()));
      await open(tester);
      await tester.enterText(field('source-language'), 'ja');
      await tester.enterText(field('source-text'), 'stale source');
      await tester.enterText(field('target-language-0'), 'en');
      await tester.enterText(field('translation-text-0'), 'stale translation');
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
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('restores a v2 document with a UTF-8 BOM', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final bytes = Uint8List.fromList([
        0xef,
        0xbb,
        0xbf,
        ...utf8.encode(formatWorkspaceExport(restoredDraft())),
      ]);
      picker.pick = () async => _BytesFile(bytes);
      await open(tester);

      await restore(tester);

      expect(textOf(tester, 'source-language'), 'ja');
      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
      expect(textOf(tester, 'target-language-1'), 'fr');
      expect(textOf(tester, 'translation-text-1'), 'bonjour');
      expect(find.text('Workspace restored.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('restores a BOM-prefixed CRLF export verbatim', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final crlf = utf8.encode(
        formatWorkspaceExport(restoredDraft()).replaceAll('\n', '\r\n'),
      );
      picker.pick = () async =>
          _BytesFile(Uint8List.fromList([0xef, 0xbb, 0xbf, ...crlf]));
      await open(tester);

      await restore(tester);

      expect(textOf(tester, 'source-language'), 'ja');
      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
      expect(
        textOf(tester, 'translation-text-0'),
        'Translation 2 language: fr\nTranslation text:\nnot a header',
      );
      expect(textOf(tester, 'target-language-1'), 'fr');
      expect(textOf(tester, 'translation-text-1'), 'bonjour');
      expect(find.text('Workspace restored.'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('malformed UTF-8 bytes are rejected without changing drafts', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final valid = formatWorkspaceExport(restoredDraft());
      final at = valid.indexOf('bonjour');
      expect(at, greaterThan(0));
      final invalid = Uint8List.fromList([
        ...utf8.encode(valid.substring(0, at)),
        0xff,
        ...utf8.encode(valid.substring(at + 'bonjour'.length)),
      ]);
      picker.pick = () async => _BytesFile(invalid);
      await open(tester);
      await tester.enterText(field('source-language'), 'current-language');
      await tester.enterText(field('source-text'), 'current source');

      await restore(tester);

      expect(
        find.text('This file is not a Kotoha v2 workspace export.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-language'), 'current-language');
      expect(textOf(tester, 'source-text'), 'current source');
      expect(find.text('Workspace restored.'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an unsupported document is rejected without changing drafts', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File('Kotoha workspace export v1\nwhatever');
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);

      expect(
        find.text('This file is not a Kotoha v2 workspace export.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final edit in {
    'source-language': 'edited-language',
    'source-text': 'edited source',
    'target-language-0': 'edited-target',
    'translation-text-0': 'edited translation',
  }.entries) {
    testWidgets('an edit to ${edit.key} after picking aborts the restore', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await open(tester);
        await tester.enterText(field('source-language'), 'old-language');
        await tester.enterText(field('source-text'), 'old source');
        await tester.enterText(field('target-language-0'), 'old-target');
        await tester.enterText(field('translation-text-0'), 'old translation');
        picker.pick = () async {
          tester.widget<TextField>(field(edit.key)).controller!.text =
              edit.value;
          return _File(formatWorkspaceExport(restoredDraft()));
        };

        await restore(tester);

        expect(
          find.text(
            'Workspace changed during restore. Your edits were kept; choose Restore workspace again to retry.',
          ),
          findsOneWidget,
        );
        expect(textOf(tester, edit.key), edit.value);
        expect(
          textOf(tester, 'source-text'),
          edit.key == 'source-text' ? edit.value : 'old source',
        );
        expect(find.text('Workspace restored.'), findsNothing);
        expect(
          find.byKey(const ValueKey('restore-workspace-confirm')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('picker cancellation keeps the workspace without a notice', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => null;
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);

      expect(textOf(tester, 'source-text'), 'keep me');
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an unsupported file type is rejected with its own notice', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async =>
          _File(formatWorkspaceExport(restoredDraft()), name: 'workspace.pdf');
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);

      expect(
        find.text('Choose a .txt, .md, or .markdown file to restore.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an oversized document is rejected with its own notice', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _LargeFile();
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);

      expect(
        find.text(
          'This file is too large to restore. Choose a smaller workspace export.',
        ),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-text'), 'keep me');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'an unsupported file type is reported before any size preflight',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final file = _UnsupportedLargeFile();
        picker.pick = () async => file;
        await open(tester);
        await tester.enterText(field('source-text'), 'keep me');

        await restore(tester);

        expect(
          find.text('Choose a .txt, .md, or .markdown file to restore.'),
          findsOneWidget,
        );
        expect(textOf(tester, 'source-text'), 'keep me');
        expect(file.lengthCalled, isFalse);
        expect(file.readCalled, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('uses the Japanese unsupported-document notice', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    binding.platformDispatcher.localesTestValue = const [Locale('ja')];
    try {
      picker.pick = () async => _File('wrong header');
      await open(tester);

      await restore(tester);

      expect(find.text('このファイルはKotoha v2の作業エクスポートではありません。'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('uses the Japanese confirmation and success strings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    binding.platformDispatcher.localesTestValue = const [Locale('ja')];
    try {
      picker.pick = () async => _File(formatWorkspaceExport(restoredDraft()));
      await open(tester);
      await tester.enterText(field('source-text'), '残す原文');

      await restore(tester);

      expect(find.text('現在の作業内容を置き換えますか？'), findsOneWidget);
      await tester.tap(field('restore-workspace-confirm'));
      await tester.pumpAndSettle();

      expect(find.text('作業内容を復元しました。'), findsOneWidget);
      expect(textOf(tester, 'source-text'), '第一行\nsecond 🌏');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a read failure is reported without changing drafts', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async =>
          _File('', failure: const FileSystemException('denied'));
      await open(tester);
      await tester.enterText(field('source-text'), 'keep me');

      await restore(tester);

      expect(find.text('Could not restore the workspace.'), findsOneWidget);
      expect(textOf(tester, 'source-text'), 'keep me');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final (locale, title, question, replaceTitle, success) in [
    (
      const Locale('en'),
      'Unpaired characters in export',
      'This export contains unpaired UTF-16 code units. They will be replaced with U+FFFD before editing; the exported file is unchanged. Continue?',
      'Replace the current workspace?',
      'Workspace restored.',
    ),
    (
      const Locale('ja'),
      'エクスポート内の孤立したサロゲート',
      'このエクスポートには対になっていないUTF-16サロゲートが含まれています。編集前にU+FFFDへ置き換えます。エクスポートしたファイルは変更されません。続けますか？',
      '現在の作業内容を置き換えますか？',
      '作業内容を復元しました。',
    ),
  ]) {
    testWidgets(
      'discloses surrogate normalization for $locale before editing',
      (tester) async {
        binding.platformDispatcher.localesTestValue = [locale];
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        try {
          picker.pick = () async =>
              _File(formatWorkspaceExport(surrogateDraft()));
          await open(tester);
          await tester.enterText(field('source-language'), 'keep language');
          await tester.enterText(field('source-text'), 'keep me');

          await restore(tester);

          expect(find.text(title), findsOneWidget);
          expect(find.text(question), findsOneWidget);
          expect(find.text(replaceTitle), findsNothing);
          expect(textOf(tester, 'source-language'), 'keep language');
          expect(textOf(tester, 'source-text'), 'keep me');

          await tester.tap(field('restore-workspace-surrogate-cancel'));
          await tester.pumpAndSettle();

          expect(find.text(title), findsNothing);
          expect(textOf(tester, 'source-language'), 'keep language');
          expect(textOf(tester, 'source-text'), 'keep me');
          expect(find.text(success), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      },
    );
  }

  testWidgets('confirming the disclosure normalizes only editable fields', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async => _File(formatWorkspaceExport(surrogateDraft()));
      await open(tester);
      await tester.enterText(field('source-text'), 'old text');

      await restore(tester);
      expect(find.text('Unpaired characters in export'), findsOneWidget);
      await tester.tap(field('restore-workspace-surrogate-confirm'));
      await tester.pumpAndSettle();

      // The existing replacement consent still precedes any field mutation.
      expect(find.text('Replace the current workspace?'), findsOneWidget);
      expect(textOf(tester, 'source-text'), 'old text');
      await tester.tap(field('restore-workspace-confirm'));
      await tester.pumpAndSettle();

      expect(textOf(tester, 'source-language').codeUnits, [
        0x78,
        0xFFFD,
        0x2D,
        0x79,
      ]);
      expect(textOf(tester, 'source-text'), 'first 🌏\nsecond');
      expect(textOf(tester, 'target-language-0'), 'en');
      expect(textOf(tester, 'target-language-1'), 'fr');
      expect(textOf(tester, 'translation-text-1').codeUnits, [
        0xFFFD,
        0x2D,
        0x74,
        0x61,
        0x69,
        0x6C,
      ]);
      expect(find.text('Workspace restored.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
