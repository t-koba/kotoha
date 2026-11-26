import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/license_expression.dart';

const Map<String, String> _classifications = <String, String>{
  'MIT': 'permissive',
  'Apache-2.0': 'permissive',
  'Apache-2.0 WITH LLVM-exception': 'permissive',
  'CC0-1.0': 'public-domain',
  'GPL-3.0-only': 'gpl-family',
  'LicenseRef-Unclassified': 'unknown',
};

Set<String>? select(String expression) => selectedLicenseTerms(
  expression,
  _classifications,
  acceptableCategories: const <String>{'permissive', 'public-domain'},
  excludedCategories: const <String>{'gpl-family', 'commercial-paid'},
);

void expectTerms(String expression, Set<String>? expected) {
  final actual = select(expression);
  if (expected == null) {
    expect(actual, isNull, reason: expression);
    return;
  }
  expect(actual, isNotNull, reason: expression);
  expect(actual!.length, expected.length, reason: expression);
  expect(actual, containsAll(expected), reason: expression);
}

void main() {
  group('selectedLicenseTerms', () {
    test('selects a single acceptable term', () {
      expectTerms('MIT', <String>{'MIT'});
    });

    test('selects the acceptable OR branch', () {
      expectTerms('MIT OR GPL-3.0-only', <String>{'MIT'});
      expectTerms('GPL-3.0-only OR MIT', <String>{'MIT'});
    });

    test('unions AND terms in the selected branch', () {
      expectTerms('(MIT OR Apache-2.0) AND CC0-1.0', <String>{
        'MIT',
        'CC0-1.0',
      });
    });

    test('rejects an AND term with an excluded category', () {
      expectTerms('GPL-3.0-only AND MIT', null);
    });

    test('rejects an unclassified term', () {
      expectTerms('LicenseRef-Unclassified', null);
    });

    test('recognizes an exception as part of the term identifier', () {
      expectTerms('Apache-2.0 WITH LLVM-exception', <String>{
        'Apache-2.0 WITH LLVM-exception',
      });
      expectTerms('MIT WITH LLVM-exception', null);
    });

    test('excluded category overrides an acceptable category', () {
      expect(
        selectedLicenseTerms(
          'MIT',
          _classifications,
          acceptableCategories: const <String>{'permissive'},
          excludedCategories: const <String>{'permissive'},
        ),
        isNull,
      );
    });

    test('honors AND before OR', () {
      expectTerms('GPL-3.0-only OR MIT AND Apache-2.0', <String>{
        'MIT',
        'Apache-2.0',
      });
      expectTerms('MIT OR GPL-3.0-only AND Apache-2.0', <String>{'MIT'});
    });

    test('rejects malformed expressions and trailing tokens', () {
      expectTerms('MIT AND', null);
      expectTerms('MIT & Apache-2.0', null);
      expectTerms('MIT (Apache-2.0)', null);
      expectTerms('(MIT OR Apache-2.0', null);
      expectTerms('', null);
    });
  });
}
