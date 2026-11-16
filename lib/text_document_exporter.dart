import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Writes one explicitly exported translation as UTF-8 to the selected path.
///
/// The bytes are staged beside the destination and renamed into place only
/// after the staging write completes, so a failed staging write cannot truncate
/// an existing export. POSIX staging directories are created owner-only;
/// Windows staging directories inherit the destination parent's ACL.
Future<void> exportTextDocument(String path, String text) =>
    _exportTextDocument(path, text, (file, bytes) => file.writeAsBytes(bytes));

typedef _MkdtempNative = Pointer<Utf8> Function(Pointer<Utf8>);
typedef _MkdtempDart = Pointer<Utf8> Function(Pointer<Utf8>);

final _mkdtemp = DynamicLibrary.process()
    .lookupFunction<_MkdtempNative, _MkdtempDart>('mkdtemp');

@visibleForTesting
Future<void> exportTextDocumentWithStagedWriter(
  String path,
  String text,
  Future<void> Function(File file, List<int> bytes) writeStagedFile,
) => _exportTextDocument(path, text, writeStagedFile);

Directory _createStagingDirectory(Directory parent) {
  if (Platform.isWindows) {
    throw StateError('Use Directory.createTemp on Windows');
  }

  // POSIX mkdtemp creates mode 0700 atomically, before any plaintext exists.
  final template =
      '${parent.path}${Platform.pathSeparator}.kotoha-export-XXXXXX';
  return using((arena) {
    final nativeTemplate = template.toNativeUtf8(allocator: arena);
    final created = _mkdtemp(nativeTemplate);
    if (created == nullptr) {
      throw FileSystemException(
        'Could not create private export staging directory',
        parent.path,
      );
    }
    final directory = Directory(created.toDartString());
    if ((directory.statSync().mode & 0x1ff) != 0x1c0) {
      directory.deleteSync();
      throw FileSystemException(
        'Could not secure private export staging directory',
        directory.path,
      );
    }
    return directory;
  });
}

Future<void> _exportTextDocument(
  String path,
  String text,
  Future<void> Function(File file, List<int> bytes) writeStagedFile,
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
    await writeStagedFile(stagedFile, bytes);
    await stagedFile.rename(destination.path);
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
