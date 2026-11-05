import 'dart:async';
import 'dart:typed_data';

/// Failures never authorize generating a replacement key or resetting storage.
enum KeyStoreFailure {
  unsupportedPlatform,
  location,
  read,
  format,
  protect,
  unprotect,
  create,
  alreadyExists,
  creationPending,
}

/// Deliberately excludes key bytes, native messages and filesystem paths.
class ProtectedKeyStoreException implements Exception {
  const ProtectedKeyStoreException(this.failure, {this.osError});

  final KeyStoreFailure failure;
  final int? osError;

  @override
  String toString() => 'ProtectedKeyStoreException(${failure.name}, $osError)';
}

/// Platform boundary; implementations must never mutate input buffers.
abstract interface class KeyProtector {
  Uint8List protect(Uint8List key);
  Uint8List unprotect(Uint8List ciphertext);
}

/// Storage boundary: null means confirmed absence, not an unreadable file.
abstract interface class ProtectedKeyFile {
  Future<Uint8List?> read();

  /// Publish complete ciphertext without replacing any existing destination.
  Future<void> create(Uint8List ciphertext);
}

/// An opaque-key building block, not a draft store or a backup/recovery policy.
/// There is intentionally no implicit generation, reset, delete or update API.
class ProtectedKeyStore {
  ProtectedKeyStore({required this.file, required this.protector});

  final ProtectedKeyFile file;
  final KeyProtector protector;

  // File-format constant: ASCII KKEY followed by format version 1.
  static const _header = [0x4b, 0x4b, 0x45, 0x59, 1];

  Future<Uint8List?> load() async {
    final bytes = await _checked(KeyStoreFailure.read, file.read);
    if (bytes == null) return null;
    if (bytes.length <= _header.length ||
        !Iterable<int>.generate(_header.length)
            .every((i) => bytes[i] == _header[i])) {
      throw const ProtectedKeyStoreException(KeyStoreFailure.format);
    }
    final key = await _checked(
      KeyStoreFailure.unprotect,
      () => protector.unprotect(Uint8List.sublistView(bytes, _header.length)),
    );
    if (key.isEmpty) {
      throw const ProtectedKeyStoreException(KeyStoreFailure.format);
    }
    return key;
  }

  /// The caller supplies key bytes explicitly. Errors do not imply absence:
  /// after an uncertain create result, load rather than generate another key.
  Future<void> create(Uint8List key) async {
    if (key.isEmpty) {
      throw const ProtectedKeyStoreException(KeyStoreFailure.format);
    }
    final encrypted = await _checked(
      KeyStoreFailure.protect,
      () => protector.protect(Uint8List.fromList(key)),
    );
    if (encrypted.isEmpty) {
      throw const ProtectedKeyStoreException(KeyStoreFailure.protect);
    }
    await _checked(
      KeyStoreFailure.create,
      () => file.create(Uint8List.fromList([..._header, ...encrypted])),
    );
  }

  Future<T> _checked<T>(
    KeyStoreFailure failure,
    FutureOr<T> Function() action,
  ) async {
    try {
      return await action();
    } on ProtectedKeyStoreException {
      rethrow;
    } on Exception {
      throw ProtectedKeyStoreException(failure);
    }
  }
}
