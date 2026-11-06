import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_document_exporter.dart';

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

  Future<void> openWorkspace(
    WidgetTester tester,
    _Writer writer, {
    String source = '原文',
    String firstTranslation = 'Bonjour',
    String secondTranslation = 'Hello, 🌏',
  }) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(KotohaApp(exportText: writer.write));
    await tester.enterText(field('source-text'), source);
    await tester.enterText(field('translation-text-0'), firstTranslation);
    final addTranslation = find.text('Add translation');
    await tester.ensureVisible(addTranslation);
    await tester.tap(addTranslation);
    await tester.pumpAndSettle();
    await tester.enterText(field('target-language-1'), 'fr');
    await tester.enterText(field('translation-text-1'), secondTranslation);
  }

  test('writes the selected text as exact UTF-8 bytes', () async {
    final directory = Directory.systemTemp.createTempSync('kotoha-export');
    addTearDown(() => directory.deleteSync(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}translation.txt';

    await exportTextDocument(path, 'Hello, 🌏');

    expect(File(path).readAsBytesSync(), utf8.encode('Hello, 🌏'));
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('$platform exports only the chosen translation', (
      tester,
    ) async {
      await withPlatform(platform, () async {
        final writer = _Writer();
        selector.result = FileSaveLocation('/user/chosen/translation.txt');
        await openWorkspace(tester, writer);
        final exportButton = field('export-translation-1');
        await tester.ensureVisible(exportButton);
        expect(
          tester.widget<IconButton>(exportButton).tooltip,
          'Export translation 2',
        );

        await tester.tap(exportButton);
        await tester.pump();

        expect(writer.writes, [('/user/chosen/translation.txt', 'Hello, 🌏')]);
        expect(selector.calls, 1);
        expect(selector.acceptedTypeGroups, hasLength(1));
        expect(selector.acceptedTypeGroups!.single.extensions, ['txt']);
        expect(selector.acceptedTypeGroups!.single.uniformTypeIdentifiers, [
          'public.utf8-plain-text',
        ]);
        expect(selector.options!.suggestedName, 'translation.txt');
        expect(selector.options!.confirmButtonText, 'Export');
        expect(find.text('Translation exported.'), findsOneWidget);
        expect(
          tester.widget<TextField>(field('source-text')).controller!.text,
          '原文',
        );
        expect(
          tester
              .widget<TextField>(field('translation-text-0'))
              .controller!
              .text,
          'Bonjour',
        );
        expect(
          tester
              .widget<TextField>(field('translation-text-1'))
              .controller!
              .text,
          'Hello, 🌏',
        );
      });
    });
  }

  testWidgets('cancelling export leaves all drafts unchanged', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      await openWorkspace(tester, writer);
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(selector.calls, 1);
      expect(writer.writes, isEmpty);
      expect(find.text('Translation exported.'), findsNothing);
      expect(find.text('Could not export the translation.'), findsNothing);
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

  testWidgets('reports a file write failure without changing the draft', (
    tester,
  ) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer()..failure = const FileSystemException('denied');
      selector.result = FileSaveLocation('/user/chosen/translation.txt');
      await openWorkspace(tester, writer);
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(find.text('Could not export the translation.'), findsOneWidget);
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

  testWidgets('an empty translation is not written', (tester) async {
    await withPlatform(TargetPlatform.windows, () async {
      final writer = _Writer();
      await openWorkspace(tester, writer, secondTranslation: '');
      final exportButton = field('export-translation-1');
      await tester.ensureVisible(exportButton);
      await tester.tap(exportButton);
      await tester.pump();

      expect(find.text('Enter a translation to export.'), findsOneWidget);
      expect(selector.calls, 0);
      expect(writer.writes, isEmpty);
    });
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    testWidgets('$platform has no desktop export action', (tester) async {
      await withPlatform(platform, () async {
        final writer = _Writer();
        await tester.pumpWidget(KotohaApp(exportText: writer.write));

        expect(field('export-translation-0'), findsNothing);
        expect(find.textContaining('Export writes only'), findsNothing);
        expect(writer.writes, isEmpty);
      });
    });
  }
}
