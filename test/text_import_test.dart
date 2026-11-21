import 'dart:async';
import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_document_picker.dart';

class _Picker extends FileSelectorPlatform {
  Future<XFile?> Function() pick = () async => null;
  int calls = 0;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) {
    calls++;
    expect(acceptedTypeGroups!.single.extensions, ['txt', 'md', 'markdown']);
    expect(acceptedTypeGroups.single.uniformTypeIdentifiers, [
      'public.utf8-plain-text',
      'net.daringfireball.markdown',
    ]);
    expect(initialDirectory, isNull);
    return pick();
  }
}

class _File extends XFile {
  _File(String name, this.byteLength, this.read) : super('/not-stored/$name');

  final int byteLength;
  final Future<Uint8List> Function() read;
  int reads = 0;

  @override
  Future<int> length() async => byteLength;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield await readAsBytes();
  }

  @override
  Future<Uint8List> readAsBytes() {
    reads++;
    return read();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const genericNotice = 'Could not import this document.';
  const tooLargeNotice =
      'This file is too large to import. Choose a smaller UTF-8 text document.';
  late FileSelectorPlatform original;
  late _Picker picker;

  setUp(() {
    original = FileSelectorPlatform.instance;
    picker = _Picker();
    FileSelectorPlatform.instance = picker;
    binding.platformDispatcher.localesTestValue = [const Locale('en')];
  });
  tearDown(() {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  void importTest(String description, WidgetTesterCallback body) {
    testWidgets(description, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Finder field(String key) => find.byKey(ValueKey(key));
  TextEditingController controller(WidgetTester tester, String key) =>
      tester.widget<TextField>(field(key)).controller!;
  Future<void> open(WidgetTester tester, {String source = ''}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KotohaApp());
    await tester.enterText(field('source-text'), source);
  }

  Future<void> import(WidgetTester tester) async {
    await tester.tap(field('import-source'));
    await tester.pumpAndSettle();
  }

  _File textFile(String name, String text) {
    final bytes = utf8.encode(text);
    return _File(name, bytes.length, () async => bytes);
  }

  importTest('a successful retry clears the previous failure notice', (
    tester,
  ) async {
    await open(tester);
    picker.pick = () async => _File(
      'bad.txt',
      4,
      () async => Uint8List.fromList([255, 254, 253, 252]),
    );
    await import(tester);
    expect(find.textContaining(genericNotice), findsOneWidget);

    picker.pick = () async => textFile('good.txt', 'new source');
    await import(tester);

    expect(controller(tester, 'source-text').text, 'new source');
    expect(find.textContaining(genericNotice), findsNothing);
  });

  importTest('a retry after the notice timed out still imports', (
    tester,
  ) async {
    await open(tester);
    picker.pick = () async => _File(
      'bad.txt',
      4,
      () async => Uint8List.fromList([255, 254, 253, 252]),
    );
    await import(tester);
    expect(find.textContaining(genericNotice), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.textContaining(genericNotice), findsNothing);

    picker.pick = () async => textFile('good.txt', 'after timeout');
    await import(tester);
    expect(controller(tester, 'source-text').text, 'after timeout');
    expect(picker.calls, 2);
  });

  importTest('a retry leaves an unrelated notice visible', (tester) async {
    await open(tester);
    picker.pick = () async => _File(
      'bad.txt',
      4,
      () async => Uint8List.fromList([255, 254, 253, 252]),
    );
    await import(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    const foreignNotice = 'Enter a translation to copy.';
    await tester.tap(field('copy-translation-0'));
    await tester.pumpAndSettle();
    expect(find.text(foreignNotice), findsOneWidget);

    picker.pick = () async => textFile('good.txt', 'alongside notice');
    await import(tester);

    expect(controller(tester, 'source-text').text, 'alongside notice');
    expect(find.text(foreignNotice), findsOneWidget);
  });

  importTest('a failure queued behind a visible notice is never closed', (
    tester,
  ) async {
    await open(tester);
    const foreignNotice = 'Enter a translation to copy.';
    await tester.tap(field('copy-translation-0'));
    await tester.pump();
    expect(find.text(foreignNotice), findsOneWidget);

    picker.pick = () async => _File(
      'bad.txt',
      4,
      () async => Uint8List.fromList([255, 254, 253, 252]),
    );
    await import(tester);
    expect(find.text(foreignNotice), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(genericNotice),
      ),
      findsNothing,
    );
    final semantics = tester.ensureSemantics();
    final noticeSemantics = tester
        .getSemantics(field('source-import-notice'))
        .getSemanticsData();
    expect(noticeSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(noticeSemantics.label, contains(genericNotice));
    semantics.dispose();

    picker.pick = () async => textFile('good.txt', 'over queued failure');
    await import(tester);

    expect(controller(tester, 'source-text').text, 'over queued failure');
    expect(find.text(foreignNotice), findsOneWidget);
    expect(field('source-import-notice'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.textContaining(genericNotice),
      ),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text(foreignNotice), findsNothing);
    expect(find.textContaining(genericNotice), findsNothing);
  });

  importTest('cancellation keeps source without a replacement dialog', (
    tester,
  ) async {
    await open(tester, source: 'keep');
    await import(tester);
    expect(controller(tester, 'source-text').text, 'keep');
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(picker.calls, 1);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    importTest(
      '$platform imports multilingual BOM text, preserves all fields',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        picker.pick = () async =>
            textFile('sample.MaRkDoWn', '\uFEFF# 日本語\nمرحبا 🌏');
        await open(tester);
        await tester.enterText(field('source-language'), 'ja');
        await tester.enterText(field('target-language-0'), 'en');
        await tester.enterText(field('translation-text-0'), 'Manual one');
        await tester.tap(find.text('Add translation'));
        await tester.pumpAndSettle();
        await tester.enterText(field('target-language-1'), 'fr');
        await tester.enterText(field('translation-text-1'), 'Manual two');
        await import(tester);
        expect(controller(tester, 'source-text').text, '# 日本語\nمرحبا 🌏');
        expect(controller(tester, 'source-language').text, 'ja');
        expect(controller(tester, 'target-language-0').text, 'en');
        expect(controller(tester, 'translation-text-0').text, 'Manual one');
        expect(controller(tester, 'target-language-1').text, 'fr');
        expect(controller(tester, 'translation-text-1').text, 'Manual two');
        expect(find.byType(AlertDialog), findsNothing);
        // Existing manual editing remains available after importing.
        await tester.enterText(field('source-text'), 'edited');
        expect(controller(tester, 'source-text').text, 'edited');
      },
    );
  }

  for (final failure in [
    'extension',
    'UTF-8',
    'read',
    'picker',
    'size',
    'grew',
  ]) {
    importTest(
      '$failure failure reports the right notice and preserves source',
      (tester) async {
        final sizeFailure = failure == 'size' || failure == 'grew';
        final file = _File(
          failure == 'extension' ? 'private.pdf' : 'private.txt',
          failure == 'size' ? maxTextImportBytes + 1 : 2,
          () async {
            if (failure == 'read') throw Exception('/private/path');
            if (failure == 'size' || failure == 'grew') {
              return Uint8List(maxTextImportBytes + 1);
            }
            return Uint8List.fromList([0xc3, 0x28]);
          },
        );
        picker.pick = () async {
          if (failure == 'picker') {
            throw PlatformException(code: 'failure', message: '/private/path');
          }
          return file;
        };
        await open(tester, source: 'keep');
        await import(tester);
        expect(controller(tester, 'source-text').text, 'keep');
        expect(
          find.textContaining(sizeFailure ? tooLargeNotice : genericNotice),
          findsOneWidget,
        );
        expect(
          find.textContaining(sizeFailure ? genericNotice : tooLargeNotice),
          findsNothing,
        );
        expect(find.textContaining('private'), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          file.reads,
          ['extension', 'picker', 'size'].contains(failure) ? 0 : 1,
        );
      },
    );
  }

  importTest('replacement requires consent; decline leaves source intact', (
    tester,
  ) async {
    picker.pick = () async => textFile('sample.md', 'new text');
    await open(tester, source: 'keep');
    await import(tester);
    expect(controller(tester, 'source-text').text, 'keep');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller(tester, 'source-text').text, 'keep');
    await import(tester);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(controller(tester, 'source-text').text, 'new text');
  });

  for (final phase in ['picker', 'read', 'confirmation']) {
    importTest('source edit during $phase is never replaced', (tester) async {
      final picked = Completer<XFile?>();
      final bytes = Completer<Uint8List>();
      picker.pick = phase == 'picker'
          ? () => picked.future
          : () async =>
                _File('sample.txt', 'imported'.length, () => bytes.future);
      await open(tester, source: phase == 'confirmation' ? 'original' : '');
      await import(tester);
      expect(
        tester.widget<OutlinedButton>(field('import-source')).onPressed,
        isNull,
      );
      if (phase == 'confirmation') {
        bytes.complete(Uint8List.fromList(utf8.encode('imported')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
      }
      // Simulate a source edit even while a native/modal picker has focus.
      controller(tester, 'source-text').text = 'new edit';
      if (phase == 'picker') {
        // A later undo must not make an outstanding import safe again.
        controller(tester, 'source-text').text = '';
        picked.complete(textFile('sample.txt', 'imported'));
      } else if (phase == 'read') {
        bytes.complete(Uint8List.fromList(utf8.encode('imported')));
      } else {
        await tester.tap(find.text('Replace'));
      }
      await tester.pumpAndSettle();
      expect(
        controller(tester, 'source-text').text,
        phase == 'picker' ? '' : 'new edit',
      );
      expect(
        find.textContaining('Source text changed during import.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Workspace changed during restore. Your edits were kept; choose Restore workspace again to retry.',
        ),
        findsNothing,
      );
    });
  }

  importTest('Japanese import controls and errors are localized', (
    tester,
  ) async {
    binding.platformDispatcher.localesTestValue = [const Locale('ja')];
    picker.pick = () async => textFile('unsupported.pdf', 'ignored');
    await open(tester);
    expect(find.text('テキスト・Markdownを読み込む'), findsOneWidget);
    await import(tester);
    expect(find.textContaining('読み込めませんでした。'), findsOneWidget);
  });

  importTest('import is absent on Linux', (tester) async {
    await open(tester);
    for (final platform in [TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      await tester.pumpWidget(KotohaApp(key: ValueKey(platform)));
      await tester.pumpAndSettle();
      expect(field('import-source'), findsNothing);
    }
    expect(picker.calls, 0);
  });
}
