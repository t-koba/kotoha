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

  testWidgets('malformed UTF-8 bytes are rejected without changing drafts', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      picker.pick = () async =>
          _BytesFile(Uint8List.fromList([0x4b, 0xff, 0x0a]));
      await open(tester);

      await restore(tester);

      expect(
        find.text('This file is not a Kotoha v2 workspace export.'),
        findsOneWidget,
      );
      expect(textOf(tester, 'source-language'), '');
      expect(textOf(tester, 'source-text'), '');
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

  testWidgets('a language-only edit after picking aborts the restore', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await open(tester);
      await tester.enterText(field('target-language-0'), 'en');
      picker.pick = () async {
        tester.widget<TextField>(field('target-language-0')).controller!.text =
            'fr';
        return _File(formatWorkspaceExport(restoredDraft()));
      };

      await restore(tester);

      expect(
        find.text(
          'Source text changed during import. Your edits were kept; import again to retry.',
        ),
        findsOneWidget,
      );
      expect(textOf(tester, 'target-language-0'), 'fr');
      expect(textOf(tester, 'source-text'), '');
      expect(find.text('Workspace restored.'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

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
}
