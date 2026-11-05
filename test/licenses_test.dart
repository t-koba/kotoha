import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/main.dart';

void main() {
  testWidgets('opens a license page backed by the license registry', (
    tester,
  ) async {
    LicenseRegistry.addLicense(
      () => Stream<LicenseEntry>.value(
        const LicenseEntryWithLineBreaks([
          'kotoha_test_package',
        ], 'Test license body.'),
      ),
    );
    addTearDown(LicenseRegistry.reset);

    await tester.pumpWidget(const KotohaApp());

    expect(find.byKey(const ValueKey('show-licenses')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('show-licenses')));
    await tester.pumpAndSettle();

    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('kotoha_test_package'), findsWidgets);
  });
}
