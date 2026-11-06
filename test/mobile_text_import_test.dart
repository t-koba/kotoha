import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.kotoha/text_import');
  late Future<Object?> Function() reply;
  var calls = 0;
  Map<String, Object> document(
    String text, {
    String name = 'sample.MaRkDoWn',
  }) => {'name': name, 'bytes': Uint8List.fromList(utf8.encode(text))};
  Finder field(String key) => find.byKey(ValueKey(key));
  TextEditingController controller(WidgetTester tester, String key) =>
      tester.widget<TextField>(field(key)).controller!;
  Future<void> open(WidgetTester tester, {String source = ''}) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KotohaApp());
    await tester.enterText(field('source-text'), source);
    await tester.enterText(field('source-language'), 'ja');
    await tester.enterText(field('target-language-0'), 'en');
    await tester.enterText(field('translation-text-0'), 'manual');
  }

  void preserved(WidgetTester tester, String source) {
    expect(controller(tester, 'source-text').text, source);
    expect(controller(tester, 'source-language').text, 'ja');
    expect(controller(tester, 'target-language-0').text, 'en');
    expect(controller(tester, 'translation-text-0').text, 'manual');
  }

  Future<void> import(WidgetTester tester) async {
    await tester.tap(field('import-source'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    calls = 0;
    reply = () async => null;
    binding.platformDispatcher.localesTestValue = [const Locale('en')];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) {
      expect(call.method, 'open');
      expect(call.arguments, isNull);
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

    mobileTest(
      'channel cancellation then BOM import; lifecycle preserves drafts',
      (tester) async {
        await open(tester);
        await import(tester);
        preserved(tester, '');
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        reply = () async => document('\uFEFF# 日本語\nمرحبا 🌏');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await import(tester);
        preserved(tester, '# 日本語\nمرحبا 🌏');
        expect(calls, 2);
      },
    );

    for (final failure in [
      'name',
      'extension',
      'bytes',
      'shape',
      'UTF-8',
      'native',
    ]) {
      mobileTest('$failure fails closed without leaking details', (
        tester,
      ) async {
        reply = () async => switch (failure) {
          'name' => {'bytes': Uint8List(0)},
          'extension' => document('no', name: 'private.pdf'),
          'bytes' => {
            'name': 'sample.txt',
            'bytes': [65],
          },
          'shape' => 'private/path',
          'UTF-8' => {
            'name': 'sample.txt',
            'bytes': Uint8List.fromList([0xc3, 0x28]),
          },
          _ => throw PlatformException(
            code: 'read_failed',
            message: 'private/path',
          ),
        };
        await open(tester, source: 'keep');
        await import(tester);
        preserved(tester, 'keep');
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.textContaining('Could not import this document.'),
          findsOneWidget,
        );
        expect(find.textContaining('private'), findsNothing);
      });
    }

    mobileTest('consent and edits during native read or confirmation', (
      tester,
    ) async {
      await open(tester, source: 'keep');
      reply = () async => document('imported');
      await import(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      preserved(tester, 'keep');
      await import(tester);
      controller(tester, 'source-text').text = 'new edit';
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      preserved(tester, 'new edit');
      final selected = Completer<Object?>();
      reply = () => selected.future;
      await import(tester);
      expect(
        tester.widget<OutlinedButton>(field('import-source')).onPressed,
        isNull,
      );
      controller(tester, 'source-text').text = 'during read';
      controller(tester, 'source-text').text =
          'new edit'; // Undo still invalidates the request.
      selected.complete(document('ignored'));
      await tester.pumpAndSettle();
      preserved(tester, 'new edit');
      reply = () async => document('accepted');
      await import(tester);
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      preserved(tester, 'accepted');
      await tester.enterText(field('source-text'), 'manual edit');
      preserved(tester, 'manual edit');
    });
  }
}
