/// Pure, fail-closed reporting of capability declarations in a validated model
/// manifest.
///
/// Everything in this library is MANIFEST-DECLARED only: not verified support,
/// availability or quality. A matching digest or a declared route proves
/// nothing about origin, authenticity, licensing or runtime capability.
library;

/// Route evidence labels as declared by a manifest.
enum DeclaredRouteEvidence { provider, evaluation, user }

/// Parses a declared evidence label; unknown values fail closed (null).
DeclaredRouteEvidence? parseDeclaredRouteEvidence(String value) =>
    switch (value) {
      'provider' => DeclaredRouteEvidence.provider,
      'evaluation' => DeclaredRouteEvidence.evaluation,
      'user' => DeclaredRouteEvidence.user,
      _ => null,
    };

/// A route declared by the manifest, with its declared evidence provenance.
class DeclaredRoute {
  const DeclaredRoute({
    required this.source,
    required this.target,
    required this.evidence,
    this.evidenceRef,
  });

  /// Lowercase source language tag as declared.
  final String source;

  /// Lowercase target language tag as declared.
  final String target;

  /// Evidence label as declared; never upgraded to measured support.
  final DeclaredRouteEvidence evidence;

  /// Evidence reference as declared, when present.
  final String? evidenceRef;
}

/// A task capability declared by the manifest.
class DeclaredTaskCapability {
  const DeclaredTaskCapability({
    required this.id,
    required this.inputTypes,
    required this.outputTypes,
    required this.sourceLanguages,
    required this.targetLanguages,
    required this.scripts,
    required this.routes,
  });

  final String id;
  final List<String> inputTypes;
  final List<String> outputTypes;

  /// Lowercase language tags as declared; membership alone is not a route.
  final List<String> sourceLanguages;
  final List<String> targetLanguages;
  final List<String> scripts;

  /// Declared routes only.
  final List<DeclaredRoute> routes;
}

/// Resource needs as declared by the manifest.
class DeclaredResourceNeeds {
  const DeclaredResourceNeeds({
    required this.storageBytes,
    required this.peakHostBytes,
    required this.peakAcceleratorBytes,
    required this.basis,
    required this.conditions,
  });

  final int storageBytes;
  final int peakHostBytes;
  final int peakAcceleratorBytes;

  /// Resource basis as declared; only the literal 'measured' is reported as such.
  final String basis;
  final String conditions;
}

/// Declared capability snapshot of a validated manifest.
class DeclaredModelCapabilities {
  const DeclaredModelCapabilities({
    required this.modelId,
    required this.engineId,
    required this.adapterId,
    required this.tasks,
    required this.requiredCapabilities,
    required this.resources,
  });

  final String modelId;
  final String engineId;
  final String adapterId;
  final List<DeclaredTaskCapability> tasks;
  final List<String> requiredCapabilities;
  final DeclaredResourceNeeds resources;

  /// A fail-closed empty declaration: no tasks, capabilities or routes.
  static const DeclaredModelCapabilities empty = DeclaredModelCapabilities(
    modelId: '',
    engineId: '',
    adapterId: '',
    tasks: [],
    requiredCapabilities: [],
    resources: DeclaredResourceNeeds(
      storageBytes: 0,
      peakHostBytes: 0,
      peakAcceleratorBytes: 0,
      basis: 'declared',
      conditions: '',
    ),
  );
}

/// Pure queries over declared capability data; no runtime lookup or inference.
class CapabilityResolver {
  CapabilityResolver(DeclaredModelCapabilities capabilities)
    : capabilities = _freeze(capabilities);

  /// Frozen snapshot of the declarations supplied at construction, so later
  /// caller-side mutation cannot change a decision already made.
  final DeclaredModelCapabilities capabilities;

  static DeclaredModelCapabilities _freeze(DeclaredModelCapabilities value) =>
      DeclaredModelCapabilities(
        modelId: value.modelId,
        engineId: value.engineId,
        adapterId: value.adapterId,
        tasks: List<DeclaredTaskCapability>.unmodifiable(
          value.tasks.map(_freezeTask),
        ),
        requiredCapabilities: List<String>.unmodifiable(
          value.requiredCapabilities,
        ),
        resources: DeclaredResourceNeeds(
          storageBytes: value.resources.storageBytes,
          peakHostBytes: value.resources.peakHostBytes,
          peakAcceleratorBytes: value.resources.peakAcceleratorBytes,
          basis: value.resources.basis,
          conditions: value.resources.conditions,
        ),
      );

  static DeclaredTaskCapability _freezeTask(DeclaredTaskCapability value) =>
      DeclaredTaskCapability(
        id: value.id,
        inputTypes: List<String>.unmodifiable(value.inputTypes),
        outputTypes: List<String>.unmodifiable(value.outputTypes),
        sourceLanguages: List<String>.unmodifiable(value.sourceLanguages),
        targetLanguages: List<String>.unmodifiable(value.targetLanguages),
        scripts: List<String>.unmodifiable(value.scripts),
        routes: List<DeclaredRoute>.unmodifiable(
          value.routes.map(
            (route) => DeclaredRoute(
              source: route.source,
              target: route.target,
              evidence: route.evidence,
              evidenceRef: route.evidenceRef,
            ),
          ),
        ),
      );

  /// Ids of declared tasks (unmodifiable).
  List<String> get capabilityIds =>
      List<String>.unmodifiable(capabilities.tasks.map((task) => task.id));

  /// Exact declared task id, else null.
  DeclaredTaskCapability? capability(String id) {
    for (final task in capabilities.tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  bool hasCapability(String id) => capability(id) != null;

  /// Whether the exact pair is a declared route; tags compare case-insensitively
  /// and list membership is not a route.
  bool declaresRoute(String capabilityId, String source, String target) =>
      _route(capabilityId, source, target) != null;

  /// Evidence of an exact declared route, else null; provider is never elevated.
  DeclaredRouteEvidence? routeEvidence(
    String capabilityId,
    String source,
    String target,
  ) => _route(capabilityId, source, target)?.evidence;

  /// Declared routes for a task (unmodifiable; empty if the id is unknown).
  List<DeclaredRoute> routesFor(String capabilityId) =>
      List<DeclaredRoute>.unmodifiable(
        capability(capabilityId)?.routes ?? const <DeclaredRoute>[],
      );

  bool requiresCapability(String id) =>
      capabilities.requiredCapabilities.contains(id);

  /// True only when the declared resource basis is literally 'measured'.
  bool get resourcesAreMeasured => capabilities.resources.basis == 'measured';

  DeclaredRoute? _route(String capabilityId, String source, String target) {
    final task = capability(capabilityId);
    if (task == null) return null;
    final from = source.toLowerCase();
    final to = target.toLowerCase();
    for (final route in task.routes) {
      if (route.source.toLowerCase() == from &&
          route.target.toLowerCase() == to) {
        return route;
      }
    }
    return null;
  }
}
