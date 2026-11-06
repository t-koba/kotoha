import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart' as app;

void main() {
  testWidgets('bundled Unicode notice is accessible from the license page', (
    tester,
  ) async {
    addTearDown(LicenseRegistry.reset);
    app.main();
    await tester.pumpAndSettle();

    final notice = await rootBundle.loadString(
      'assets/licenses/Unicode-3.0.txt',
    );
    final entries = await LicenseRegistry.licenses
        .where((entry) => entry.packages.contains('Unicode Bidi Data'))
        .toList();
    expect(entries, hasLength(1));
    String normalizeWhitespace(String text) =>
        text.replaceAll(RegExp(r'\s+'), ' ').trim();
    expect(
      normalizeWhitespace(
        entries.single.paragraphs.map((p) => p.text).join(' '),
      ),
      normalizeWhitespace(notice),
    );

    await tester.tap(find.byKey(const ValueKey('show-licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    await tester.tap(find.text('Unicode Bidi Data'));
    await tester.pumpAndSettle();
    expect(find.text('UNICODE LICENSE V3'), findsOneWidget);
    expect(find.text('Copyright © 1991-2026 Unicode, Inc.'), findsOneWidget);
  });
}
