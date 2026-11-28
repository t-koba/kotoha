import 'dart:typed_data';

enum DraftFileFailure { read, stage, savePending, commit, discard }

/// Deliberately excludes paths, native messages, and key or content bytes.
class DraftFileStoreException implements Exception {
  const DraftFileStoreException(this.failure, {this.osError})
    : _stagingCreated = false;

  /// Backend signal: this write exclusively created staging, then failed.
  const DraftFileStoreException.stagingCreated({this.osError})
    : failure = DraftFileFailure.stage,
      _stagingCreated = true;

  final DraftFileFailure failure;
  final int? osError;
  final bool _stagingCreated;

  @override
  String toString() => 'DraftFileStoreException(${failure.name}, $osError)';
}

/// Platform boundary for all file operations.
abstract interface class DraftFileBackend {
  /// Returns null only for confirmed absence; throws for other I/O failures.
  Future<Uint8List?> read(String name);

  /// Exclusively creates staging and flushes the complete bytes before return.
  /// If staging already exists, leave it untouched and throw a
  /// [DraftFileStoreException] with [DraftFileFailure.savePending]. If the
  /// write fails after creating staging, throw
  /// [DraftFileStoreException.stagingCreated] to let the caller remove it.
  Future<void> writeStaging(String name, Uint8List bytes);

  /// Atomically moves staging over the destination on the same volume.
  /// On failure, the previously committed bytes (or absence) are unchanged.
  Future<void> commitReplace(String stagingName, String name);

  /// Removes staging; absence is not an error.
  Future<void> removeStaging(String name);
}

/// File-commit framing only: stores opaque bytes without parsing them or
/// generating keys. This adapter performs no cryptography or real file I/O.
class DraftFileStore {
  /// Isolate-local owner tokens for active staging operations, keyed by
  /// backend identity (through [Expando]) and staging name. Every store in
  /// this isolate that shares a backend and staging name shares this guard.
  ///
  /// The guarantee stops at this isolate. A real backend must enforce the
  /// same exclusivity across isolates and processes: exclusive staging
  /// creation, and commit or removal bound to the owning writer. This
  /// adapter is file-commit framing only; it enables no persistence,
  /// encryption, platform key-store behavior, or cross-process locking.
  static final Expando<Map<String, Object>> _activeStaging = Expando();

  DraftFileStore({required this._backend, required String name})
    : _name = name,
      _stagingName = '$name.pending';

  final DraftFileBackend _backend;
  final String _name;
  final String _stagingName;

  /// Prefer the committed bytes. Staging alone is not a new or empty store.
  Future<Uint8List?> load() async {
    try {
      final bytes = await _backend.read(_name);
      if (bytes != null) return Uint8List.fromList(bytes);
      final staging = await _backend.read(_stagingName);
      // A save can move staging to committed between the two observations.
      // Recheck the destination before deciding between absence and pending.
      final committed = await _backend.read(_name);
      if (committed != null) return Uint8List.fromList(committed);
      if (staging == null) return null;
    } catch (_) {
      throw const DraftFileStoreException(DraftFileFailure.read);
    }
    throw const DraftFileStoreException(DraftFileFailure.savePending);
  }

  /// Synchronous so callers in one isolate cannot both claim the same
  /// staging: the claim happens before either method reaches its first await.
  Object? _claimStaging() {
    var owners = _activeStaging[_backend];
    if (owners == null) {
      owners = <String, Object>{};
      _activeStaging[_backend] = owners;
    }
    if (owners.containsKey(_stagingName)) return null;
    final owner = Object();
    owners[_stagingName] = owner;
    return owner;
  }

  bool _ownsStaging(Object owner) =>
      identical(_activeStaging[_backend]?[_stagingName], owner);

  void _releaseStaging(Object owner) {
    final owners = _activeStaging[_backend];
    if (owners != null && identical(owners[_stagingName], owner)) {
      owners.remove(_stagingName);
    }
  }

  /// Explicitly removes a pending staging file so a store wedged by an
  /// interrupted save can be reopened or saved again. Never touches committed
  /// bytes. Refuses with [DraftFileFailure.savePending] while a save or
  /// discard in this isolate owns the staging. The caller must decide the
  /// pending bytes are not worth recovering; [load] never discards them on
  /// its own.
  Future<void> discardPending() async {
    final owner = _claimStaging();
    if (owner == null) {
      throw const DraftFileStoreException(DraftFileFailure.savePending);
    }
    try {
      await _backend.removeStaging(_stagingName);
    } catch (_) {
      throw const DraftFileStoreException(DraftFileFailure.discard);
    } finally {
      _releaseStaging(owner);
    }
  }

  /// Claims this store's staging before writing it. A concurrent save or
  /// discard on any store sharing this backend and name is refused with
  /// [DraftFileFailure.savePending] until commit or cleanup finishes.
  Future<void> save(Uint8List envelope) async {
    if (envelope.isEmpty) {
      throw const DraftFileStoreException(DraftFileFailure.stage);
    }
    final owner = _claimStaging();
    if (owner == null) {
      throw const DraftFileStoreException(DraftFileFailure.savePending);
    }
    try {
      try {
        await _backend.writeStaging(_stagingName, Uint8List.fromList(envelope));
      } catch (error) {
        if (error is DraftFileStoreException) {
          if (error.failure == DraftFileFailure.savePending) {
            throw const DraftFileStoreException(DraftFileFailure.savePending);
          }
          // Only the failing save that still owns this staging may clean it
          // up; ownership cannot be assumed from the staging name alone.
          if (error._stagingCreated && _ownsStaging(owner)) {
            try {
              await _backend.removeStaging(_stagingName);
            } catch (_) {
              // Best effort: preserve the original stage failure.
            }
          }
        }
        throw const DraftFileStoreException(DraftFileFailure.stage);
      }
      try {
        await _backend.commitReplace(_stagingName, _name);
      } catch (_) {
        // Leave staging alone after a commit failure; do not infer its state.
        throw const DraftFileStoreException(DraftFileFailure.commit);
      }
    } finally {
      _releaseStaging(owner);
    }
  }
}
