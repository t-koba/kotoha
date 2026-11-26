import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/l10n/app_localizations.dart';
import 'package:kotoha/l10n/app_localizations_en.dart';
import 'package:kotoha/main.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('org.kotoha/model_package');

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  late Map<String, Uint8List> package;
  late List<String> requests;
  late List<String> methods;
  late bool verifyReplies;
  late bool selectReplies;
  late List<Map<String, Object?>> verifyRequests;
  Completer<Object?>? verifyGate;

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

  void installFixture(
    String terms, {
    String displayName = 'Test model',
    bool verify = true,
    bool select = true,
    bool releaseFails = false,
  }) {
    verifyReplies = verify;
    selectReplies = select;
    verifyRequests = [];
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
          return selectReplies;
        case 'verifyFiles':
          verifyRequests.add((call.arguments as Map).cast<String, Object?>());
          final gate = verifyGate;
          if (gate != null) return gate.future;
          return verifyReplies;
        case 'readFile':
          final args = (call.arguments as Map).cast<String, Object?>();
          final path = args['path'] as String;
          requests.add(path);
          return package[path];
        case 'release':
          if (releaseFails) {
            throw PlatformException(
              code: 'release-failed',
              message: 'synthetic failure',
            );
          }
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

  Future<void> acceptTerms(WidgetTester tester) async {
    await tester.tap(reviewButton());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('accept-model-terms')));
    await tester.pumpAndSettle();
    // Clear the terms snackbar so the integrity result is not queued behind it.
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .clearSnackBars();
    await tester.pumpAndSettle();
  }

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
          'Declared terms files verified before review: 1',
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

  testWidgets('integrity check needs distinct consent and reports success', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      const terms = 'Synthetic license body';
      installFixture(terms);
      await openAndroid(tester);
      expect(find.byKey(const ValueKey('verify-model-files')), findsNothing);
      await acceptTerms(tester);

      final verifyButton = find.byKey(const ValueKey('verify-model-files'));
      expect(verifyButton, findsOneWidget);
      await tester.ensureVisible(verifyButton);
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();

      // Separate, session-only consent; no terms text or approval copy here.
      expect(
        find.byKey(const ValueKey('model-integrity-consent-dialog')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'stream the declared files in place',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'No file bytes or text are copied',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('No engine is enabled', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'do not prove origin, authenticity',
          findRichText: true,
        ),
        findsOneWidget,
      );
      expect(find.text(terms), findsNothing);
      expect(verifyRequests, isEmpty);

      await tester.tap(find.byKey(const ValueKey('decline-model-integrity')));
      await tester.pumpAndSettle();
      expect(verifyRequests, isEmpty);
      expect(
        find.byKey(const ValueKey('model-integrity-success')),
        findsNothing,
      );

      await tester.ensureVisible(verifyButton);
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-model-integrity')));
      await tester.pumpAndSettle();

      expect(verifyRequests.length, 1);
      final declared = (verifyRequests.single['files'] as List).single;
      expect(declared, {
        'path': 'weights.bin',
        'sizeBytes': 8,
        'sha256': 'a' * 64,
      });
      expect(
        find.byKey(const ValueKey('model-integrity-success')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Declared model files matched', findRichText: true),
        findsOneWidget,
      );
      // Only metadata was requested from Dart; weight bytes never crossed.
      expect(requests, ['model_manifest.json', 'license/terms.txt']);
      expect(methods.where((method) => method == 'verifyFiles').length, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('integrity failure and cancelled selection fail closed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      const terms = 'Synthetic license body';
      installFixture(terms, verify: false);
      await openAndroid(tester);
      await acceptTerms(tester);
      final verifyButton = find.byKey(const ValueKey('verify-model-files'));
      await tester.ensureVisible(verifyButton);
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-model-integrity')));
      await tester.pumpAndSettle();
      expect(verifyRequests.length, 1);
      expect(
        find.byKey(const ValueKey('model-integrity-failure')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('model-integrity-success')),
        findsNothing,
      );
      // Acceptance stays session-only and no runtime control appears.
      expect(
        find.byKey(const ValueKey('model-session-active')),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('workspace restore is disabled while file verification runs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      installFixture('Synthetic license body');
      verifyGate = Completer<Object?>();
      await openAndroid(tester);
      await acceptTerms(tester);

      final restore = find.byKey(const ValueKey('restore-workspace'));
      await tester.ensureVisible(restore);
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNotNull);

      final verifyButton = find.byKey(const ValueKey('verify-model-files'));
      await tester.ensureVisible(verifyButton);
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-model-integrity')));
      await tester.pump();

      expect(verifyRequests.length, 1);
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNull);
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('review-model-terms')),
            )
            .onPressed,
        isNull,
      );

      verifyGate!.complete(true);
      verifyGate = null;
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(restore).onPressed, isNotNull);
    } finally {
      verifyGate = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('integrity check without a folder selection reports failure', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      const terms = 'Synthetic license body';
      installFixture(terms);
      await openAndroid(tester);
      await acceptTerms(tester);
      // The temporary grant is released after review; a declined re-selection
      // fails closed without invoking the verifier.
      selectReplies = false;
      final verifyButton = find.byKey(const ValueKey('verify-model-files'));
      await tester.ensureVisible(verifyButton);
      await tester.tap(verifyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-model-integrity')));
      await tester.pumpAndSettle();
      expect(verifyRequests, isEmpty);
      expect(
        find.byKey(const ValueKey('model-integrity-failure')),
        findsOneWidget,
      );
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

  test('English terms-verification status uses count-neutral wording', () {
    final strings = AppLocalizationsEn();
    expect(
      strings.modelAllTermsVerified(1),
      'Declared terms files verified before review: 1.',
    );
    expect(
      strings.modelAllTermsVerified(2),
      'Declared terms files verified before review: 2.',
    );
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
  testWidgets('clearing session consent removes the volatile binding', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      const terms = 'Synthetic license body';
      installFixture(terms);
      await openAndroid(tester);
      expect(find.byKey(const ValueKey('model-session-active')), findsNothing);

      await acceptTerms(tester);
      expect(
        find.byKey(const ValueKey('model-session-active')),
        findsOneWidget,
      );
      final clearButton = find.byKey(const ValueKey('clear-model-consent'));
      expect(clearButton, findsOneWidget);
      await tester.ensureVisible(clearButton);
      final requestsAfterAccept = List<String>.from(requests);

      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('model-session-active')), findsNothing);
      expect(clearButton, findsNothing);
      expect(
        find.text('Session acceptance cleared. No approval is retained.'),
        findsOneWidget,
      );
      expect(requests, requestsAfterAccept);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('release failure clears consent and explains why', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    try {
      const terms = 'Synthetic license body';
      installFixture(terms, releaseFails: true);
      await openAndroid(tester);

      await tester.tap(reviewButton());
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('accept-model-terms')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('model-session-active')), findsNothing);
      expect(find.byKey(const ValueKey('verify-model-files')), findsNothing);
      expect(
        find.text(
          'Temporary folder access could not be released. '
          'Session acceptance was cleared.',
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
