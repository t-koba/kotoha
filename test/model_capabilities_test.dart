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

/// A resource-needs subclass whose reported basis can change after
/// construction, so the resolver cannot rely on the caller's object staying
/// still.
class _MutableBasisResources extends DeclaredResourceNeeds {
  _MutableBasisResources(this.backingBasis)
    : super(
        storageBytes: 32,
        peakHostBytes: 0,
        peakAcceleratorBytes: 0,
        basis: 'declared',
        conditions: 'synthetic',
      );

  String backingBasis;

  @override
  String get basis => backingBasis;
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

  test('resolver snapshots mutable caller declarations at construction', () {
    final routes = <DeclaredRoute>[
      const DeclaredRoute(
        source: 'de',
        target: 'ar',
        evidence: DeclaredRouteEvidence.user,
      ),
    ];
    final requiredCapabilities = <String>['translation.text'];
    final resources = _MutableBasisResources('declared');
    final declared = DeclaredModelCapabilities(
      modelId: 'synthetic-translation',
      engineId: 'local.engine',
      adapterId: 'local.adapter',
      tasks: [
        DeclaredTaskCapability(
          id: 'translation.text',
          inputTypes: ['text'],
          outputTypes: ['translations'],
          sourceLanguages: ['de', 'ar'],
          targetLanguages: ['ar', 'de'],
          scripts: ['Latn', 'Arab'],
          routes: routes,
        ),
      ],
      requiredCapabilities: requiredCapabilities,
      resources: resources,
    );
    final resolver = CapabilityResolver(declared);

    // Before the caller mutates anything: the extra route and requirement do
    // not exist, while the declared ones do (case-insensitively for routes).
    expect(resolver.declaresRoute('translation.text', 'fr', 'ar'), isFalse);
    expect(resolver.declaresRoute('translation.text', 'DE', 'ar'), isTrue);
    expect(resolver.routeEvidence('translation.text', 'fr', 'ar'), isNull);
    expect(
      resolver.routeEvidence('translation.text', 'DE', 'ar'),
      DeclaredRouteEvidence.user,
    );
    expect(resolver.requiresCapability('ocr.text'), isFalse);
    expect(resolver.requiresCapability('translation.text'), isTrue);
    expect(resolver.routesFor('translation.text'), hasLength(1));
    expect(resolver.resourcesAreMeasured, isFalse);

    routes.add(
      const DeclaredRoute(
        source: 'fr',
        target: 'ar',
        evidence: DeclaredRouteEvidence.provider,
      ),
    );
    requiredCapabilities.add('ocr.text');
    expect(declared.tasks.single.routes, hasLength(2));
    expect(requiredCapabilities, ['translation.text', 'ocr.text']);

    // The resolver still reports the construction-time snapshot.
    expect(resolver.declaresRoute('translation.text', 'fr', 'ar'), isFalse);
    expect(resolver.declaresRoute('translation.text', 'DE', 'ar'), isTrue);
    expect(resolver.routeEvidence('translation.text', 'fr', 'ar'), isNull);
    expect(
      resolver.routeEvidence('translation.text', 'DE', 'ar'),
      DeclaredRouteEvidence.user,
    );
    expect(resolver.requiresCapability('ocr.text'), isFalse);
    expect(resolver.requiresCapability('translation.text'), isTrue);

    // A subclass can change its basis getter after construction; the frozen
    // snapshot must still report the value seen at construction time.
    resources.backingBasis = 'measured';
    expect(resources.basis, 'measured');
    expect(resolver.resourcesAreMeasured, isFalse);
    expect(resolver.capabilities.resources.basis, 'declared');
    expect(resolver.capabilities.resources.runtimeType, DeclaredResourceNeeds);

    final frozen = resolver.capabilities;
    expect(frozen.requiredCapabilities, ['translation.text']);
    final task = frozen.tasks.single;
    expect(task.inputTypes, ['text']);
    expect(task.outputTypes, ['translations']);
    expect(task.sourceLanguages, ['de', 'ar']);
    expect(task.targetLanguages, ['ar', 'de']);
    expect(task.scripts, ['Latn', 'Arab']);
    expect(
      task.routes.map((route) => [route.source, route.target, route.evidence]),
      [
        ['de', 'ar', DeclaredRouteEvidence.user],
      ],
    );
    final exposedRoutes = resolver.routesFor('translation.text');
    expect(
      exposedRoutes.map(
        (route) => [route.source, route.target, route.evidence],
      ),
      [
        ['de', 'ar', DeclaredRouteEvidence.user],
      ],
    );

    // Every nested list exposed through the resolver is frozen.
    final mutations = <void Function()>[
      () => frozen.tasks.add(task),
      () => frozen.requiredCapabilities.add('ocr.text'),
      () => task.inputTypes.add('unexpected'),
      () => task.outputTypes.add('unexpected'),
      () => task.sourceLanguages.add('unexpected'),
      () => task.targetLanguages.add('unexpected'),
      () => task.scripts.add('unexpected'),
      () => task.routes.add(exposedRoutes.first),
      () => exposedRoutes.add(exposedRoutes.first),
    ];
    for (final mutation in mutations) {
      expect(mutation, throwsA(isA<UnsupportedError>()));
    }
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
