import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/draft_envelope.dart';
import 'package:kotoha/workspace.dart';

// A framing test double, not a real AEAD.
class FakeAead implements DraftEnvelopeAead {
  @override
  int get nonceLength => 12;

  @override
  int get tagLength => 16;

  @override
  Uint8List seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  }) {
    final ciphertext = _xor(key, nonce, plaintext);
    return Uint8List.fromList([
      ...ciphertext,
      ..._tag(key, associatedData, ciphertext),
    ]);
  }

  @override
  Uint8List? open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List ciphertextWithTag,
  }) {
    final length = ciphertextWithTag.length - tagLength;
    if (length < 0) return null;
    final ciphertext = Uint8List.sublistView(ciphertextWithTag, 0, length);
    final tag = _tag(key, associatedData, ciphertext);
    var difference = 0;
    for (var i = 0; i < tagLength; i++) {
      difference |= tag[i] ^ ciphertextWithTag[length + i];
    }
    return difference == 0 ? _xor(key, nonce, ciphertext) : null;
  }

  List<int> _tag(Uint8List key, Uint8List header, Uint8List ciphertext) => Hmac(
    sha256,
    key,
  ).convert([...header, ...ciphertext]).bytes.take(tagLength).toList();

  Uint8List _xor(Uint8List key, Uint8List nonce, Uint8List input) {
    final counter = ByteData(4);
    final output = Uint8List(input.length);
    for (var offset = 0, block = 0; offset < input.length; block++) {
      counter.setUint32(0, block, Endian.little);
      final stream = sha256.convert([
        ...key,
        ...nonce,
        ...counter.buffer.asUint8List(),
      ]).bytes;
      for (
        var i = 0;
        i < stream.length && offset < input.length;
        i++, offset++
      ) {
        output[offset] = input[offset] ^ stream[i];
      }
    }
    return output;
  }
}

class CounterNonce implements DraftNonceGenerator {
  int _counter = 0;

  @override
  Uint8List next(int length) {
    final bytes = Uint8List(length);
    ByteData.sublistView(bytes).setUint32(0, _counter++, Endian.little);
    return bytes;
  }
}

Matcher _throwsEnvelope(String reason) => throwsA(
  isA<DraftEnvelopeException>().having(
    (error) => error.reason,
    'reason',
    reason,
  ),
);

void main() {
  final aead = FakeAead();
  final key = Uint8List.fromList([1, 2, 3]);
  const headerLength = 6 + 12;
  late DraftEnvelopeCodec codec;

  setUp(() {
    codec = DraftEnvelopeCodec(aead: aead, nonce: CounterNonce());
  });

  test('round-trips a multilingual draft through the envelope', () {
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: '月がきれいです。🌙',
      translations: const [
        ManualTranslationDraft(
          targetLanguage: 'en',
          text: 'The moon is lovely.',
        ),
        ManualTranslationDraft(
          targetLanguage: 'fr',
          text: 'La lune est belle.',
        ),
      ],
    );
    final plaintext = utf8.encode(jsonEncode(draft.toJson()));
    final first = codec.seal(key: key, plaintext: plaintext);
    final second = codec.seal(key: key, plaintext: plaintext);
    expect(first.sublist(0, 6), [...ascii.encode('KDRE'), 1, 12]);
    expect(
      first.sublist(6, headerLength),
      isNot(second.sublist(6, headerLength)),
    );

    final restored = TextWorkspaceDraft.fromJson(
      jsonDecode(utf8.decode(codec.open(key: key, envelope: first))),
    );
    expect(restored.sourceLanguage, 'ja');
    expect(restored.sourceText, '月がきれいです。🌙');
    expect(restored.translations.map((entry) => entry.targetLanguage), [
      'en',
      'fr',
    ]);
    expect(restored.translations.map((entry) => entry.text), [
      'The moon is lovely.',
      'La lune est belle.',
    ]);
  });

  test('rejects a tampered or truncated envelope', () {
    final envelope = codec.seal(key: key, plaintext: utf8.encode('draft'));
    for (final offset in [6, headerLength]) {
      final tampered = Uint8List.fromList(envelope)..[offset] ^= 1;
      expect(
        () => codec.open(key: key, envelope: tampered),
        _throwsEnvelope('authentication failed'),
      );
    }
    expect(
      () => codec.open(
        key: key,
        envelope: envelope.sublist(0, envelope.length - 1),
      ),
      _throwsEnvelope('authentication failed'),
    );
    final wrongVersion = Uint8List.fromList(envelope)..[4] = 2;
    expect(
      () => codec.open(key: key, envelope: wrongVersion),
      _throwsEnvelope('unsupported version'),
    );
  });

  test('rejects wrong key and malformed header', () {
    final plaintext = utf8.encode('draft');
    final envelope = codec.seal(key: key, plaintext: plaintext);
    expect(
      () => codec.open(key: Uint8List.fromList([3, 2, 1]), envelope: envelope),
      _throwsEnvelope('authentication failed'),
    );
    final emptyKey = Uint8List(0);
    expect(
      () => codec.open(key: emptyKey, envelope: envelope),
      _throwsEnvelope('empty key'),
    );
    expect(
      () => codec.seal(key: emptyKey, plaintext: plaintext),
      _throwsEnvelope('empty key'),
    );

    final badMagic = Uint8List.fromList(envelope)..[0] ^= 1;
    expect(
      () => codec.open(key: key, envelope: badMagic),
      _throwsEnvelope('invalid magic'),
    );
    final badNonceLength = Uint8List.fromList(envelope)..[5] = 0;
    expect(
      () => codec.open(key: key, envelope: badNonceLength),
      _throwsEnvelope('invalid nonce length'),
    );
  });

  test('accepts an empty payload only with a complete tag', () {
    final envelope = codec.seal(key: key, plaintext: Uint8List(0));
    expect(envelope, hasLength(headerLength + aead.tagLength));
    expect(codec.open(key: key, envelope: envelope), isEmpty);
    expect(
      () => codec.open(
        key: key,
        envelope: envelope.sublist(0, envelope.length - 1),
      ),
      _throwsEnvelope('truncated envelope'),
    );
  });
}
