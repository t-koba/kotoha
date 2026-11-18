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
      if (await _backend.read(_stagingName) == null) return null;
    } catch (_) {
      throw const DraftFileStoreException(DraftFileFailure.read);
    }
    throw const DraftFileStoreException(DraftFileFailure.savePending);
  }

  /// Explicitly removes a pending staging file so a store wedged by an
  /// interrupted save can be reopened or saved again. Never touches committed
  /// bytes. The caller must decide the pending bytes are not worth recovering;
  /// [load] never discards them on its own.
  Future<void> discardPending() async {
    try {
      await _backend.removeStaging(_stagingName);
    } catch (_) {
      throw const DraftFileStoreException(DraftFileFailure.discard);
    }
  }

  Future<void> save(Uint8List envelope) async {
    if (envelope.isEmpty) {
      throw const DraftFileStoreException(DraftFileFailure.stage);
    }
    try {
      await _backend.writeStaging(_stagingName, Uint8List.fromList(envelope));
    } catch (error) {
      if (error is DraftFileStoreException) {
        if (error.failure == DraftFileFailure.savePending) {
          throw const DraftFileStoreException(DraftFileFailure.savePending);
        }
        if (error._stagingCreated) {
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
  }
}
