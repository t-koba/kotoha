import 'package:flutter/services.dart';

import 'model_terms_import.dart';

/// Explicit, session-only integrity check for manifest-declared non-terms
/// files. The native side streams each file in place through a fixed buffer
/// and returns only a boolean; no bytes enter Dart, nothing is cached or
/// persisted, and no engine is involved. A matching digest is not proof of
/// origin, authenticity, or licensing.
class ModelFileIntegrity {
  const ModelFileIntegrity({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'org.kotoha/model_package';
  final MethodChannel _channel;

  /// Returns true only when the native side confirms every declared file.
  /// Any platform error, false, or unexpected reply fails closed.
  Future<bool> verify(List<DeclaredModelFile> files) async {
    if (files.isEmpty) return false;
    try {
      final reply = await _channel.invokeMethod<bool>('verifyFiles', {
        'files': files.map((file) => file.toPlatformArguments()).toList(),
      });
      return reply == true;
    } catch (_) {
      return false;
    }
  }
}
