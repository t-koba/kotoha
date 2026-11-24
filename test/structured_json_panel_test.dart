import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/l10n/app_localizations.dart';
import 'package:kotoha/structured_json_panel.dart';

void main() {
  const panelKey = ValueKey<String>('structured-json-panel');
  const applyKey = ValueKey<String>('structured-json-apply');
  const title = 'Structured JSON values';
  const invalidMessage =
      'The source is not valid JSON. Fix the source text before editing values.';
  const tooLargeMessage =
      'This source is too large for the JSON editor. Shorten it before editing values.';
  const tooManyMessage =
      'This JSON has too many string values to edit here. Shorten the source before editing values.';
  const appliedMessage = 'Translations applied to the source text.';

  Widget panelFor(TextEditingController controller) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(
      body: SingleChildScrollView(
        child: StructuredJsonPanel(controller: controller),
      ),
    ),
  );

  Future<void> expand(WidgetTester tester) async {
    await tester.tap(find.byKey(panelKey));
    await tester.pumpAndSettle();
  }

  testWidgets('panel starts collapsed and exposes structured-json-panel', (
    tester,
  ) async {
    final controller = TextEditingController(text: '{"a":"x"}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));

    final panel = find.byKey(panelKey);
    expect(panel, findsOneWidget);
    expect(tester.widget<ExpansionTile>(panel).initiallyExpanded, isFalse);
    expect(find.text(title), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      findsNothing,
    );
  });

  testWidgets('collapsed header is reachable by Tab and opens with Enter', (
    tester,
  ) async {
    final controller = TextEditingController(text: '{"a":"x"}');
    addTearDown(controller.dispose);
    final previousFocus = FocusNode(debugLabel: 'before-json-panel');
    addTearDown(previousFocus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Column(
            children: [
              Focus(focusNode: previousFocus, child: const Text('before')),
              StructuredJsonPanel(controller: controller),
            ],
          ),
        ),
      ),
    );

    final headerNode = Focus.of(tester.element(find.text(title)));
    previousFocus.requestFocus();
    await tester.pump();
    expect(previousFocus.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(headerNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      findsOneWidget,
    );
  });

  testWidgets('applying a translation rewrites source and preserves the rest', (
    tester,
  ) async {
    const source =
        '{\n  "greeting": "Hello",\n  "nested": { "keep": "a\\/b" },\n  "count": 2\n}\n';
    final controller = TextEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    expect(find.text('2 string values found.'), findsOneWidget);
    expect(find.text(r'$.greeting'), findsOneWidget);
    expect(find.text(r'$.nested.keep'), findsOneWidget);
    final field = find.byKey(const ValueKey<String>('structured-json-field-0'));
    expect(field, findsOneWidget);

    await tester.enterText(field, 'Bonjour');
    await tester.tap(find.byKey(applyKey));
    await tester.pumpAndSettle();

    expect(controller.text, source.replaceFirst('Hello', 'Bonjour'));
    expect(controller.text, contains(r'"keep": "a\/b"'));
    expect(jsonDecode(controller.text), <String, dynamic>{
      'greeting': 'Bonjour',
      'nested': <String, dynamic>{'keep': 'a/b'},
      'count': 2,
    });
    expect(find.text(appliedMessage), findsOneWidget);
  });

  testWidgets('apply without translations leaves source and status unchanged', (
    tester,
  ) async {
    const source = '{"one":"first","two":"second"}';
    final controller = TextEditingController(text: source);
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    await tester.tap(find.byKey(applyKey));
    await tester.pumpAndSettle();

    expect(controller.text, source);
    expect(find.text(appliedMessage), findsNothing);
  });

  testWidgets('empty translations leave original values unchanged', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: '{"one":"first","two":"second"}',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      '',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('structured-json-field-1')),
      'second changed',
    );
    await tester.tap(find.byKey(applyKey));
    await tester.pumpAndSettle();

    expect(jsonDecode(controller.text), <String, dynamic>{
      'one': 'first',
      'two': 'second changed',
    });
    expect(find.text(appliedMessage), findsOneWidget);
  });

  testWidgets('nonempty whitespace replacement is applied while an empty '
      'sibling is unchanged', (tester) async {
    final controller = TextEditingController(
      text: '{"one":"first","two":"second"}',
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    // U+3000 IDEOGRAPHIC SPACE is a nonempty, intentional value; trim() would
    // erase it and silently skip the replacement.
    await tester.enterText(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      '\u3000',
    );
    // Field 1 stays genuinely empty, so "two" must keep its original value.
    await tester.tap(find.byKey(applyKey));
    await tester.pumpAndSettle();

    expect(jsonDecode(controller.text), <String, dynamic>{
      'one': '\u3000',
      'two': 'second',
    });
    expect(find.text(appliedMessage), findsOneWidget);
  });

  testWidgets('invalid JSON shows localized message and no fields', (
    tester,
  ) async {
    final controller = TextEditingController(text: '{"a": }');
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    expect(find.text(invalidMessage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      findsNothing,
    );
    expect(find.byKey(applyKey), findsNothing);
  });

  testWidgets('oversized source shows bounded message without parsing', (
    tester,
  ) async {
    final padding = 'x' * (128 * 1024 + 1);
    final controller = TextEditingController(text: '{"a":"$padding"}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    expect(find.text(tooLargeMessage), findsOneWidget);
    expect(find.text(invalidMessage), findsNothing);
    expect(find.text('1 string values found.'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      findsNothing,
    );
  });

  testWidgets('changing the source refreshes parsed rows', (tester) async {
    final controller = TextEditingController(text: '{"a":"one","b":"two"}');
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);
    expect(find.text(r'$.a'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-1')),
      findsOneWidget,
    );

    controller.text = '{"c":"three"}';
    await tester.pumpAndSettle();

    expect(find.text(r'$.a'), findsNothing);
    expect(find.text(r'$.c'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-1')),
      findsNothing,
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey<String>('structured-json-field-0')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('too many values shows the limit without building rows', (
    tester,
  ) async {
    final controller = TextEditingController(
      text: jsonEncode(<String, String>{
        for (var index = 0; index < 201; index++) 'key$index': 'value$index',
      }),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    expect(find.text(tooManyMessage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      findsNothing,
    );
    expect(find.byKey(applyKey), findsNothing);
  });

  testWidgets('apply clamps the source selection to the rewritten length', (
    tester,
  ) async {
    const source = '{"a":"Hello"}';
    final controller = TextEditingController();
    controller.value = TextEditingValue(
      text: source,
      selection: TextSelection.collapsed(offset: source.length),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(panelFor(controller));
    await expand(tester);

    await tester.enterText(
      find.byKey(const ValueKey<String>('structured-json-field-0')),
      'Hi',
    );
    await tester.tap(find.byKey(applyKey));
    await tester.pumpAndSettle();

    expect(controller.text, '{"a":"Hi"}');
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.baseOffset, controller.text.length);
  });
}
