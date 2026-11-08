import 'package:flutter/services.dart';

import 'model_terms_import.dart';

/// Temporary SAF directory reader for the terms-review increment.
///
/// The native side holds only a temporary read-only grant, never a
/// persistable permission, and enforces the supplied [maxBytes] bound with a
/// 4 MiB protocol ceiling. Only manifest/terms metadata paths are requested;
/// weight files are never read.
class AndroidPackageReader implements PackageReader {
  static const _channel = MethodChannel('org.kotoha/model_package');
  @override
  Future<Uint8List?> readDirectoryFile(
    String relativePath,
    int maxBytes,
  ) async {
    final value = await _channel.invokeMethod<Uint8List>('readFile', {
      'path': relativePath,
      'maxBytes': maxBytes,
    });
    return value;
  }

  static Future<void> release() async => _channel.invokeMethod<void>('release');
  static Future<bool> select() async =>
      await _channel.invokeMethod<bool>('selectDirectory') ?? false;
}
