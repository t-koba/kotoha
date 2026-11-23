import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/model_capabilities.dart';
import 'package:kotoha/model_terms_import.dart';

class _ManifestReader implements PackageReader {
  _ManifestReader(this.files);
  final Map<String, Uint8List> files;
  final requests = <String>[];

  @override
  Future<Uint8List?> readDirectoryFile(String path, int maxBytes) async {
    requests.add(path);
    return files[path];
  }
}

Future<VerifiedTerms> reviewExampleManifest() async {
  final reader = _ManifestReader({
    'model_manifest.json': File('design/examples/model_manifest.json')
        .readAsBytesSync(),
    // The example manifest binds this 15-byte terms text by SHA-256.
    'terms.txt': Uint8List.fromList(utf8.encode('synthetic-terms')),
  });
  VerifiedTerms? reviewed;
  final authorization = await const ModelTermsImport().run(reader, (
    value,
  ) async {
    reviewed = value;
    return true;
  });
  expect(authorization, isNotNull);
  expect(reader.requests, ['model_manifest.json', 'terms.txt']);
  return reviewed!;
}

void main() {
  test('example manifest round-trips typed declared capabilities', () async {
    final declared = (await reviewExampleManifest()).capabilities;
    expect(declared.modelId, 'synthetic-translation');
    expect(declared.engineId, 'local.engine');
    expect(declared.adapterId, 'local.adapter');
    expect(declared.requiredCapabilities, ['translation.text']);
    expect(declared.tasks, hasLength(1));

    final task = declared.tasks.single;
    expect(task.id, 'translation.text');
    expect(task.inputTypes, ['text']);
    expect(task.outputTypes, ['translations']);
    expect(task.sourceLanguages, ['de', 'ar']);
    expect(task.targetLanguages, ['ar', 'de']);
    expect(task.scripts, ['Latn', 'Arab']);
    expect(
      task.routes.map(
        (route) => [
          route.source,
          route.target,
          route.evidence,
          route.evidenceRef,
        ],
      ),
      [
        ['de', 'ar', DeclaredRouteEvidence.user, null],
        ['ar', 'de', DeclaredRouteEvidence.user, null],
      ],
    );
    expect(declared.resources.storageBytes, 32);
    expect(declared.resources.peakHostBytes, 0);
    expect(declared.resources.peakAcceleratorBytes, 0);
    expect(declared.resources.basis, 'declared');
    expect(declared.resources.conditions, '検査用の合成値');
  });

  test('resolver reports declarations only and fails closed', () async {
    final resolver = CapabilityResolver(
      (await reviewExampleManifest()).capabilities,
    );

    expect(resolver.capabilityIds, ['translation.text']);
    expect(
      () => resolver.capabilityIds.add('ocr.text'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(resolver.hasCapability('translation.text'), isTrue);
    expect(resolver.hasCapability('ocr.text'), isFalse);
    expect(resolver.capability('translation.text')!.id, 'translation.text');
    expect(resolver.capability('OCR.TEXT'), isNull);

    // Tags compare case-insensitively, but membership in the source and target
    // lists alone is not a declared route.
    expect(resolver.declaresRoute('translation.text', 'DE', 'ar'), isTrue);
    expect(resolver.declaresRoute('translation.text', 'de', 'AR'), isTrue);
    expect(resolver.declaresRoute('translation.text', 'de', 'de'), isFalse);
    expect(resolver.declaresRoute('ocr.text', 'de', 'ar'), isFalse);
    expect(
      resolver.routeEvidence('translation.text', 'DE', 'ar'),
      DeclaredRouteEvidence.user,
    );
    expect(resolver.routeEvidence('translation.text', 'de', 'de'), isNull);
    expect(resolver.routeEvidence('ocr.text', 'de', 'ar'), isNull);

    final routes = resolver.routesFor('translation.text');
    expect(routes, hasLength(2));
    expect(() => routes.add(routes.first), throwsA(isA<UnsupportedError>()));
    expect(resolver.routesFor('ocr.text'), isEmpty);
    expect(
      () => resolver.routesFor('ocr.text').add(routes.first),
      throwsA(isA<UnsupportedError>()),
    );

    expect(resolver.requiresCapability('translation.text'), isTrue);
    expect(resolver.requiresCapability('ocr.text'), isFalse);
    expect(resolver.resourcesAreMeasured, isFalse);
  });

  test('measured basis is the only measured resource report', () async {
    final declared = (await reviewExampleManifest()).capabilities;
    final measured = DeclaredModelCapabilities(
      modelId: declared.modelId,
      engineId: declared.engineId,
      adapterId: declared.adapterId,
      tasks: declared.tasks,
      requiredCapabilities: declared.requiredCapabilities,
      resources: DeclaredResourceNeeds(
        storageBytes: declared.resources.storageBytes,
        peakHostBytes: declared.resources.peakHostBytes,
        peakAcceleratorBytes: declared.resources.peakAcceleratorBytes,
        basis: 'measured',
        conditions: declared.resources.conditions,
      ),
    );
    expect(CapabilityResolver(measured).resourcesAreMeasured, isTrue);
  });

  test('declared route evidence parser fails closed on unknown labels', () {
    expect(
      parseDeclaredRouteEvidence('provider'),
      DeclaredRouteEvidence.provider,
    );
    expect(
      parseDeclaredRouteEvidence('evaluation'),
      DeclaredRouteEvidence.evaluation,
    );
    expect(parseDeclaredRouteEvidence('user'), DeclaredRouteEvidence.user);
    expect(parseDeclaredRouteEvidence('measured'), isNull);
    expect(parseDeclaredRouteEvidence('Provider'), isNull);
    expect(parseDeclaredRouteEvidence(''), isNull);
  });
}
