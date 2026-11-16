import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Writes one explicitly exported translation as UTF-8 to the selected path.
///
/// Bytes are staged beside the destination before replacement, so a failed
/// staging write cannot truncate an existing export. POSIX staging directories
/// use mode 0700; inherited ACL handling is platform- and destination-specific.
/// Existing files retain POSIX access permissions (including Linux access ACLs),
/// macOS ACLs, or Windows DACLs. Metadata-preservation failures abort without
/// fallback. This is not a durability or concurrency guarantee, nor a promise
/// to preserve all file metadata.
Future<void> exportTextDocument(String path, String text) =>
    _exportTextDocument(path, text, (_, sink, bytes) async {
      await sink.writeFrom(bytes);
    });

typedef _MkdtempNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _MkdtempDart = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _ChmodNative = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodDart = int Function(Pointer<Utf8>, int);
typedef _ChownNative = Int32 Function(Pointer<Utf8>, Uint32, Uint32);
typedef _ChownDart = int Function(Pointer<Utf8>, int, int);
typedef _StatxNative = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Int32,
  Uint32,
  Pointer<_LinuxStatx>,
);
typedef _StatxDart = int Function(
  int,
  Pointer<Utf8>,
  int,
  int,
  Pointer<_LinuxStatx>,
);
typedef _GetxattrNative = IntPtr Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  UintPtr,
);
typedef _GetxattrDart = int Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  int,
);
typedef _SetxattrNative = Int32 Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  UintPtr,
  Int32,
);
typedef _SetxattrDart = int Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  int,
  int,
);
typedef _RemovexattrNative = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _RemovexattrDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _ErrnoNative = Pointer<Int32> Function();
typedef _ErrnoDart = Pointer<Int32> Function();
typedef _StatNative = Int32 Function(Pointer<Utf8>, Pointer<_DarwinStat>);
typedef _StatDart = int Function(Pointer<Utf8>, Pointer<_DarwinStat>);
typedef _AclGetFileNative = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _AclGetFileDart = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _AclSetFileNative = Int32 Function(Pointer<Utf8>, Int32, Pointer<Void>);
typedef _AclSetFileDart = int Function(Pointer<Utf8>, int, Pointer<Void>);
typedef _AclDeleteFileNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _AclDeleteFileDart = int Function(Pointer<Utf8>, int);
typedef _AclFreeNative = Int32 Function(Pointer<Void>);
typedef _AclFreeDart = int Function(Pointer<Void>);
typedef _ReplaceFileNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _ReplaceFileDart = int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _LastErrorNative = Uint32 Function();
typedef _LastErrorDart = int Function();
typedef _GetNamedSecurityNative = Uint32 Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
);
typedef _GetNamedSecurityDart = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
);
typedef _SetNamedSecurityNative = Uint32 Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _SetNamedSecurityDart = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void>);

// Darwin's 64-bit-inode struct stat prefix is shared by macOS arm64 and
// x86_64's stat$INODE64 symbol. Only mode, uid, and gid are read.
final class _DarwinStat extends Struct {
  @Int32()
  external int device;
  @Uint16()
  external int mode;
  @Uint16()
  external int linkCount;
  @Uint64()
  external int inode;
  @Uint32()
  external int uid;
  @Uint32()
  external int gid;
  @Int32()
  external int deviceType;
  @Array(116)
  external Array<Uint8> remaining;
}

// Linux UAPI statx has a fixed, architecture-independent 256-byte layout.
// Only ownership and mode are requested; the remaining fields are unused.
final class _LinuxStatx extends Struct {
  @Uint32()
  external int mask;
  @Uint32()
  external int blockSize;
  @Uint64()
  external int attributes;
  @Uint32()
  external int linkCount;
  @Uint32()
  external int uid;
  @Uint32()
  external int gid;
  @Uint16()
  external int mode;
  @Array(226)
  external Array<Uint8> remaining;
}

