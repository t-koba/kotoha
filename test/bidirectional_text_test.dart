import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
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
      const rtlSource = 'العربية — English 日本語';
      const ltrSource = 'English — العربية 日本語';
      const rtlTranslation = 'עברית — English العربية';

      for (final locale in [const Locale('en'), const Locale('ja')]) {
        tester.binding.platformDispatcher.localesTestValue = [locale];
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(const KotohaApp());
        await tester.pumpAndSettle();

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

        final copy = find.byKey(copyKey);
        await tester.ensureVisible(copy);
        await tester.pumpAndSettle();
        await tester.tap(copy);
        await tester.pump();
        expect(clipboardCalls.last.arguments, {'text': rtlTranslation});
      }
    },
  );
}
