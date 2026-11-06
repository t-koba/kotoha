import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

bool _isSelectedOrChecked(SemanticsData data) =>
    data.flagsCollection.isSelected == ui.Tristate.isTrue ||
    data.flagsCollection.isChecked == ui.CheckedState.isTrue;

void main() {
  testWidgets('language menu announces the active session locale', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = [const Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('source-text'));
    await tester.enterText(source, 'temporary manual text');
    await tester.pump();
    final sourceController = tester.widget<TextField>(source).controller!;

    final semantics = tester.ensureSemantics();
    try {
      await tester.tap(find.byKey(const ValueKey('ui-language')));
      await tester.pumpAndSettle();
      expect(
        _isSelectedOrChecked(
          tester.getSemantics(find.text('English')).getSemanticsData(),
        ),
        isTrue,
      );
      expect(
        _isSelectedOrChecked(
          tester.getSemantics(find.text('日本語')).getSemanticsData(),
        ),
        isFalse,
      );

      await tester.tap(find.byType(CheckedPopupMenuItem<Locale>).first);
      await tester.pumpAndSettle();
      expect(sourceController.text, 'temporary manual text');
      await tester.tap(find.byKey(const ValueKey('ui-language')));
      await tester.pumpAndSettle();
      expect(
        _isSelectedOrChecked(
          tester.getSemantics(find.text('日本語')).getSemanticsData(),
        ),
        isTrue,
      );
      expect(
        _isSelectedOrChecked(
          tester.getSemantics(find.text('English')).getSemanticsData(),
        ),
        isFalse,
      );
    } finally {
      semantics.dispose();
    }
  });
}