@visibleForTesting
Future<void> exportTextDocumentWithStagedWriter(
  String path,
  String text,
  Future<void> Function(File file, RandomAccessFile sink, List<int> bytes)
  writeStagedFile,
) => _exportTextDocument(path, text, writeStagedFile);

Directory _createStagingDirectory(Directory parent) {
  // Called only on POSIX. All native lookups in this file are lazy and occur
  // inside their platform branch, including when imported on another OS.
  final mkdtemp = DynamicLibrary.process()
      .lookupFunction<_MkdtempNative, _MkdtempDart>('mkdtemp');
  // POSIX mkdtemp creates mode 0700 atomically, before any plaintext exists.
  final template =
      '${parent.path}${Platform.pathSeparator}.kotoha-export-XXXXXX';
  return using((arena) {
    final created = mkdtemp(template.toNativeUtf8(allocator: arena));
    if (created == nullptr) {
      throw FileSystemException(
        'Could not create private export staging directory',
        parent.path,
      );
    }
    final directory = Directory(created.toDartString());
    try {
      if (Platform.isLinux) {
        // Linux default ACL inheritance can override mkdtemp's requested mode.
        // Restrict the access ACL mask before any child file can hold plaintext;
        // the directory's inherited default ACL remains for new-file policy.
        final chmod = DynamicLibrary.process()
            .lookupFunction<_ChmodNative, _ChmodDart>('chmod');
        if (chmod(directory.path.toNativeUtf8(allocator: arena), 0x1c0) != 0) {
          throw FileSystemException(
            'Could not secure private export staging directory',
            directory.path,
          );
        }
      }
      if ((directory.statSync().mode & 0x1ff) != 0x1c0) {
        throw FileSystemException(
          'Could not secure private export staging directory',
          directory.path,
        );
      }
      return directory;
    } catch (_) {
      if (directory.existsSync()) directory.deleteSync();
      rethrow;
    }
  });
}

void _preserveWindowsStagingAcl(File destination, File stagedFile) {
  // Copy the existing file DACL onto the empty stage before writing plaintext.
  // Protect it from inheritance, so the selected parent cannot widen access.
  final advapi = DynamicLibrary.open('advapi32.dll');
  final getSecurity = advapi
      .lookupFunction<_GetNamedSecurityNative, _GetNamedSecurityDart>(
        'GetNamedSecurityInfoW',
      );
  final setSecurity = advapi
      .lookupFunction<_SetNamedSecurityNative, _SetNamedSecurityDart>(
        'SetNamedSecurityInfoW',
      );
  final localFree = DynamicLibrary.open('kernel32.dll')
      .lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
  using((arena) {
    final owner = arena<Pointer<Void>>()..value = nullptr;
    final group = arena<Pointer<Void>>()..value = nullptr;
    final dacl = arena<Pointer<Void>>()..value = nullptr;
    final sacl = arena<Pointer<Void>>()..value = nullptr;
    final descriptor = arena<Pointer<Void>>()..value = nullptr;
    const fileObject = 1; // SE_FILE_OBJECT
    const daclInformation = 0x4; // DACL_SECURITY_INFORMATION
    try {
      final getResult = getSecurity(
        destination.path.toNativeUtf16(allocator: arena),
        fileObject,
        daclInformation,
        owner,
        group,
        dacl,
        sacl,
        descriptor,
      );
      if (getResult != 0) {
        throw FileSystemException(
          'Could not read export destination DACL',
          destination.path,
          OSError('GetNamedSecurityInfoW failed', getResult),
        );
      }
      const protectedDacl = 0x80000000;
      final setResult = setSecurity(
        stagedFile.path.toNativeUtf16(allocator: arena),
        fileObject,
        daclInformation | protectedDacl,
        nullptr,
        nullptr,
        dacl.value,
        nullptr,
      );
      if (setResult != 0) {
        throw FileSystemException(
          'Could not secure staged export with destination DACL',
          stagedFile.path,
          OSError('SetNamedSecurityInfoW failed', setResult),
        );
      }
    } finally {
      if (descriptor.value != nullptr) localFree(descriptor.value);
    }
  });
}

