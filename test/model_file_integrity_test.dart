import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/model_file_integrity.dart';
import 'package:kotoha/model_terms_import.dart';

/// Minimal in-memory platform channel: only encoded replies cross this edge.
class _FakeMessenger extends BinaryMessenger {
  Future<ByteData?> Function(ByteData message)? onSend;
  int calls = 0;
  MethodCall? lastCall;

  @override
  Future<ByteData?> send(String channel, ByteData? message) async {
    calls++;
    expect(channel, 'org.kotoha/model_package');
    lastCall = const StandardMethodCodec().decodeMethodCall(message!);
    return onSend?.call(message);
  }

  // Required by BinaryMessenger; this fake only exercises send().
  // ignore: deprecated_member_use
  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    PlatformMessageResponseCallback? callback,
  ) async {}

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}
}

void main() {
  const codec = StandardMethodCodec();
  const file = DeclaredModelFile(
    path: 'weights/model.gguf',
    role: 'weights',
    sizeBytes: 1288490188,
    sha256: 'ab',
  );

  late _FakeMessenger messenger;
  late ModelFileIntegrity verifier;

  setUp(() {
    messenger = _FakeMessenger();
    verifier = ModelFileIntegrity(
      channel: MethodChannel('org.kotoha/model_package', codec, messenger),
    );
  });

  test('matching native reply verifies and sends metadata only', () async {
    messenger.onSend = (message) async => codec.encodeSuccessEnvelope(true);

    expect(await verifier.verify(const [file]), isTrue);
    expect(messenger.calls, 1);
    expect(messenger.lastCall!.method, 'verifyFiles');
    final args = messenger.lastCall!.arguments as Map<dynamic, dynamic>;
    final declared = (args['files'] as List).single as Map<dynamic, dynamic>;
    expect(declared, {
      'path': 'weights/model.gguf',
      'sizeBytes': 1288490188,
      'sha256': 'ab',
    });
    // No bytes are included in the platform call.
    expect(declared.values.any((value) => value is Uint8List), isFalse);
  });

  test('hash mismatch replies false', () async {
    messenger.onSend = (message) async => codec.encodeSuccessEnvelope(false);
    expect(await verifier.verify(const [file]), isFalse);
  });

  test('size mismatch replies false', () async {
    messenger.onSend = (message) async => codec.encodeSuccessEnvelope(false);
    const wrongSize = DeclaredModelFile(
      path: 'weights/model.gguf',
      role: 'weights',
      sizeBytes: 9,
      sha256: 'ab',
    );
    expect(await verifier.verify(const [wrongSize]), isFalse);
    final args = messenger.lastCall!.arguments as Map<dynamic, dynamic>;
    final declared = (args['files'] as List).single as Map<dynamic, dynamic>;
    expect(declared['sizeBytes'], 9);
  });

  test('platform exception fails closed', () async {
    messenger.onSend = (message) async =>
        codec.encodeErrorEnvelope(code: 'released', message: 'cancelled');
    expect(await verifier.verify(const [file]), isFalse);
  });

  test('thrown platform error fails closed', () async {
    messenger.onSend = (message) async => throw MissingPluginException();
    expect(await verifier.verify(const [file]), isFalse);
  });

  test('false and unexpected replies fail closed', () async {
    messenger.onSend = (message) async => codec.encodeSuccessEnvelope('true');
    expect(await verifier.verify(const [file]), isFalse);
    messenger.onSend = (message) async => codec.encodeSuccessEnvelope(null);
    expect(await verifier.verify(const [file]), isFalse);
  });

  test(
    'an empty declaration list fails closed without a platform call',
    () async {
      expect(await verifier.verify(const []), isFalse);
      expect(messenger.calls, 0);
    },
  );
}
