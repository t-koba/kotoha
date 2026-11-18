import 'dart:typed_data';

/// The injected cipher boundary. Lengths are fixed; inputs must not be mutated.
abstract interface class DraftEnvelopeAead {
  int get nonceLength;
  int get tagLength;

  /// Returns ciphertext followed by the authentication tag.
  Uint8List seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  });

  /// Returns null if and only if authentication fails. A bad tag must not throw.
  Uint8List? open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List ciphertextWithTag,
  });
}

/// Supplies nonces of the requested length. The caller is responsible for
/// freshness under each key; the codec derives neither keys nor nonces from
/// implicit state.
abstract interface class DraftNonceGenerator {
  Uint8List next(int length);
}

class DraftEnvelopeException implements Exception {
  const DraftEnvelopeException(this.reason);

  final String reason;

  @override
  String toString() => 'DraftEnvelopeException($reason)';
}

/// Frames raw bytes; all encryption and authentication are delegated to [aead].
/// V1 is `KDRE | version | nonce length | nonce | ciphertext | tag`, with the
/// entire header (through the nonce) passed as associated data.
class DraftEnvelopeCodec {
  const DraftEnvelopeCodec({required this.aead, required this.nonce});

  static const int formatVersion = 1;
  static const _magic = [0x4b, 0x44, 0x52, 0x45];
  static const _prefixLength = 6;

  final DraftEnvelopeAead aead;
  final DraftNonceGenerator nonce;

  Uint8List seal({required Uint8List key, required Uint8List plaintext}) {
    final nonceLength = _checkedNonceLength(key);
    final nonceBytes = nonce.next(nonceLength);
    if (nonceBytes.length != nonceLength) {
      throw const DraftEnvelopeException('invalid nonce length');
    }
    final header = Uint8List(_prefixLength + nonceLength)
      ..setAll(0, _magic)
      ..[4] = formatVersion
      ..[5] = nonceLength
      ..setAll(_prefixLength, nonceBytes);
    final ciphertextWithTag = aead.seal(
      key: key,
      nonce: nonceBytes,
      associatedData: header,
      plaintext: plaintext,
    );
    return Uint8List(header.length + ciphertextWithTag.length)
      ..setAll(0, header)
      ..setAll(header.length, ciphertextWithTag);
  }

  Uint8List open({required Uint8List key, required Uint8List envelope}) {
    final nonceLength = _checkedNonceLength(key);
    final headerLength = _prefixLength + nonceLength;
    if (envelope.length < headerLength + aead.tagLength) {
      throw const DraftEnvelopeException('truncated envelope');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (envelope[i] != _magic[i]) {
        throw const DraftEnvelopeException('invalid magic');
      }
    }
    if (envelope[4] != formatVersion) {
      throw const DraftEnvelopeException('unsupported version');
    }
    if (envelope[5] != nonceLength) {
      throw const DraftEnvelopeException('invalid nonce length');
    }
    final plaintext = aead.open(
      key: key,
      nonce: Uint8List.sublistView(envelope, _prefixLength, headerLength),
      associatedData: Uint8List.sublistView(envelope, 0, headerLength),
      ciphertextWithTag: Uint8List.sublistView(envelope, headerLength),
    );
    if (plaintext == null) {
      throw const DraftEnvelopeException('authentication failed');
    }
    return Uint8List.fromList(plaintext);
  }

  int _checkedNonceLength(Uint8List key) {
    if (key.isEmpty) throw const DraftEnvelopeException('empty key');
    final length = aead.nonceLength;
    if (length < 1 || length > 255) {
      throw const DraftEnvelopeException('invalid nonce length');
    }
    return length;
  }
}