void _preserveLinuxAccess(File destination, File stagedFile) {
  final libc = DynamicLibrary.process();
  final statx = libc.lookupFunction<_StatxNative, _StatxDart>('statx');
  final chown = libc.lookupFunction<_ChownNative, _ChownDart>('chown');
  final chmod = libc.lookupFunction<_ChmodNative, _ChmodDart>('chmod');
  final getxattr = libc.lookupFunction<_GetxattrNative, _GetxattrDart>(
    'getxattr',
  );
  final setxattr = libc.lookupFunction<_SetxattrNative, _SetxattrDart>(
    'setxattr',
  );
  final removexattr = libc.lookupFunction<_RemovexattrNative, _RemovexattrDart>(
    'removexattr',
  );
  final errno = libc.lookupFunction<_ErrnoNative, _ErrnoDart>(
    '__errno_location',
  );
  Never fail() => throw FileSystemException(
    'Could not preserve export access permissions',
    destination.path,
    OSError('POSIX metadata operation failed', errno().value),
  );
  using((arena) {
    final source = destination.path.toNativeUtf8(allocator: arena);
    final target = stagedFile.path.toNativeUtf8(allocator: arena);
    final stat = arena<_LinuxStatx>();
    const accessMask = 0x1a; // STATX_MODE | STATX_UID | STATX_GID
    if (statx(-100, source, 0, accessMask, stat) != 0) fail(); // AT_FDCWD
    if (stat.ref.mask & accessMask != accessMask) {
      throw FileSystemException(
        'Missing export ownership/mode',
        destination.path,
      );
    }
    // Ownership determines which mode/ACL entries apply. Do not silently
    // replace another owner's file with one owned by the exporting process.
    if (chown(target, stat.ref.uid, stat.ref.gid) != 0) fail();
    if (chmod(target, stat.ref.mode & 0x1ff) != 0) fail();

    final name = 'system.posix_acl_access'.toNativeUtf8(allocator: arena);
    final size = getxattr(source, name, nullptr, 0);
    if (size < 0) {
      // Only ENODATA establishes absence. Unsupported ACL operations fail
      // closed too, rather than assuming there is no protection to preserve.
      if (errno().value != 61) fail();
      // Discard an ACL inherited by staging, rather than granting its named
      // users access when the original file had no such ACL.
      if (removexattr(target, name) != 0 && errno().value != 61) {
        fail();
      }
    } else {
      final acl = arena<Uint8>(size);
      final read = getxattr(source, name, acl.cast(), size);
      if (read < 0) fail();
      if (setxattr(target, name, acl.cast(), read, 0) != 0) fail();
    }
  });
}

void _deleteMacAclIfPresent(File file) {
  final libc = DynamicLibrary.process();
  final getAcl = libc.lookupFunction<_AclGetFileNative, _AclGetFileDart>(
    'acl_get_file',
  );
  final deleteAcl = libc
      .lookupFunction<_AclDeleteFileNative, _AclDeleteFileDart>(
        'acl_delete_file_np',
      );
  final freeAcl = libc.lookupFunction<_AclFreeNative, _AclFreeDart>('acl_free');
  final errno = libc.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  using((arena) {
    final path = file.path.toNativeUtf8(allocator: arena);
    const extendedAcl = 0x100; // ACL_TYPE_EXTENDED
    errno().value = 0;
    final acl = getAcl(path, extendedAcl);
    if (acl == nullptr) {
      final error = errno().value;
      if (error == 2) {
        // ENOENT: the confirmed stage has no extended ACL.
        return;
      }
      throw FileSystemException(
        'Could not inspect staged export ACL',
        file.path,
        OSError('acl_get_file failed', error),
      );
    }
    try {
      errno().value = 0;
      if (deleteAcl(path, extendedAcl) != 0) {
        throw FileSystemException(
          'Could not clear inherited staged export ACL',
          file.path,
          OSError('acl_delete_file_np failed', errno().value),
        );
      }
    } finally {
      freeAcl(acl);
    }
  });
}

