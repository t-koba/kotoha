import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/execution_plan.dart';
import 'package:kotoha/model_capabilities.dart';
import 'package:kotoha/model_terms_import.dart';

class _Reader implements PackageReader {
  _Reader(this.files);
  final Map<String, Uint8List> files;

  @override
  Future<Uint8List?> readDirectoryFile(String path, int maxBytes) async =>
      files[path];
}

Future<EphemeralModelAuthorization> _acceptExampleManifest() async {
  final reader = _Reader({
    'model_manifest.json': File('design/examples/model_manifest.json')
        .readAsBytesSync(),
    'terms.txt': Uint8List.fromList(utf8.encode('synthetic-terms')),
  });
  final authorization = await const ModelTermsImport().run(
    reader,
    (review) async => true,
  );
  expect(authorization, isNotNull);
  return authorization!;
}

PlanRequest _request(String source, String target) => PlanRequest(
  inputType: 'text',
  outputType: 'translations',
  sourceLanguage: source,
  targetLanguage: target,
  storageBudgetBytes: 32,
  hostBudgetBytes: 0,
  acceleratorBudgetBytes: 0,
);

void main() {
  test(
    'accepted review retains manifest-declared capabilities in session',
    () async {
      final authorization = await _acceptExampleManifest();
      final declared = authorization.capabilities;

      expect(declared.modelId, 'synthetic-translation');
      expect(declared.engineId, 'local.engine');
      expect(declared.adapterId, 'local.adapter');
      expect(declared.requiredCapabilities, ['translation.text']);
      expect(declared.tasks.single.id, 'translation.text');
      expect(
        declared.tasks.single.routes.map(
          (route) => [route.source, route.target],
        ),
        [
          ['de', 'ar'],
          ['ar', 'de'],
        ],
      );
      // Declared resource numbers are declarations, never measured values.
      expect(CapabilityResolver(declared).resourcesAreMeasured, isFalse);
    },
  );

  test('retained declarations drive declaration-level eligibility', () async {
    final declared = (await _acceptExampleManifest()).capabilities;

    final eligible = evaluateDeclaredEligibility(
      _request('de', 'ar'),
      declared,
      'translation.text',
    );
    expect(eligible.eligible, isTrue);

    final undeclared = evaluateDeclaredEligibility(
      _request('en', 'ja'),
      declared,
      'translation.text',
    );
    expect(undeclared.route, isTrue);

    final unknown = evaluateDeclaredEligibility(
      _request('de', 'ar'),
      declared,
      'other.capability',
    );
    expect(unknown.unknownTask, isTrue);
  });

  test(
    'authorization without capabilities fails closed as empty declarations',
    () {
      const authorization = EphemeralModelAuthorization(
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(authorization.capabilities.tasks, isEmpty);
      final result = evaluateDeclaredEligibility(
        _request('de', 'ar'),
        authorization.capabilities,
        'translation.text',
      );
      expect(result.unknownTask, isTrue);
      expect(result.eligible, isFalse);
    },
  );
}
