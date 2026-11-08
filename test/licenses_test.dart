import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart' as app;

void main() {
  testWidgets('bundled notices are accessible from the license page', (
    tester,
  ) async {
    addTearDown(LicenseRegistry.reset);
    app.main();
    await tester.pumpAndSettle();

    String normalizeWhitespace(String text) =>
        text.replaceAll(RegExp(r'\s+'), ' ').trim();
    Future<void> expectBundledNotice(String package, String asset) async {
      final notice = await rootBundle.loadString(asset);
      final entries = await LicenseRegistry.licenses
          .where((entry) => entry.packages.contains(package))
          .toList();
      expect(entries, hasLength(1));
      expect(
        normalizeWhitespace(
          entries.single.paragraphs.map((p) => p.text).join(' '),
        ),
        normalizeWhitespace(notice),
      );
    }

    await expectBundledNotice(
      'Unicode Bidi Data',
      'assets/licenses/Unicode-3.0.txt',
    );
    await expectBundledNotice('crypto', 'assets/licenses/crypto-3.0.8.txt');

    await tester.tap(find.byKey(const ValueKey('show-licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    await tester.tap(find.text('Unicode Bidi Data'));
    await tester.pumpAndSettle();
    expect(find.text('UNICODE LICENSE V3'), findsOneWidget);
    expect(find.text('Copyright © 1991-2026 Unicode, Inc.'), findsOneWidget);
    // Back to the package list, then open the crypto notice.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('crypto'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dart project authors'), findsOneWidget);
    expect(
      find.textContaining('Redistribution and use in source and binary forms'),
      findsOneWidget,
    );
  });
}