void _prepareMacStageForWrite(File stagedFile) {
  // Strip ACLs inherited from the selected parent before opening a writable
  // handle. No plaintext exists yet; _preserveMacAccess installs the target
  // file's policy on that handle's path before any bytes are written.
  _deleteMacAclIfPresent(stagedFile);
  final libc = DynamicLibrary.process();
  final chmod = libc.lookupFunction<_ChmodNative, _ChmodDart>('chmod');
  final errno = libc.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  using((arena) {
    final path = stagedFile.path.toNativeUtf8(allocator: arena);
    if (chmod(path, 0x180) != 0) {
      throw FileSystemException(
        'Could not secure staged export for writing',
        stagedFile.path,
        OSError('chmod failed', errno().value),
      );
    }
  });
}

void _preserveMacAccess(File destination, File stagedFile) {
  // stat and acl_get_file inspect metadata without opening file data. The ACL
  // API requires read-security permission; if it is denied, fail before writes.
  final libc = DynamicLibrary.process();
  final abi = Abi.current();
  final statSymbol = switch (abi) {
    Abi.macosX64 => r'stat$INODE64',
    Abi.macosArm64 => 'stat',
    _ => throw UnsupportedError('Unsupported macOS stat ABI: $abi'),
  };
  final stat = libc.lookupFunction<_StatNative, _StatDart>(statSymbol);
  final chown = libc.lookupFunction<_ChownNative, _ChownDart>('chown');
  final chmod = libc.lookupFunction<_ChmodNative, _ChmodDart>('chmod');
  final getAcl = libc.lookupFunction<_AclGetFileNative, _AclGetFileDart>(
    'acl_get_file',
  );
  final setAcl = libc.lookupFunction<_AclSetFileNative, _AclSetFileDart>(
    'acl_set_file',
  );
  final freeAcl = libc.lookupFunction<_AclFreeNative, _AclFreeDart>('acl_free');
  final errno = libc.lookupFunction<_ErrnoNative, _ErrnoDart>('__error');
  using((arena) {
    final sourcePath = destination.path.toNativeUtf8(allocator: arena);
    final stagedPath = stagedFile.path.toNativeUtf8(allocator: arena);
    final metadata = arena<_DarwinStat>();
    if (stat(sourcePath, metadata) != 0) {
      final error = errno().value;
      throw FileSystemException(
        'Could not inspect export ownership and mode',
        destination.path,
        OSError('stat failed', error),
      );
    }
    if (chown(stagedPath, metadata.ref.uid, metadata.ref.gid) != 0) {
      final error = errno().value;
      throw FileSystemException(
        'Could not preserve export ownership',
        destination.path,
        OSError('chown failed', error),
      );
    }
    if (chmod(stagedPath, metadata.ref.mode & 0xfff) != 0) {
      final error = errno().value;
      throw FileSystemException(
        'Could not preserve export mode',
        destination.path,
        OSError('chmod failed', error),
      );
    }

    const extendedAcl = 0x100; // ACL_TYPE_EXTENDED
    final acl = getAcl(sourcePath, extendedAcl);
    if (acl == nullptr) {
      final error = errno().value;
      if (error != 2) {
        throw FileSystemException(
          'Could not read export access-control list',
          destination.path,
          OSError('acl_get_file failed', error),
        );
      }
      // ENOENT denotes no extended ACL after stat confirmed the source exists.
      // Remove any ACL inherited by staging; absence is checked before deletion.
      _deleteMacAclIfPresent(stagedFile);
      return;
    }
    try {
      if (setAcl(stagedPath, extendedAcl, acl) != 0) {
        final error = errno().value;
        throw FileSystemException(
          'Could not preserve export access-control list',
          destination.path,
          OSError('acl_set_file failed', error),
        );
      }
    } finally {
      freeAcl(acl);
    }
  });
}

