import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/text_find_replace.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
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
}
