import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = math.max(firstLuminance, secondLuminance);
  final darker = math.min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  testWidgets('follows system appearance with readable editor colors', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const KotohaApp());
    for (final brightness in [Brightness.light, Brightness.dark]) {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      expect(theme.brightness, brightness);
      expect(scheme.brightness, brightness);
      expect(theme.scaffoldBackgroundColor, scheme.surface);

      final foregroundPairs = <String, (Color, Color)>{
        'body text': (scheme.onSurface, scheme.surface),
        'field labels': (scheme.onSurfaceVariant, scheme.surface),
        'primary control labels': (scheme.onPrimary, scheme.primary),
        'draft notice': (scheme.onTertiaryContainer, scheme.tertiaryContainer),
        'snackbar': (scheme.onInverseSurface, scheme.inverseSurface),
      };
      for (final entry in foregroundPairs.entries) {
        expect(
          _contrastRatio(entry.value.$1, entry.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} contrast in $brightness theme',
        );
      }
    }
  });
}
