import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/l10n/app_localizations_en.dart';
import 'package:kotoha/main.dart';

class _Selector extends FileSelectorPlatform {
  @override
  Future<FileSaveLocation?> getSaveLocation({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? suggestedName,
    SaveDialogOptions options = const SaveDialogOptions(),
  }) async => FileSaveLocation('/user/chosen/translation.txt');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late FileSelectorPlatform original;

  setUp(() {
    original = FileSelectorPlatform.instance;
    FileSelectorPlatform.instance = _Selector();
    binding.platformDispatcher.localesTestValue = const [Locale('en')];
  });

  tearDown(() {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    binding.platformDispatcher.clearLocalesTestValue();
  });

  Future<void> enterMarkerContent(WidgetTester tester, String marker) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      KotohaApp(exportText: (path, text) async => throw Exception(marker)),
    );
    await tester.enterText(find.byKey(const ValueKey('source-text')), marker);
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-0')),
      marker,
    );
  }

  Future<void> withWindows(Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  List<String> snackTexts(WidgetTester tester) => tester
      .widgetList<Text>(
        find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)),
      )
      .map((widget) => widget.data ?? '')
      .toList();

  testWidgets(
    'translation export failure notice does not echo marker content',
    (tester) async {
      final marker = 'PRIVATE-MARKER-${'7' * 24}';
      await withWindows(() async {
        await enterMarkerContent(tester, marker);
        final button = find.byKey(const ValueKey('export-translation-0'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();

        final texts = snackTexts(tester);
        expect(texts, contains(AppLocalizationsEn().exportFailureNotice));
        expect(texts.join(' '), isNot(contains(marker)));
      });
    },
  );

  testWidgets('workspace export failure notice does not echo marker content', (
    tester,
  ) async {
    final marker = 'PRIVATE-MARKER-${'9' * 24}';
    await withWindows(() async {
      await enterMarkerContent(tester, marker);
      final button = find.byKey(const ValueKey('export-workspace'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();

      final texts = snackTexts(tester);
      expect(
        texts,
        contains(AppLocalizationsEn().workspaceExportFailureNotice),
      );
      expect(texts.join(' '), isNot(contains(marker)));
    });
  });
}
