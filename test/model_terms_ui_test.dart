import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/l10n/app_localizations.dart';
import 'package:kotoha/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.kotoha/model_package');

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  late Map<String, Uint8List> package;
  late List<String> requests;
  late List<String> methods;

  Map<String, Object?> fixtureManifest(
    String terms, {
    String displayName = 'Test model',
  }) {
    final h = sha256.convert(bytes(terms)).toString();
    final size = bytes(terms).length;
    return {
      'id': 'test-model',
      'display_name': displayName,
      'publisher': 'fixture',
      'files': [
        {
          'path': 'weights.bin',
          'role': 'weights',
          'sha256': 'a' * 64,
          'size_bytes': 8,
        },
        {
          'path': 'license/terms.txt',
          'role': 'terms',
          'sha256': h,
          'size_bytes': size,
        },
      ],
      'executor': {
        'engine_id': 'local.engine',
        'adapter_id': 'local.adapter',
        'required_capabilities': ['translation.text'],
      },
      'tasks': [
        {
          'capability': 'translation.text',
          'input_types': ['text'],
          'output_types': ['translations'],
          'languages': {
            'source': ['de'],
            'target': ['ar'],
            'routes': [
              {'source': 'de', 'target': 'ar', 'evidence': 'user'},
            ],
            'scripts': ['Latn'],
          },
        },
      ],
      'resources': {
        'storage_bytes': 8 + size,
        'peak_host_bytes': 0,
        'peak_accelerator_bytes': 0,
        'basis': 'declared',
        'conditions': 'fixture',
      },
      'terms': [
        {
          'id': 'test-license',
          'text_file': 'license/terms.txt',
          'text_sha256': h,
          'consent': 'explicit',
          'usage_requirements': ['Use locally'],
          'required_attributions': ['Attribution X'],
          'covered_files': ['weights.bin', 'license/terms.txt'],
        },
      ],
    };
  }

  void installFixture(String terms, {String displayName = 'Test model'}) {
    final manifest = fixtureManifest(terms, displayName: displayName);
    package = {
      'model_manifest.json': bytes(jsonEncode(manifest)),
      'license/terms.txt': bytes(terms),
    };
    requests = [];
    methods = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      MethodCall call,
    ) async {
      methods.add(call.method);
      switch (call.method) {
        case 'selectDirectory':
          return true;
        case 'readFile':
          final args = (call.arguments as Map).cast<String, Object?>();
          final path = args['path'] as String;
          requests.add(path);
          return package[path];
        case 'release':
          return null;
      }
      return null;
    });
  }

  setUp(() {
    binding.platformDispatcher.localesTestValue = [const Locale('en')];
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.platformDispatcher.clearLocalesTestValue();
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> openAndroid(WidgetTester tester) async {
    await tester.pumpWidget(const KotohaApp());
    await tester.pumpAndSettle();
  }

  Finder reviewButton() => find.byKey(const ValueKey('review-model-terms'));

  testWidgets('terms review shows complete terms and session acceptance', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const terms = 'Synthetic license body';
      installFixture(terms);
      await openAndroid(tester);
      expect(reviewButton(), findsOneWidget);
      expect(find.byKey(const ValueKey('model-session-active')), findsNothing);

      await tester.tap(reviewButton());
      await tester.pumpAndSettle();

      // Complete review is explicit: title, runtime-disabled, integrity-only,
      // verified count, full text, usage and attributions.
      expect(find.text('Terms for Test model'), findsOneWidget);
      expect(find.text('Package ID: test-model'), findsOneWidget);
      expect(
        find.text('Declared publisher (unverified): fixture'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'does not install a model or enable runtime use',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'do not prove origin, authenticity, or license approval',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'All 1 declared terms files were verified',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text(terms), findsOneWidget);
      expect(find.textContaining('Use locally'), findsOneWidget);
      expect(find.textContaining('Attribution X'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('accept-model-terms')));
      await tester.pumpAndSettle();

      expect(find.textContaining('session only'), findsOneWidget);
      // Session digest binding is retained in volatile state.
      expect(
        find.byKey(const ValueKey('model-session-active')),
        findsOneWidget,
      );
      // Only manifest and declared terms were read; no weight path.
      expect(requests, ['model_manifest.json', 'license/terms.txt']);
      expect(requests.contains('weights.bin'), isFalse);
      expect(methods.contains('release'), isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a long model name keeps the terms reachable', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(360, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      installFixture(
        'Synthetic license body',
        displayName: 'Multilingual Model Edition ' * 40,
      );
      await openAndroid(tester);
      await tester.ensureVisible(reviewButton());
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final termsBody = find.text('Synthetic license body');
      expect(termsBody, findsOneWidget);
      await tester.ensureVisible(termsBody);
      await tester.pumpAndSettle();
      final termsRect = tester.getRect(termsBody);
      final view = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(termsRect.top, greaterThanOrEqualTo(0));
      expect(termsRect.bottom, lessThanOrEqualTo(view.height));
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('decline-model-terms')));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('declined review records no approval and clears session', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      const terms = 'Synthetic license body';
      installFixture(terms);
      await openAndroid(tester);

      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decline-model-terms')));
      await tester.pumpAndSettle();

      expect(find.textContaining('declined'), findsOneWidget);
      expect(find.byKey(const ValueKey('model-session-active')), findsNothing);
      expect(requests, ['model_manifest.json', 'license/terms.txt']);
      expect(requests.contains('weights.bin'), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('localized review keeps honesty notices', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      binding.platformDispatcher.localesTestValue = [const Locale('ja')];
      const terms = '合成ライセンス本文';
      installFixture(terms);
      await openAndroid(tester);
      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      final strings = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      )!;
      expect(find.text(strings.modelIntegrityOnly), findsOneWidget);
      expect(find.text(strings.modelAllTermsVerified(1)), findsOneWidget);
      expect(find.text(terms), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('decline-model-terms')));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
