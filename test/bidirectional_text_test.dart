import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';
import 'package:kotoha/first_strong_direction.dart';

void main() {
  test('UAX #9 P2/P3 scans scalars and ignores non-strong types', () {
    const cases = <String, TextDirection>{
      '😀 العربية': TextDirection.rtl, // Supplementary ON, then AL.
      '\u200fEnglish': TextDirection.rtl, // RLM is R, not neutral.
      '\u{10ECB}English':
          TextDirection.rtl, // UCD17 @missing: Arabic Extended-C is AL.
      '\u061cEnglish': TextDirection.rtl, // ALM is AL.
      '\u200eالعربية': TextDirection.ltr, // LRM is L.
      '\u{1E900} English': TextDirection.rtl, // Supplementary R (Adlam).
      '\u{10400} العربية': TextDirection.ltr, // Supplementary L (Deseret).
      '\u{1F680}\u{1D167}עברית': TextDirection.rtl, // ON and NSM.
      '\u202bEnglish': TextDirection.ltr, // RLE is not a strong type.
      // Skip nested LRI/RLI/FSI through their matching PDI.
      '\u2066English\u2067עברית\u2069\u2068日本語\u2069\u2069العربية':
          TextDirection.rtl,
      '\u2067עברית\u2069English': TextDirection.ltr,
      '\u2069العربية': TextDirection.rtl, // Unmatched PDI is skipped.
      '\u2067العربية': TextDirection.ltr, // Unmatched isolate hides rest.
      '\u2066English\u2067עברית\u2069العربية': TextDirection.ltr,
      '\nالعربية': TextDirection.ltr, // B terminates before a strong type.
      '\u2067עברית\u2029\u2069العربية': TextDirection.ltr, // B in isolate.
      'العربية\nEnglish': TextDirection.rtl, // First paragraph only.
      '': TextDirection.ltr,
      '123 😀': TextDirection.ltr, // No strong type defaults to LTR.
    };
    for (final entry in cases.entries) {
      expect(firstStrongDirection(entry.key), entry.value, reason: entry.key);
    }
  });

  testWidgets(
    'mixed-script text direction and clipboard are independent of UI locale',
    (tester) async {
      final clipboardCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboardCalls.add(call);
          if (call.method == 'Clipboard.hasStrings') return {'value': false};
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      const sourceKey = ValueKey('source-text');
      const translationKey = ValueKey('translation-text-0');
      const copyKey = ValueKey('copy-translation-0');
      const rtlSource = '😀 العربية — English 日本語';
      const ltrSource = '\u200eEnglish — العربية 日本語';
      const rtlTranslation = '\u200fEnglish — עברית العربية';

      for (final locale in [const Locale('en'), const Locale('ja')]) {
        tester.binding.platformDispatcher.localesTestValue = [locale];
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const KotohaApp());
        await tester.pumpAndSettle();

        final languageFields = [
          (find.byKey(const ValueKey('source-language')), 'source language'),
          (find.byKey(const ValueKey('target-language-0')), 'target language'),
        ];
        for (final (field, label) in languageFields) {
          await tester.ensureVisible(field);
          await tester.pumpAndSettle();
          final controller = tester.widget<TextField>(field).controller!;
          final editable = find.descendant(
            of: field,
            matching: find.byType(EditableText),
          );
          for (final (text, direction) in [
            (rtlSource, TextDirection.rtl),
            (ltrSource, TextDirection.ltr),
          ]) {
            await tester.enterText(field, text);
            await tester.pump();
            final editableState = tester.state<EditableTextState>(editable);
            expect(
              editableState.widget.textDirection,
              direction,
              reason: '$label direction for $text',
            );
            expect(editableState.widget.focusNode.hasFocus, isTrue);
            expect(controller.text, text);
            expect(controller.selection.baseOffset, text.length);

            final render = editableState.renderEditable;
            final startCaret = render.getLocalRectForCaret(
              const TextPosition(offset: 0),
            );
            final endCaret = render.getLocalRectForCaret(
              TextPosition(offset: text.length),
            );
            if (direction == TextDirection.rtl) {
              expect(
                startCaret.left,
                greaterThan(endCaret.left),
                reason: '$label RTL caret order',
              );
            } else {
              expect(
                startCaret.left,
                lessThan(endCaret.left),
                reason: '$label LTR caret order',
              );
            }
          }
        }

        final source = find.byKey(sourceKey);
        final sourceController = tester.widget<TextField>(source).controller!;
        final sourceEditable = find.descendant(
          of: source,
          matching: find.byType(EditableText),
        );
        await tester.enterText(source, rtlSource);
        await tester.pump();
        expect(
          tester.widget<EditableText>(sourceEditable).textDirection,
          TextDirection.rtl,
        );
        expect(
          tester.widget<EditableText>(sourceEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(sourceController.text, rtlSource);
        expect(sourceController.selection.baseOffset, rtlSource.length);

        await tester.enterText(source, ltrSource);
        await tester.pump();
        expect(
          tester.widget<EditableText>(sourceEditable).textDirection,
          TextDirection.ltr,
        );
        expect(
          tester.widget<EditableText>(sourceEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(sourceController.text, ltrSource);
        expect(sourceController.selection.baseOffset, ltrSource.length);

        final translation = find.byKey(translationKey);
        final translationController = tester
            .widget<TextField>(translation)
            .controller!;
        final translationEditable = find.descendant(
          of: translation,
          matching: find.byType(EditableText),
        );
        await tester.enterText(translation, rtlTranslation);
        await tester.pump();
        expect(
          tester.widget<EditableText>(translationEditable).textDirection,
          TextDirection.rtl,
        );
        expect(
          tester.widget<EditableText>(translationEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(translationController.text, rtlTranslation);
        expect(
          translationController.selection.baseOffset,
          rtlTranslation.length,
        );

        const selected = TextSelection(baseOffset: 1, extentOffset: 8);
        translationController.selection = selected;
        await tester.pump();
        expect(translationController.selection, selected);
        final edited = translationController.value.replaced(selected, '日本語');
        tester.testTextInput.updateEditingValue(edited);
        await tester.pump();
        expect(translationController.value, edited);
        expect(
          tester.widget<EditableText>(translationEditable).focusNode.hasFocus,
          isTrue,
        );
        expect(
          tester.widget<EditableText>(translationEditable).textDirection,
          TextDirection.rtl,
        );

        final copy = find.byKey(copyKey);
        await tester.ensureVisible(copy);
        await tester.pumpAndSettle();
        await tester.tap(copy);
        await tester.pump();
        expect(clipboardCalls.last.arguments, {'text': edited.text});
      }
    },
  );

  testWidgets('renderer lays out bidi runs and caret positions', (
    tester,
  ) async {
    const text = 'العربية — English';
    const multilineText = 'العربية\nEnglish';
    final controller = TextEditingController(text: text);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 160,
            child: TextField(
              controller: controller,
              maxLines: null,
              textDirection: firstStrongDirection(text),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final editableFinder = find.byType(EditableText);
    final editableState = tester.state<EditableTextState>(editableFinder);
    final renderEditable = editableState.renderEditable;
    final startCaret = renderEditable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    final endCaret = renderEditable.getLocalRectForCaret(
      TextPosition(offset: text.length),
    );
    final selectionBoxes = renderEditable.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    );

    expect(startCaret.left, greaterThan(endCaret.left));
    expect(
      selectionBoxes.map((box) => box.direction).toSet(),
      containsAll({TextDirection.ltr, TextDirection.rtl}),
    );

    controller.value = const TextEditingValue(
      text: multilineText,
      selection: TextSelection.collapsed(offset: 0),
    );
    await tester.pumpAndSettle();
    final multilineRenderEditable = tester
        .state<EditableTextState>(editableFinder)
        .renderEditable;
    final firstParagraphCaret = multilineRenderEditable.getLocalRectForCaret(
      const TextPosition(offset: 0),
    );
    final secondParagraphCaret = multilineRenderEditable.getLocalRectForCaret(
      const TextPosition(offset: 8),
    );
    expect(secondParagraphCaret.top, greaterThan(firstParagraphCaret.top));
  });

  testWidgets('source field preserves composing input across edit rebuilds', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());
    final source = find.byKey(const ValueKey('source-text'));
    await tester.tap(source);
    await tester.pump();

    final controller = tester.widget<TextField>(source).controller!;
    final editable = find.descendant(
      of: source,
      matching: find.byType(EditableText),
    );
    final focusNode = tester.widget<EditableText>(editable).focusNode;

    const firstComposition = TextEditingValue(
      text: 'ひらがな',
      selection: TextSelection.collapsed(offset: 4),
      composing: TextRange(start: 0, end: 4),
    );
    tester.testTextInput.updateEditingValue(firstComposition);
    await tester.pump();
    expect(tester.widget<TextField>(source).controller, same(controller));
    expect(controller.value, firstComposition);
    expect(tester.widget<EditableText>(editable).focusNode, same(focusNode));
    expect(focusNode.hasFocus, isTrue);

    const secondComposition = TextEditingValue(
      text: 'ひらがな日本語',
      selection: TextSelection.collapsed(offset: 7),
      composing: TextRange(start: 0, end: 7),
    );
    tester.testTextInput.updateEditingValue(secondComposition);
    await tester.pump();
    expect(tester.widget<TextField>(source).controller, same(controller));
    expect(controller.value, secondComposition);
    expect(controller.value.composing, const TextRange(start: 0, end: 7));
    expect(tester.widget<EditableText>(editable).focusNode, same(focusNode));
    expect(focusNode.hasFocus, isTrue);
  });
}
