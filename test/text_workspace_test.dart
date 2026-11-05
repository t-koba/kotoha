import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
  testWidgets('keeps the source separate while adding manual translations', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());

    expect(find.textContaining('自動翻訳は行いません'), findsOneWidget);
    expect(find.textContaining('このビルドでは保存されません'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('source-text')), 'こんにちは');
    await tester.dragUntilVisible(
      find.text('訳先を追加'),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('訳先を追加'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('translation-text-1')),
      'Hello',
    );

    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('source-text')))
          .controller!
          .text,
      'こんにちは',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('translation-text-1')))
          .controller!
          .text,
      'Hello',
    );
    expect(find.byKey(const ValueKey('translation-text-0')), findsOneWidget);
  });

  testWidgets('does not allow deleting the final translation field', (
    tester,
  ) async {
    await tester.pumpWidget(const KotohaApp());
    await tester.dragUntilVisible(
      find.text('訳先を追加'),
      find.byType(Scrollable).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('訳先を追加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-translation-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('translation-text-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-text-1')), findsNothing);
  });
}
