import 'dart:async';
import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_find_replace.dart';
import 'package:kotoha/workspace.dart';
import 'package:kotoha/workspace_export.dart';

class _PendingPicker extends FileSelectorPlatform {
  final Completer<XFile?> pending = Completer<XFile?>();

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) => pending.future;
}

class _WorkspaceFile extends XFile {
  _WorkspaceFile(this.text) : super('/not-stored/workspace.txt');

  final String text;

  @override
  Future<int> length() async => utf8.encode(text).length;

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield utf8.encode(text);
  }
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _collectSemanticsLabels(SemanticsNode node, List<String> labels) {
  if (node.label.isNotEmpty) labels.add(node.label);
  node.visitChildren((child) {
    _collectSemanticsLabels(child, labels);
    return true;
  });
}

bool _hasPrimaryFocus(WidgetTester tester, Finder finder) {
  final elements = finder.evaluate();
  final focused = tester.binding.focusManager.primaryFocus?.context;
  if (elements.length != 1 || focused == null) return false;
  final target = elements.single;
  if (focused == target) return true;
  var found = false;
  focused.visitAncestorElements((ancestor) {
    if (ancestor == target) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  test('empty query never changes the value or selects a range', () {
    final controller = TextEditingController(text: 'abcabc');
    final before = controller.value;

    expect(findNext(controller, ''), isFalse);
    expect(replaceSelection(controller, '', 'x'), isFalse);
    expect(replaceAll(controller, '', 'x'), 0);
    expect(controller.value, before);
    expect(controller.selection.isCollapsed, isTrue);
  });

  test('replace requires the selected text to equal the query exactly', () {
    final controller = TextEditingController(text: 'cat dog cat');
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 6);

    expect(replaceSelection(controller, 'dog', 'X'), isFalse);
    expect(controller.text, 'cat dog cat');

    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
    expect(replaceSelection(controller, 'DOG', 'X'), isFalse);
    expect(replaceSelection(controller, 'dog', 'bird'), isTrue);
    expect(controller.text, 'cat bird cat');
    expect(controller.selection.start, 4);
    expect(controller.selection.textInside(controller.text), 'bird');
  });

  test('find starts after the current selection and wraps around', () {
    final controller = TextEditingController(text: 'one two one');
    controller.selection = const TextSelection.collapsed(offset: 0);

    expect(findNext(controller, 'one'), isTrue);
    expect(controller.selection.start, 0);
    expect(findNext(controller, 'one'), isTrue);
    expect(controller.selection.start, 8);
    expect(controller.selection.end, 11);
    expect(controller.selection.textInside(controller.text), 'one');

    expect(findNext(controller, 'one'), isTrue);
    expect(controller.selection.start, 0);
    expect(findNext(controller, 'missing'), isFalse);
    expect(controller.selection.start, 0);
  });

  test('replace all skips overlaps and does not revisit new matches', () {
    final overlapping = TextEditingController(text: 'banana');
    expect(replaceAll(overlapping, 'ana', 'X'), 1);
    expect(overlapping.text, 'bXna');

    final repeated = TextEditingController(text: 'aaaa');
    expect(replaceAll(repeated, 'aa', 'X'), 2);
    expect(repeated.text, 'XX');

    final growing = TextEditingController(text: 'aa');
    expect(replaceAll(growing, 'a', 'aa'), 2);
    expect(growing.text, 'aaaa');

    final absent = TextEditingController(text: 'abc');
    final before = absent.value;
    expect(replaceAll(absent, 'z', 'X'), 0);
    expect(absent.value, before);
  });

  test('replace all keeps the caret on a UTF-16 boundary', () {
    final controller = TextEditingController(text: 'a!');
    controller.selection = const TextSelection.collapsed(offset: 1);

    expect(replaceAll(controller, 'a', '😀'), 1);
    expect(controller.text, '😀!');
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, 2);
    expect(controller.selection.extentOffset, 2);

    final after = TextEditingController(text: '!a');
    after.selection = const TextSelection.collapsed(offset: 2);
    expect(replaceAll(after, 'a', '😀'), 1);
    expect(after.selection.baseOffset, 3);

    final before = TextEditingController(text: 'a!');
    before.selection = const TextSelection.collapsed(offset: 0);
    expect(replaceAll(before, 'a', '😀'), 1);
    expect(before.selection.baseOffset, 0);
  });

  test('replace all enforces the output budget before changing the value', () {
    final within = TextEditingController(text: 'aaaa');
    expect(replaceAll(within, 'a', 'aa', maxOutputLength: 8), 4);
    expect(within.text, 'aaaaaaaa');

    final controller = TextEditingController();
    controller.value = TextEditingValue(
      text: 'aaaa',
      selection: const TextSelection(baseOffset: 1, extentOffset: 3),
      composing: const TextRange(start: 0, end: 1),
    );
    final before = controller.value;
    expect(replaceAll(controller, 'a', 'aa', maxOutputLength: 7), -1);
    expect(controller.value, before);
    expect(controller.text, 'aaaa');
    expect(controller.selection, before.selection);
    expect(controller.value.composing, before.composing);
  });

  test('a shrinking replacement works above the output budget', () {
    final controller = TextEditingController(text: 'a' * 20);
    expect(replaceAll(controller, 'aa', 'b', maxOutputLength: 8), 10);
    expect(controller.text, 'b' * 10);
  });

  test('replace all refuses a runaway expansion promptly', () {
    final controller = TextEditingController(text: 'x' * 65536);
    final before = controller.value;
    final stopwatch = Stopwatch()..start();
    expect(replaceAll(controller, 'x', 'y' * 65536), -1);
    stopwatch.stop();
    expect(controller.value, before);
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });

  testWidgets('replace all over the editor limit shows a localized refusal', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'x' * 129);
    final controller = tester.widget<TextField>(source).controller!;
    final before = controller.value;
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'x');
    final replacement = find.byKey(const ValueKey('find-replacement'));
    tester.widget<TextField>(replacement).controller!.text = 'y' * 65536;
    await tester.pumpAndSettle();

    await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      'The replacement would exceed the editor limit. No text was changed.',
    );
    expect(controller.value, before);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the keyboard shortcut opens the localized panel', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('ja')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());
    expect(find.byKey(const ValueKey('find-replace-panel')), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('source-text')), 'abc');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);
    expect(find.text('検索語'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finds and replaces in the chosen translation only', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    final translation = find.byKey(const ValueKey('translation-text-0'));
    await tester.enterText(source, 'source keep');
    await tester.dragUntilVisible(
      translation,
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.enterText(translation, 'alpha beta alpha');
    final sourceController = tester.widget<TextField>(source).controller!;
    final translationController = tester
        .widget<TextField>(translation)
        .controller!;

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('find-next')))
          .onPressed,
      isNull,
      reason: 'actions are disabled until a query exists',
    );

    await _tapVisible(tester, find.byKey(const ValueKey('find-target')));
    await tester.tap(find.text('Translation 1'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'beta');
    await _tapVisible(tester, find.byKey(const ValueKey('find-replacement')));
    await tester.enterText(find.byKey(const ValueKey('find-replacement')), 'B');

    await _tapVisible(tester, find.byKey(const ValueKey('find-next')));
    expect(
      translationController.selection.textInside(translationController.text),
      'beta',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('replace-selection')));
    expect(translationController.text, 'alpha B alpha');
    expect(
      translationController.selection.textInside(translationController.text),
      'B',
    );
    expect(sourceController.text, 'source keep');

    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'alpha');
    await _tapVisible(tester, find.byKey(const ValueKey('find-replacement')));
    await tester.enterText(find.byKey(const ValueKey('find-replacement')), 'A');
    await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));
    expect(translationController.text, 'A B A');
    expect(sourceController.text, 'source keep');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      'Replaced 2 matches.',
    );

    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'missing');
    await _tapVisible(tester, find.byKey(const ValueKey('find-next')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      'No match found.',
    );
    expect(translationController.text, 'A B A');

    final queryController = tester
        .widget<TextField>(find.byKey(const ValueKey('find-query')))
        .controller!;
    queryController.selection = const TextSelection.collapsed(offset: 0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('find-status')),
      findsOneWidget,
      reason: 'moving the caret does not edit the query',
    );

    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'A');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-status')), findsNothing);

    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'missing');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('find-status')),
      findsNothing,
      reason: 'returning to an earlier query must not revive old feedback',
    );

    await _tapVisible(tester, find.byKey(const ValueKey('find-next')));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('find-status'))).data,
      'No match found.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the selected field when an earlier card is removed', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    for (var added = 0; added < 2; added++) {
      await tester.dragUntilVisible(
        find.text('Add translation'),
        find.byType(Scrollable).first,
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add translation'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-1')),
      'match',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-2')),
      'match other',
    );
    final selectedController = tester
        .widget<TextField>(find.byKey(const ValueKey('translation-text-1')))
        .controller!;
    final otherController = tester
        .widget<TextField>(find.byKey(const ValueKey('translation-text-2')))
        .controller!;

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('find-replace-toggle')),
      find.byType(Scrollable).first,
      const Offset(0, 400),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('find-target')));
    await tester.tap(find.text('Translation 2'));
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'match');
    await _tapVisible(tester, find.byKey(const ValueKey('find-replacement')));
    await tester.enterText(
      find.byKey(const ValueKey('find-replacement')),
      'NEW',
    );

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('remove-translation-0')),
    );
    await tester.pumpAndSettle();

    expect(selectedController.text, 'match');
    expect(otherController.text, 'match other');

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('replace-all')),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));
    expect(selectedController.text, 'NEW');
    expect(otherController.text, 'match other');

    await tester.dragUntilVisible(
      find.byKey(const ValueKey('remove-translation-0')),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('remove-translation-0')),
    );
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('remove-translation-confirm')),
    );
    await tester.pumpAndSettle();

    expect(otherController.text, 'match other');
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('replace-all')))
          .onPressed,
      isNull,
      reason: 'a removed selected field requires a deliberate new selection',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tab reaches the toggle and Space/Enter opens the panel', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final toggle = find.byKey(const ValueKey('find-replace-toggle'));
    final reviewToggle = find.byKey(
      const ValueKey('document-outline-review-only'),
    );
    final panel = find.byKey(const ValueKey('find-replace-panel'));
    expect(panel, findsNothing);

    var reachedNearbyControl = false;
    for (var tab = 0; tab < 40 && !reachedNearbyControl; tab++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      reachedNearbyControl = _hasPrimaryFocus(tester, reviewToggle);
    }
    expect(reachedNearbyControl, isTrue, reason: 'Tab reaches the outline');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(
      _hasPrimaryFocus(tester, toggle),
      isTrue,
      reason: 'Tab from the outline reaches the find and replace toggle',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(_hasPrimaryFocus(tester, toggle), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the query field search action selects the next match', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'one two one');
    final controller = tester.widget<TextField>(source).controller!;

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'one');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, 3);
    expect(controller.selection.textInside(controller.text), 'one');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter in the query field still finds the next match', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'one two one');
    final controller = tester.widget<TextField>(source).controller!;

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'one');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(controller.selection.start, 0);
    expect(controller.selection.end, 3);
  });

  testWidgets('Enter during IME composition does not search', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'cat dog cat');
    final sourceController = tester.widget<TextField>(source).controller!;
    sourceController.selection = const TextSelection.collapsed(offset: 7);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'dog');
    final queryController = tester.widget<TextField>(query).controller!;
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: 'dog',
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 0, end: 3),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(queryController.value.composing.isValid, isTrue);
    expect(sourceController.selection.baseOffset, 7);
    expect(sourceController.selection.extentOffset, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('submit action during IME composition does not search', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'cat dog cat');
    final sourceController = tester.widget<TextField>(source).controller!;
    sourceController.selection = const TextSelection.collapsed(offset: 7);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'dog');
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: 'dog',
        selection: const TextSelection.collapsed(offset: 3),
        composing: const TextRange(start: 0, end: 3),
      ),
    );
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(sourceController.selection.baseOffset, 7);
    expect(sourceController.selection.extentOffset, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replace all preserves pasted line breaks', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'foobar\nfoo\nbar');
    final sourceController = tester.widget<TextField>(source).controller!;

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('find-query')),
      'foo\nbar',
    );
    await tester.enterText(
      find.byKey(const ValueKey('find-replacement')),
      'x\ny',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));

    expect(sourceController.text, 'foobar\nx\ny');
  });

  testWidgets('find fields follow their content direction and IME setting', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    final replacement = find.byKey(const ValueKey('find-replacement'));

    expect(tester.widget<TextField>(query).textDirection, TextDirection.ltr);
    expect(
      tester.widget<TextField>(query).enableIMEPersonalizedLearning,
      isFalse,
    );
    expect(
      tester.widget<TextField>(replacement).enableIMEPersonalizedLearning,
      isFalse,
    );

    const arabic = 'العربية';
    await _tapVisible(tester, query);
    await tester.enterText(query, arabic);
    await _tapVisible(tester, replacement);
    await tester.enterText(replacement, arabic);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(query).textDirection, TextDirection.rtl);
    expect(
      tester.widget<TextField>(replacement).textDirection,
      TextDirection.rtl,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Escape closes the find panel while a field has focus', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('find-replace-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+F focuses the query field and selects its text', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'abc');
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('find-query')));
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'needle');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _tapVisible(tester, source);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final query = find.byKey(const ValueKey('find-query'));
    expect(query, findsOneWidget);
    expect(_hasPrimaryFocus(tester, query), isTrue);
    final controller = tester.widget<TextField>(query).controller!;
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 'needle'.length);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated Enter keeps query focus and finds each match', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'one two one');
    final controller = tester.widget<TextField>(source).controller!;
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'one');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(controller.selection.start, 0);
    expect(_hasPrimaryFocus(tester, query), isTrue);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(controller.selection.start, 8);
    expect(_hasPrimaryFocus(tester, query), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated Ctrl+F refocuses the query without closing the panel', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final replacement = find.byKey(const ValueKey('find-replacement'));
    await _tapVisible(tester, replacement);
    expect(_hasPrimaryFocus(tester, replacement), isTrue);

    for (var press = 0; press < 2; press++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);
      expect(
        _hasPrimaryFocus(tester, find.byKey(const ValueKey('find-query'))),
        isTrue,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'repeated Ctrl+F brings a focused, offscreen query back into view',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KotohaApp());

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final query = find.byKey(const ValueKey('find-query'));
      expect(_hasPrimaryFocus(tester, query), isTrue);
      final position = tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .position;
      position.jumpTo(0);
      await tester.pumpAndSettle();
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      final offscreen = tester.getRect(query);
      expect(offscreen.top >= viewport.height || offscreen.bottom <= 0, isTrue);
      expect(_hasPrimaryFocus(tester, query), isTrue);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final back = tester.getRect(query);
      expect(back.top, greaterThanOrEqualTo(0));
      expect(back.bottom, lessThanOrEqualTo(viewport.height));
      expect(_hasPrimaryFocus(tester, query), isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('find fields ignore stale input while the app is paused', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    final replacement = find.byKey(const ValueKey('find-replacement'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'keep');
    await _tapVisible(tester, replacement);
    await tester.enterText(replacement, 'also');

    final stale = TextEditingValue(
      text: 'stale',
      selection: const TextSelection.collapsed(offset: 5),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.testTextInput.updateEditingValue(stale);
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(replacement).controller!.text, 'also');
    expect(tester.widget<TextField>(query).controller!.text, 'keep');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);
    expect(_hasPrimaryFocus(tester, query), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-replace-panel')), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await _tapVisible(tester, query);
    tester.testTextInput.updateEditingValue(stale);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query).controller!.text, 'stale');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+F does not focus the query when paused before the frame', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(const KotohaApp());

    final panel = find.byKey(const ValueKey('find-replace-panel'));
    expect(panel, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(panel, findsOneWidget);
    expect(
      _hasPrimaryFocus(tester, find.byKey(const ValueKey('find-query'))),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('find shortcuts work before any field has focus', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final panel = find.byKey(const ValueKey('find-replace-panel'));
    expect(panel, findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(
      _hasPrimaryFocus(tester, find.byKey(const ValueKey('find-query'))),
      isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(
      _hasPrimaryFocus(tester, find.byKey(const ValueKey('find-query'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+F works after clicking the inert left gutter', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const KotohaApp());

      final source = find.byKey(const ValueKey('source-text'));
      await tester.enterText(source, 'abc');
      await tester.pumpAndSettle();
      expect(_hasPrimaryFocus(tester, source), isTrue);

      // A real mouse click on inert page chrome drops focus out of the
      // TextField; the workspace shortcut must still be reachable.
      final gesture = await tester.startGesture(
        const Offset(2, 98),
        kind: PointerDeviceKind.mouse,
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(_hasPrimaryFocus(tester, source), isFalse);

      final panel = find.byKey(const ValueKey('find-replace-panel'));
      expect(panel, findsNothing);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(panel, findsOneWidget);
      expect(
        _hasPrimaryFocus(tester, find.byKey(const ValueKey('find-query'))),
        isTrue,
      );

      // Escape must reach the workspace binding after a second click-away too.
      final secondClick = await tester.startGesture(
        const Offset(2, 98),
        kind: PointerDeviceKind.mouse,
      );
      await secondClick.up();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a menu choice made before restore cannot edit restored text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final original = FileSelectorPlatform.instance;
      final picker = _PendingPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = original);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const KotohaApp());

      final restored = TextWorkspaceDraft(
        sourceLanguage: 'ja',
        sourceText: 'source',
        translations: [
          const ManualTranslationDraft(
            targetLanguage: 'en',
            text: 'Translation Translation',
          ),
        ],
      );
      final restoreButton = find.byKey(const ValueKey('restore-workspace'));
      await _tapVisible(tester, restoreButton);
      await tester.pumpAndSettle();

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('find-replace-toggle')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('find-query')),
        'Translation',
      );
      await tester.enterText(
        find.byKey(const ValueKey('find-replacement')),
        'WRONG',
      );
      await _tapVisible(tester, find.byKey(const ValueKey('find-target')));
      expect(find.text('Translation 1'), findsOneWidget);

      picker.pending.complete(_WorkspaceFile(formatWorkspaceExport(restored)));
      await tester.pumpAndSettle();
      final restoredText = find.byKey(const ValueKey('translation-text-0'));
      expect(
        tester.widget<TextField>(restoredText).controller!.text,
        'Translation Translation',
      );

      await tester.tap(find.text('Translation 1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('replace-all')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(restoredText).controller!.text,
        'Translation Translation',
      );

      await _tapVisible(tester, find.byKey(const ValueKey('find-target')));
      await tester.tap(find.text('Translation 1'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const ValueKey('replace-all')));
      expect(
        tester.widget<TextField>(restoredText).controller!.text,
        'WRONG WRONG',
      );
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Escape closes the panel from an editor', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final toggle = find.byKey(const ValueKey('find-replace-toggle'));
    final panel = find.byKey(const ValueKey('find-replace-panel'));
    await _tapVisible(tester, toggle);
    await _tapVisible(tester, find.byKey(const ValueKey('source-text')));
    expect(panel, findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(panel, findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(panel, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ctrl+F on an open panel focuses the query immediately', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('source-text')));
    final query = find.byKey(const ValueKey('find-query'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(_hasPrimaryFocus(tester, query), isTrue);
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, query), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing find target keeps focus in the selector', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final target = find.byKey(const ValueKey('find-target'));
    final query = find.byKey(const ValueKey('find-query'));
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    var reached = false;
    for (var i = 0; i < 80; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      if (_hasPrimaryFocus(tester, target)) {
        reached = true;
        break;
      }
    }
    expect(reached, isTrue, reason: 'Tab can reach the find target');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translation 1'));
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, target), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(_hasPrimaryFocus(tester, query), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a successful find shows visible confirmation', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'one two one');
    final controller = tester.widget<TextField>(source).controller!;

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'one');
    expect(find.byKey(const ValueKey('find-status')), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Match found.'), findsOneWidget);
    expect(_hasPrimaryFocus(tester, query), isTrue);
    expect(controller.selection.textInside(controller.text), 'one');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Match found.'), findsOneWidget);
    expect(_hasPrimaryFocus(tester, query), isTrue);
    expect(controller.selection.start, 8);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'find confirmation is visible with the query at the viewport edge',
    (tester) async {
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(800, 360);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.binding.setSurfaceSize(const Size(800, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const KotohaApp());

      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        'one two one',
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final query = find.byKey(const ValueKey('find-query'));
      final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(viewport, const Size(800, 360));
      // Place the query at the lower edge, as it appears when a keyboard user
      // keeps the panel and the query field in view on a short workspace.
      final queryRect = tester.getRect(query);
      final position = tester
          .widget<Scrollable>(find.byType(Scrollable).first)
          .controller!
          .position;
      position.jumpTo(
        position.pixels + queryRect.top - (viewport.height - queryRect.height),
      );
      await tester.pumpAndSettle();

      await tester.tap(query);
      await tester.enterText(query, 'one');
      await tester.pumpAndSettle();
      final focusedQueryRect = tester.getRect(query);
      expect(focusedQueryRect.top, greaterThanOrEqualTo(0));
      expect(focusedQueryRect.bottom, lessThanOrEqualTo(viewport.height));
      expect(focusedQueryRect.bottom, greaterThan(viewport.height - 80));
      expect(_hasPrimaryFocus(tester, query), isTrue);
      expect(find.byKey(const ValueKey('find-status')), findsNothing);

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final status = find.byKey(const ValueKey('find-status'));
      expect(status, findsOneWidget);
      final statusRect = tester.getRect(status);
      expect(
        statusRect.top,
        greaterThanOrEqualTo(0),
        reason:
            'query $focusedQueryRect, status $statusRect, viewport $viewport',
      );
      expect(
        statusRect.bottom,
        lessThanOrEqualTo(viewport.height),
        reason:
            'query $focusedQueryRect, status $statusRect, viewport $viewport',
      );
      expect(tester.widget<Text>(status).data, 'Match found.');
      expect(_hasPrimaryFocus(tester, query), isTrue);
      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Match found.'))
            .getSemanticsData()
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
      handle.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('find status wraps at large text on a narrow viewport', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue,
    );
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const KotohaApp());

    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'cat dog cat',
    );
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final query = find.byKey(const ValueKey('find-query'));
    await tester.enterText(query, 'cat');
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.byKey(const ValueKey('replace-selection')));

    const statusText = 'Select an exact match before replacing.';
    final status = find.byKey(const ValueKey('find-status'));
    expect(status, findsOneWidget);
    expect(tester.widget<Text>(status).data, statusText);

    var reachedRow = false;
    var fittedBoxes = 0;
    RenderBox? flexibleBox;
    status.evaluate().single.visitAncestorElements((element) {
      final widget = element.widget;
      if (widget is FittedBox) fittedBoxes++;
      if (widget is Flexible && flexibleBox == null) {
        final renderObject = element.renderObject;
        if (renderObject is RenderBox) flexibleBox = renderObject;
      }
      if (widget is Row) {
        reachedRow = true;
        return false;
      }
      return true;
    });
    expect(reachedRow, isTrue);
    expect(fittedBoxes, 0, reason: 'status must wrap, not scale down');
    final slot = flexibleBox;
    expect(slot, isNotNull);

    final paragraph = tester.renderObject<RenderParagraph>(status);
    expect(paragraph.textScaler.scale(10), 20);
    expect(
      paragraph.size.width,
      lessThanOrEqualTo(slot!.size.width - 8),
      reason: 'status width ${paragraph.size.width}, slot ${slot.size.width}',
    );
    expect(
      paragraph.size.height,
      greaterThan(paragraph.preferredLineHeight),
      reason:
          'status height ${paragraph.size.height}, '
          'one scaled line ${paragraph.preferredLineHeight}',
    );

    final handle = tester.ensureSemantics();
    expect(
      tester
          .getSemantics(find.bySemanticsLabel(statusText))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    handle.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('find status is exposed to semantics clients', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());
    final handle = tester.ensureSemantics();

    await tester.enterText(
      find.byKey(const ValueKey('source-text')),
      'one two one',
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'one');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final labels = <String>[];
    _collectSemanticsLabels(
      tester
          .binding
          .renderViews
          .single
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
      labels,
    );
    expect(labels, contains('Match found.'));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('editing the found field clears stale feedback', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'cat');
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('find-replace-toggle')),
    );
    final query = find.byKey(const ValueKey('find-query'));
    await _tapVisible(tester, query);
    await tester.enterText(query, 'cat');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Match found.'), findsOneWidget);

    await _tapVisible(tester, source);
    await tester.enterText(source, 'dog');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-status')), findsNothing);

    // Restoring the exact text must not revive a stale result.
    await tester.enterText(source, 'cat');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-status')), findsNothing);
    expect(_hasPrimaryFocus(tester, source), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restoring a document clears a stale find result', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final original = FileSelectorPlatform.instance;
      final picker = _PendingPicker();
      FileSelectorPlatform.instance = picker;
      addTearDown(() => FileSelectorPlatform.instance = original);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(const KotohaApp());

      await tester.enterText(
        find.byKey(const ValueKey('source-text')),
        'cat cat',
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('find-replace-toggle')),
      );
      await tester.enterText(find.byKey(const ValueKey('find-query')), 'cat');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Match found.'), findsOneWidget);

      final restored = TextWorkspaceDraft(
        sourceLanguage: 'en',
        sourceText: 'dog dog',
        translations: [
          const ManualTranslationDraft(targetLanguage: 'fr', text: 'bonjour'),
        ],
      );
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('restore-workspace')),
      );
      picker.pending.complete(_WorkspaceFile(formatWorkspaceExport(restored)));
      await tester.pumpAndSettle();
      await _tapVisible(
        tester,
        find.byKey(const ValueKey('restore-workspace-confirm')),
      );

      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('source-text')))
            .controller!
            .text,
        'dog dog',
      );
      expect(find.byKey(const ValueKey('find-status')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Escape returns keyboard focus to the editor that was found', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());

    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'cat dog');
    await tester.pumpAndSettle();
    expect(_hasPrimaryFocus(tester, source), isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('find-query')), 'cat');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final controller = tester.widget<TextField>(source).controller!;
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('find-replace-panel')), findsNothing);
    expect(_hasPrimaryFocus(tester, source), isTrue);
    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, 3);
    expect(tester.takeException(), isNull);
  });
}
