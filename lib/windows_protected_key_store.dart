import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:win32/win32.dart';

import 'protected_key_store.dart';

/// Opens the Windows user-profile store in the app support directory, not in
/// Documents or beside the executable. [directory] is for isolated runtime tests
/// or an explicitly managed private support directory. Inherited profile ACLs
/// are relied upon; this is not protection against other code running as user.
/// No keys or files are created merely by opening the store.
Future<ProtectedKeyStore> openWindowsProtectedKeyStore({
  Directory? directory,
}) async {
  if (!Platform.isWindows) {
    throw const ProtectedKeyStoreException(KeyStoreFailure.unsupportedPlatform);
  }
  try {
    final support = directory ?? await getApplicationSupportDirectory();
    return ProtectedKeyStore(
      file: WindowsProtectedKeyFile(
        File('${support.path}${Platform.pathSeparator}db-key.dpapi'),
      ),
      protector: WindowsDpapiProtector(),
    );
  } on Exception {
    throw const ProtectedKeyStoreException(KeyStoreFailure.location);
  }
}

/// Direct user-scope DPAPI. No CRYPTPROTECT_LOCAL_MACHINE flag, entropy,
/// description or prompt. Imported Win32 DLL bindings are lazy and are only
/// invoked after the platform check, so host-side tests can import this library.
class WindowsDpapiProtector implements KeyProtector {
  @override
  Uint8List protect(Uint8List key) => _transform(key, protect: true);

  @override
  Uint8List unprotect(Uint8List ciphertext) =>
      _transform(ciphertext, protect: false);

  Uint8List _transform(Uint8List bytes, {required bool protect}) {
    if (!Platform.isWindows) {
      throw const ProtectedKeyStoreException(
        KeyStoreFailure.unsupportedPlatform,
      );
    }
    final failure = protect
        ? KeyStoreFailure.protect
        : KeyStoreFailure.unprotect;
    // DATA_BLOB.cbData is a DWORD: this bound is intrinsic to the Win32 ABI.
    if (bytes.isEmpty || bytes.length > 0xffffffff) {
      throw ProtectedKeyStoreException(failure);
    }
    return using((arena) {
      final input = arena<CRYPT_INTEGER_BLOB>();
      final output = arena<CRYPT_INTEGER_BLOB>();
      final buffer = arena<Uint8>(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..cbData = bytes.length
        ..pbData = buffer;
      // Windows dpapi.h protocol flag, not exported by win32 6.4.0.
      const cryptprotectUiForbidden = 0x1;
      try {
        final result = protect
            ? CryptProtectData(
                input,
                null,
                null,
                null,
                cryptprotectUiForbidden,
                output,
              )
            : CryptUnprotectData(
                input,
                null,
                null,
                null,
                cryptprotectUiForbidden,
                output,
              );
        if (!result.value) {
          throw ProtectedKeyStoreException(failure, osError: result.error.code);
        }
        if (output.ref.cbData == 0 || output.ref.pbData == nullptr) {
          throw ProtectedKeyStoreException(failure);
        }
        return Uint8List.fromList(
          output.ref.pbData.asTypedList(output.ref.cbData),
        );
      } finally {
        // Best-effort clearing of native copies, not a claim of managed-heap
        // zeroization. DPAPI allocates its output with LocalAlloc, not calloc.
        buffer.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
        if (output.ref.pbData != nullptr) {
          output.ref.pbData
              .asTypedList(output.ref.cbData)
              .fillRange(0, output.ref.cbData, 0);
          LocalFree(HLOCAL(output.ref.pbData));
        }
      }
    });
  }
}

/// Same-volume staging plus MoveFileEx without REPLACE_EXISTING or COPY_ALLOWED.
/// Competing creators cannot overwrite the committed key. A fixed, exclusive
/// .pending file serializes creation; normal failures remove only this attempt's
/// staging file. A crash before rename can leave .pending, blocking creation
/// until explicit recovery (not provided here); load reports creationPending if
/// no committed key exists. No history, retries, scans or automatic resets.
///
/// Flushed staging + rename avoids publishing partially written ciphertext in
/// normal operation. This is NOT a transaction durable against all power loss,
/// filesystem/filter-driver failures or same-user tampering. Errors after commit
/// can be ambiguous; callers must load, never assume an error means no key.
class WindowsProtectedKeyFile implements ProtectedKeyFile {
  WindowsProtectedKeyFile(this.file);

  final File file;
  File get _pending => File('${file.path}.pending');

  // Windows ERROR_FILE_NOT_FOUND / ERROR_PATH_NOT_FOUND only. exists() would
  // suppress permission errors and conflate them with absence.
  bool _missing(FileSystemException error) =>
      error.osError?.errorCode == 2 || error.osError?.errorCode == 3;

  @override
  Future<Uint8List?> read() async {
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      if (!_missing(error)) {
        throw ProtectedKeyStoreException(
          KeyStoreFailure.read,
          osError: error.osError?.errorCode,
        );
      }
      try {
        await _pending.readAsBytes();
      } on FileSystemException catch (pendingError) {
        if (_missing(pendingError)) return null;
        throw ProtectedKeyStoreException(
          KeyStoreFailure.read,
          osError: pendingError.osError?.errorCode,
        );
      }
      throw const ProtectedKeyStoreException(KeyStoreFailure.creationPending);
    }
  }

  @override
  Future<void> create(Uint8List ciphertext) async {
    if (!Platform.isWindows) {
      throw const ProtectedKeyStoreException(
        KeyStoreFailure.unsupportedPlatform,
      );
    }
    await file.parent.create(recursive: true);
    // Never use Dart File.rename: it is allowed to replace the destination.
    // Exclusive create happens before try/finally: a pre-existing .pending file
    // belongs to someone else and must not be removed, even on permission error.
    try {
      await _pending.create(exclusive: true);
    } on FileSystemException catch (error) {
      throw ProtectedKeyStoreException(
        error.osError?.errorCode == ERROR_FILE_EXISTS ||
                error.osError?.errorCode == ERROR_ALREADY_EXISTS
            ? KeyStoreFailure.creationPending
            : KeyStoreFailure.create,
        osError: error.osError?.errorCode,
      );
    }
    var published = false;
    try {
      await _pending.writeAsBytes(ciphertext, flush: true);
      using((arena) {
        final result = MoveFileEx(
          PCWSTR(_pending.absolute.path.toNativeUtf16(allocator: arena)),
          PCWSTR(file.absolute.path.toNativeUtf16(allocator: arena)),
          MOVEFILE_WRITE_THROUGH,
        );
        if (!result.value) {
          throw ProtectedKeyStoreException(
            result.error == ERROR_ALREADY_EXISTS ||
                    result.error == ERROR_FILE_EXISTS
                ? KeyStoreFailure.alreadyExists
                : KeyStoreFailure.create,
            osError: result.error.code,
          );
        }
      });
      published = true;
    } finally {
      // After rename, another creator may already own a new .pending file.
      if (!published) {
        try {
          await _pending.delete();
        } on FileSystemException catch (error) {
          if (!_missing(error)) {
            throw ProtectedKeyStoreException(
              KeyStoreFailure.create,
              osError: error.osError?.errorCode,
            );
          }
        }
      }
    }
  }
}
