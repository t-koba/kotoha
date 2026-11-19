import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
  for (final (locale, title, handled, preserved, review) in [
    (
      const Locale('en'),
      'TXT / Markdown support',
      'Recognized locally: headings, paragraphs, list items and fenced code.',
      'The flat source text and exact block ranges stay canonical and editable; '
          'output is plain text.',
      'Inline formatting, numbers, links and placeholders are not converted; '
          'check them manually.',
    ),
    (
      const Locale('ja'),
      'テキスト形式の対応範囲',
      'ローカルで認識: 見出し、段落、リスト項目、コードブロック。',
      '原文のテキストとブロックの正確な範囲は編集可能なまま維持し、出力はプレーンテキストです。',
      'インライン装飾、数字、リンク、プレースホルダーは変換しません。手動で確認してください。',
    ),
  ]) {
    testWidgets('capability note is localized for $locale', (tester) async {
      tester.binding.platformDispatcher.localesTestValue = [locale];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const KotohaApp());
      await tester.pumpAndSettle();

      final note = find.byKey(const ValueKey('document-format-support'));
      expect(note, findsOneWidget);
      expect(
        find.descendant(of: note, matching: find.text(title)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: note, matching: find.text(handled)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: note, matching: find.text(preserved)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: note, matching: find.text(review)),
        findsOneWidget,
      );
    });
  }
}
