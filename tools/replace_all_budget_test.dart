// Opt-in only: flutter test tools/replace_all_budget_test.dart --dart-define=KOTOHA_REPLACE_ALL_OUTPUT_LIMIT=16
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/editor_config.dart';
import 'package:kotoha/l10n/app_localizations_en.dart';
import 'package:kotoha/main.dart';

const _define = 'KOTOHA_REPLACE_ALL_OUTPUT_LIMIT';
const _budget = 16;

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

// The 9/8-character boundary below is specific to this budget, so a missing
// or different define fails here instead of quietly testing the default run.
Future<TextEditingController> _replaceAll(
  WidgetTester tester,
  String source,
) async {
  final field = find.byKey(const ValueKey('source-text'));
  await tester.enterText(field, source);
  final controller = tester.widget<TextField>(field).controller!;
  await _tapVisible(tester, find.byKey(const ValueKey('find-replace-toggle')));
  await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
  await tester.enterText(find.byKey(const ValueKey('find-query')), 'a');
  await _tapVisible(tester, find.byKey(const ValueKey('find-replacement')));
  await tester.enterText(find.byKey(const ValueKey('find-replacement')), 'aa');
  await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));
  return controller;
}

void main() {
  const requested = int.fromEnvironment(_define);
  if (requested != _budget) {
    throw ArgumentError('Set --dart-define=$_define=$_budget to run this test');
  }
  final strings = AppLocalizationsEn();

  test('build-time define sets the output budget', () {
    expect(replaceAllOutputLimit, requested);
    expect(replaceAllOutputLimit, isNot(8 * 1024 * 1024));
  });

  testWidgets('a growing Replace All over the configured budget is refused', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final controller = await _replaceAll(tester, 'a' * 9);
    expect(controller.text, 'a' * 9);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      strings.findLimitExceeded,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a growing Replace All at the configured budget is applied', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final controller = await _replaceAll(tester, 'a' * 8);
    expect(controller.text, 'a' * 16);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      strings.findReplacedCount(8),
    );
    expect(tester.takeException(), isNull);
  });
}