void _replaceWindowsFile(File destination, File stagedFile) {
  // ReplaceFileW preserves the replaced file's DACL; MoveFileExW (File.rename)
  // does not. Flags=0 deliberately excludes IGNORE_MERGE_ERRORS and
  // IGNORE_ACL_ERRORS. This native behavior still needs a Windows test run.
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final replaceFile = kernel32
      .lookupFunction<_ReplaceFileNative, _ReplaceFileDart>('ReplaceFileW');
  final lastError = kernel32.lookupFunction<_LastErrorNative, _LastErrorDart>(
    'GetLastError',
  );
  using((arena) {
    if (replaceFile(
          destination.path.toNativeUtf16(allocator: arena),
          stagedFile.path.toNativeUtf16(allocator: arena),
          nullptr,
          0,
          nullptr,
          nullptr,
        ) ==
        0) {
      throw FileSystemException(
        'Could not replace export while preserving its DACL',
        destination.path,
        OSError('ReplaceFileW failed', lastError()),
      );
    }
  });
}

Future<void> _commit(File destination, File stagedFile) async {
  final type = await FileSystemEntity.type(destination.path);
  if (type == FileSystemEntityType.file) {
    if (Platform.isWindows) {
      _replaceWindowsFile(destination, stagedFile);
      return;
    } else if (Platform.isLinux) {
      _preserveLinuxAccess(destination, stagedFile);
    } else if (!Platform.isMacOS) {
      throw FileSystemException(
        'Preserving export access permissions is unsupported on this platform',
        destination.path,
      );
    }
  } else if (type != FileSystemEntityType.notFound) {
    throw FileSystemException(
      'Export destination is not a file',
      destination.path,
    );
  }
  await stagedFile.rename(destination.path);
}

Future<void> _exportTextDocument(
  String path,
  String text,
  Future<void> Function(File file, RandomAccessFile sink, List<int> bytes)
  writeStagedFile,
) async {
  final bytes = utf8.encode(text);
  final selectedPath = File(path);
  final selectedType = await FileSystemEntity.type(
    selectedPath.path,
    followLinks: false,
  );
  // Preserve writeAsBytes' behavior for an existing final symlink: update its
  // target rather than replacing the link itself. A dangling link fails closed.
  final destination = selectedType == FileSystemEntityType.link
      ? File(await selectedPath.resolveSymbolicLinks())
      : selectedPath;
  final destinationType = await FileSystemEntity.type(destination.path);
  if (destinationType != FileSystemEntityType.file &&
      destinationType != FileSystemEntityType.notFound) {
    throw FileSystemException('Export destination is not a file', path);
  }
  final existing = destinationType == FileSystemEntityType.file;
  final stagingDirectory = Platform.isWindows
      ? await destination.parent.createTemp('.kotoha-export-')
      : _createStagingDirectory(destination.parent);
  final stagedFile = File(
    '${stagingDirectory.path}${Platform.pathSeparator}translation.txt',
  );
  var stagedFileCreated = false;
  try {
    await stagedFile.create(exclusive: true);
    stagedFileCreated = true;
    if (Platform.isMacOS && existing) {
      _prepareMacStageForWrite(stagedFile);
    }
    final sink = await stagedFile.open(mode: FileMode.writeOnly);
    try {
      if (Platform.isWindows && existing) {
        _preserveWindowsStagingAcl(destination, stagedFile);
      } else if (Platform.isMacOS && existing) {
        _preserveMacAccess(destination, stagedFile);
      }
      await writeStagedFile(stagedFile, sink, bytes);
      await sink.flush();
    } finally {
      await sink.close();
    }
    await _commit(destination, stagedFile);
    stagedFileCreated = false;
  } finally {
    if (stagedFileCreated && await stagedFile.exists()) {
      await stagedFile.delete();
    }
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete();
    }
  }
}
