import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/draft_envelope.dart';
import 'package:kotoha/draft_file_store.dart';
import 'package:kotoha/draft_store.dart';
import 'package:kotoha/workspace.dart';

// Test-only framing doubles: no real encryption or filesystem.
class _TagAead implements DraftEnvelopeAead {
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
  }) => Uint8List.fromList([
    ...plaintext,
    ..._tag(key, associatedData, plaintext),
  ]);

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
    return difference == 0 ? Uint8List.fromList(ciphertext) : null;
  }

  List<int> _tag(Uint8List key, Uint8List header, Uint8List ciphertext) => Hmac(
    sha256,
    key,
  ).convert([...header, ...ciphertext]).bytes.take(tagLength).toList();
}

class _CounterNonce implements DraftNonceGenerator {
  int _counter = 0;

  @override
  Uint8List next(int length) {
    final bytes = Uint8List(length);
    ByteData.sublistView(bytes).setUint32(0, _counter++, Endian.little);
    return bytes;
  }
}

class _MemoryBackend implements DraftFileBackend {
  final _files = <String, Uint8List>{};

  @override
  Future<Uint8List?> read(String name) async {
    final bytes = _files[name];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeStaging(String name, Uint8List bytes) async {
    if (_files.containsKey(name)) throw StateError('staging exists');
    seed(name, bytes);
  }

  @override
  Future<void> commitReplace(String stagingName, String name) async {
    seed(name, _files[stagingName]!);
    _files.remove(stagingName);
  }

  @override
  Future<void> removeStaging(String name) async {
    _files.remove(name);
  }

  void seed(String name, Uint8List bytes) =>
      _files[name] = Uint8List.fromList(bytes);

  Uint8List? peek(String name) => _files[name];
}

void main() {
  const name = 'draft.envelope';
  final key = Uint8List.fromList([1, 2, 3, 4]);
  late _MemoryBackend backend;

  DraftStore build() => DraftStore(
    fileStore: DraftFileStore(backend: backend, name: name),
    envelope: DraftEnvelopeCodec(aead: _TagAead(), nonce: _CounterNonce()),
    key: key,
  );

  TextWorkspaceDraft sample() => TextWorkspaceDraft(
    sourceLanguage: 'ja',
    sourceText: '月がきれいです。🌙',
    translations: const [
      ManualTranslationDraft(targetLanguage: 'en', text: 'The moon is lovely.'),
      ManualTranslationDraft(targetLanguage: 'fr', text: 'La lune est belle.'),
    ],
  );

  setUp(() {
    backend = _MemoryBackend();
  });

  test('saves and reopens a multilingual draft with edit integrity', () async {
    final store = build();
    expect(await store.load(), isNull);

    await store.save(sample());
    final first = await build().load();
    expect(first, isNotNull);
    expect(first!.sourceLanguage, 'ja');
    expect(first.sourceText, '月がきれいです。🌙');
    expect(first.translations.map((entry) => entry.targetLanguage), [
      'en',
      'fr',
    ]);
    expect(first.translations.map((entry) => entry.text), [
      'The moon is lovely.',
      'La lune est belle.',
    ]);

    final edited = first.copyWith(
      translations: [
        first.translations[0],
        first.translations[1].copyWith(text: 'La lune est magnifique. 🌙'),
      ],
    );
    await store.save(edited);
    final second = await build().load();
    expect(second!.sourceText, '月がきれいです。🌙');
    expect(second.translations.map((entry) => entry.targetLanguage), [
      'en',
      'fr',
    ]);
    expect(second.translations.map((entry) => entry.text), [
      'The moon is lovely.',
      'La lune est magnifique. 🌙',
    ]);
  });

  test('a tampered committed file fails closed', () async {
    await build().save(sample());
    final tampered = Uint8List.fromList(backend.peek(name)!);
    tampered[tampered.length - 1] ^= 1;
    backend.seed(name, tampered);
    await expectLater(build().load(), throwsA(isA<DraftEnvelopeException>()));
  });

  test('a truncated committed file fails closed', () async {
    await build().save(sample());
    final sealed = Uint8List.fromList(backend.peek(name)!);
    backend.seed(name, sealed.sublist(0, sealed.length - 1));
    await expectLater(build().load(), throwsA(isA<DraftEnvelopeException>()));
  });

  test('load before any save returns null', () async {
    expect(await build().load(), isNull);
  });

  test(
    'discardPending recovers a pending-only store for a fresh round-trip',
    () async {
      backend.seed('$name.pending', Uint8List.fromList([1, 2, 3]));
      final store = build();
      await expectLater(store.load(), throwsA(isA<DraftFileStoreException>()));

      await store.discardPending();
      expect(await build().load(), isNull);

      await store.save(sample());
      final reopened = await build().load();
      expect(reopened!.sourceLanguage, 'ja');
      expect(reopened.sourceText, '月がきれいです。🌙');
      expect(reopened.translations.map((entry) => entry.text), [
        'The moon is lovely.',
        'La lune est belle.',
      ]);
    },
  );
}
