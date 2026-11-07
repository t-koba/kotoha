// Opt-in only: flutter test tools/profile_text_import_test.dart --dart-define=...
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

class _SelectedFile extends FileSelectorPlatform {
  _SelectedFile(this.file);
  final XFile file;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async => file;
}

void main() {
  const requested = int.fromEnvironment('PROFILE_BYTES');
  const stage = String.fromEnvironment('PROFILE_STAGE', defaultValue: 'decode');
  final chunk = utf8.encode('${'a' * 1003}日本語 مرحبا\n');
  const maximumProfileBytes = 16 * 1024 * 1024;
  const maximumEditorBytes = 2 * 1024 * 1024;
  final maximumBytes = stage == 'editor'
      ? maximumEditorBytes
      : maximumProfileBytes;
  if (requested < chunk.length ||
      requested > maximumBytes ||
      !['decode', 'editor'].contains(stage)) {
    throw ArgumentError(
      'Set PROFILE_BYTES between ${chunk.length} and $maximumBytes for stage $stage',
    );
  }
  if (requested % chunk.length != 0) {
    throw ArgumentError(
      'PROFILE_BYTES must be divisible by the ${chunk.length}-byte UTF-8 fixture chunk',
    );
  }
  final length = requested;
  testWidgets('synthetic import memory profile', (tester) async {
    try {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('kotoha-profile-'),
      ))!;
      addTearDown(() => directory.delete(recursive: true));
      final fixture = File('${directory.path}/synthetic.txt');
      // Fixture creation is outside the measured stage, in bounded chunks.
      await tester.runAsync(() async {
        final output = fixture.openWrite();
        var buffered = 0;
        try {
          for (var n = 0; n < length; n += chunk.length) {
            output.add(chunk);
            buffered += chunk.length;
            if (buffered >= 1024 * 1024) {
              await output.flush();
              buffered = 0;
            }
          }
        } finally {
          await output.close();
        }
      });
      final file = XFile(fixture.path);
      if (stage == 'editor') {
        // Widget tests otherwise default to Android even on a desktop host.
        debugDefaultTargetPlatformOverride = Platform.isWindows
            ? TargetPlatform.windows
            : TargetPlatform.macOS;
        final original = FileSelectorPlatform.instance;
        FileSelectorPlatform.instance = _SelectedFile(file);
        addTearDown(() => FileSelectorPlatform.instance = original);
        await tester.binding.setSurfaceSize(const Size(1200, 2200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(const KotohaApp());
      }
      final beforeRss = ProcessInfo.currentRss;
      final beforePeak = ProcessInfo.maxRss;
      final watch = Stopwatch()..start();
      var units = 0;
      if (stage == 'decode') {
        final text = await tester.runAsync(
          () async =>
              utf8.decode(await file.readAsBytes(), allowMalformed: false),
        );
        units = text!.length;
      } else {
        // Only selection is synthetic: actual disk XFile read, app decoder,
        // controller assignment and TextField layout run unchanged.
        final source = tester.widget<TextField>(
          find.byKey(const ValueKey('source-text')),
        );
        await tester.runAsync(() async {
          // Create the completion in the real zone too; a fake-zone future would
          // strand the filesystem completion until another test-clock pump.
          final imported = Completer<void>();
          void changed() {
            if (source.controller!.text.isNotEmpty && !imported.isCompleted) {
              imported.complete();
            }
          }

          source.controller!.addListener(changed);
          try {
            tester
                .widget<OutlinedButton>(
                  find.byKey(const ValueKey('import-source')),
                )
                .onPressed!();
            await imported.future; // External watchdog bounds failure/hangs.
          } finally {
            source.controller!.removeListener(changed);
          }
        });
        await tester.pumpAndSettle();
        units = source.controller!.text.length;
      }
      expect(units, length ~/ chunk.length * utf8.decode(chunk).length);
      // Process-wide peaks include runtime startup and fixture creation. A zero
      // peak delta does not mean zero allocation. Never subtract stages as copies.
      // ignore: avoid_print
      print(
        jsonEncode({
          'profile': 'dart-$stage',
          'os': Platform.operatingSystem,
          'runtime': Platform.version,
          'bytes': length,
          'codeUnits': units,
          'elapsedMicros': watch.elapsedMicroseconds,
          'rssBefore': beforeRss,
          'rssAfter': ProcessInfo.currentRss,
          'peakBefore': beforePeak,
          'peakAfter': ProcessInfo.maxRss,
        }),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
