import 'model_terms_import.dart';

/// Failures are reported without any path, provider name, digest or content
/// bytes.
enum ModelRegistryFailure {
  invalidBinding,
  duplicate,
  notInstalled,
  inUse,
  invalidLease,
}

/// Deliberately excludes paths, provider names, digests and content bytes.
class ModelRegistryException implements Exception {
  const ModelRegistryException(this.failure);

  final ModelRegistryFailure failure;

  @override
  String toString() => 'ModelRegistryException(${failure.name})';
}

/// An immutable digest binding created by [ModelRegistry.install] from an
/// already-accepted review.
///
/// These digests are not verified support, availability or quality claims.
/// Hashes prove identity only: they prove nothing about origin, authenticity,
/// signature/provenance or license approval. Only a registry constructs
/// records; each declared file is copied into a plain record whose fields are
/// read once at install time, and those files are never opened here.
class InstalledModel {
  InstalledModel._(
    this.manifestDigest,
    this.termsDigest,
    List<DeclaredModelFile> declaredFiles,
  ) : _declaredFiles = List<DeclaredModelFile>.unmodifiable(
        declaredFiles.map(
          (file) => DeclaredModelFile(
            path: file.path,
            role: file.role,
            sizeBytes: file.sizeBytes,
            sha256: file.sha256,
          ),
        ),
      );

  final String manifestDigest;
  final String termsDigest;
  final List<DeclaredModelFile> _declaredFiles;

  /// Declared non-terms files, in manifest order, as an unmodifiable list of
  /// plain records frozen at install time.
  List<DeclaredModelFile> get declaredFiles => _declaredFiles;
}

/// A reference to the exact installed content identity used by a job.
///
/// Created only by [ModelRegistry.pin], bound to its issuing registry and to
/// the manifest digest at pin time, independent of later switches.
class ModelLease {
  ModelLease._(this._owner, this.manifestDigest, this._token);

  final ModelRegistry _owner;
  final Object _token;

  /// The exact content identity pinned at lease time.
  final String manifestDigest;
}

/// In-memory retention and switching of digest bindings from accepted reviews.
///
/// Installing, activating, pinning and removing only change this registry's
/// volatile state: no file is read or deleted, no engine is invoked, no
/// network or persistence is used, and no runtime is authorized. A switch
/// target is acceptable only because it was already installed through its own
/// accepted review; no new verification happens here. The previously active
/// binding stays installed so jobs and comparisons can be re-run.
class ModelRegistry {
  static final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');

  final Map<String, InstalledModel> _installed = <String, InstalledModel>{};
  final Map<String, Set<Object>> _leases = <String, Set<Object>>{};
  String? _activeId;

  /// Installed manifest digests in deterministic (sorted) order.
  Iterable<String> get installedIds =>
      List<String>.unmodifiable(_installed.keys.toList()..sort());

  /// The active manifest digest, or null when nothing is active.
  String? get activeId => _activeId;

  /// Records an accepted review's digest binding without reading any content.
  ///
  /// Both digests must be 64 lowercase hex characters. An existing manifest
  /// digest is never silently overwritten.
  void install(EphemeralModelAuthorization authorization) {
    final manifestDigest = authorization.manifestDigest;
    final termsDigest = authorization.termsDigest;
    if (!_digestPattern.hasMatch(manifestDigest) ||
        !_digestPattern.hasMatch(termsDigest)) {
      throw const ModelRegistryException(ModelRegistryFailure.invalidBinding);
    }
    if (_installed.containsKey(manifestDigest)) {
      throw const ModelRegistryException(ModelRegistryFailure.duplicate);
    }
    _installed[manifestDigest] = InstalledModel._(
      manifestDigest,
      termsDigest,
      authorization.declaredFiles,
    );
  }

  /// Returns the immutable binding for [id], or null if it is not installed.
  InstalledModel? lookup(String id) => _installed[id];

  /// Makes an already-installed binding active; the previous one remains
  /// installed for re-runs and comparison.
  void activate(String id) {
    if (!_installed.containsKey(id)) {
      throw const ModelRegistryException(ModelRegistryFailure.notInstalled);
    }
    _activeId = id;
  }

  /// Pins the exact installed content for a job, independently of [activeId].
  ModelLease pin(String id) {
    if (!_installed.containsKey(id)) {
      throw const ModelRegistryException(ModelRegistryFailure.notInstalled);
    }
    final token = Object();
    (_leases[id] ??= <Object>{}).add(token);
    return ModelLease._(this, id, token);
  }

  /// Releases a pin issued by this registry. Double releases and foreign
  /// leases fail closed instead of changing any count.
  void release(ModelLease lease) {
    if (!identical(lease._owner, this)) {
      throw const ModelRegistryException(ModelRegistryFailure.invalidLease);
    }
    final tokens = _leases[lease.manifestDigest];
    if (tokens == null || !tokens.remove(lease._token)) {
      throw const ModelRegistryException(ModelRegistryFailure.invalidLease);
    }
    if (tokens.isEmpty) _leases.remove(lease.manifestDigest);
  }

  /// Number of outstanding pins for [id].
  int leaseCount(String id) => _leases[id]?.length ?? 0;

  /// Forgets an unused binding. No content is deleted here.
  void remove(String id) {
    if (!_installed.containsKey(id)) {
      throw const ModelRegistryException(ModelRegistryFailure.notInstalled);
    }
    if (id == _activeId || leaseCount(id) > 0) {
      throw const ModelRegistryException(ModelRegistryFailure.inUse);
    }
    _installed.remove(id);
  }
}
