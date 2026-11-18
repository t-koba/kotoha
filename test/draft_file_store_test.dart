import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/draft_file_store.dart';

Matcher fails(DraftFileFailure failure) => throwsA(
  isA<DraftFileStoreException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

class _StagingExists extends DraftFileStoreException {
  const _StagingExists() : super(DraftFileFailure.savePending);
}

// In-memory file-commit framing only; no cryptography or real filesystem.
class MemoryFileBackend implements DraftFileBackend {
  final _files = <String, Uint8List>{};
  bool failNextCommit = false;
  bool failRead = false;
  bool failNextWriteStagingAfterCreate = false;
  bool failNextWriteStagingGeneric = false;
  bool failNextRemoveStaging = false;
  int removeStagingCalls = 0;

  void seed(String name, Uint8List bytes) {
    _files[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String name) async {
    if (failRead) throw StateError('synthetic read failure');
    final bytes = _files[name];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeStaging(String name, Uint8List bytes) async {
    if (_files.containsKey(name)) throw const _StagingExists();
    if (failNextWriteStagingGeneric) {
      failNextWriteStagingGeneric = false;
      throw StateError('synthetic staging failure');
    }
    seed(name, bytes);
    if (failNextWriteStagingAfterCreate) {
      failNextWriteStagingAfterCreate = false;
      throw const DraftFileStoreException.stagingCreated();
    }
  }

  @override
  Future<void> commitReplace(String stagingName, String name) async {
    if (failNextCommit) {
      failNextCommit = false;
      throw StateError('synthetic commit failure');
    }
    seed(name, _files[stagingName]!);
    _files.remove(stagingName);
  }

  @override
  Future<void> removeStaging(String name) async {
    removeStagingCalls++;
    if (failNextRemoveStaging) {
      failNextRemoveStaging = false;
      throw StateError('synthetic staging removal failure');
    }
    _files.remove(name);
  }
}

void main() {
  const name = 'draft';
  const staging = '$name.pending';
  late MemoryFileBackend backend;
  late DraftFileStore store;
  final bytesA = Uint8List.fromList([1, 4, 9]);
  final bytesB = Uint8List.fromList([2, 0, 255, 7]);

  setUp(() {
    backend = MemoryFileBackend();
    store = DraftFileStore(backend: backend, name: name);
  });

  test('saves and reopens exact bytes, and replaces on a later save', () async {
    expect(await store.load(), isNull);
    await store.save(bytesA);
    final reopened = DraftFileStore(backend: backend, name: name);
    expect(await reopened.load(), orderedEquals(bytesA));
    expect(await backend.read(staging), isNull);

    await reopened.save(bytesB);
    expect(await store.load(), orderedEquals(bytesB));
    expect(await backend.read(staging), isNull);
  });

  test('a pre-existing staging file blocks save without touching committed '
      'bytes', () async {
    await store.save(bytesA);
    final pending = Uint8List.fromList([5]);
    backend.seed(staging, pending);

    await expectLater(store.save(bytesB), fails(DraftFileFailure.savePending));
    expect(await store.load(), orderedEquals(bytesA));
    expect(await backend.read(staging), orderedEquals(pending));
  });

  test('a failed commit preserves committed bytes and keeps staging', () async {
    await store.save(bytesA);
    backend.failNextCommit = true;

    await expectLater(store.save(bytesB), fails(DraftFileFailure.commit));
    expect(await store.load(), orderedEquals(bytesA));
    expect(await backend.read(staging), orderedEquals(bytesB));
  });

  test(
    'load reports pending when committed is absent but staging exists',
    () async {
      expect(await store.load(), isNull);
      backend.seed(staging, bytesA);

      await expectLater(store.load(), fails(DraftFileFailure.savePending));
    },
  );

  test('rejects an empty envelope', () async {
    await expectLater(store.save(Uint8List(0)), fails(DraftFileFailure.stage));
    expect(await store.load(), isNull);
  });

  test('a backend read failure maps to a read failure', () async {
    await store.save(bytesA);
    backend.failRead = true;
    await expectLater(store.load(), fails(DraftFileFailure.read));
  });

  test(
    'a partial staging write cleans up and reports a stage failure',
    () async {
      await store.save(bytesA);
      backend.failNextWriteStagingAfterCreate = true;

      await expectLater(store.save(bytesB), fails(DraftFileFailure.stage));
      expect(backend.removeStagingCalls, 1);
      expect(await backend.read(staging), isNull);
      // The committed bytes are untouched and a later save can proceed.
      expect(await store.load(), orderedEquals(bytesA));
      await store.save(bytesB);
      expect(await store.load(), orderedEquals(bytesB));
    },
  );

  test('a generic staging write failure maps to a stage failure', () async {
    await store.save(bytesA);
    backend.failNextWriteStagingGeneric = true;

    await expectLater(store.save(bytesB), fails(DraftFileFailure.stage));
    expect(backend.removeStagingCalls, 0);
    expect(await store.load(), orderedEquals(bytesA));
  });

  test('discardPending clears a staging-only pending state', () async {
    backend.seed(staging, bytesA);
    await expectLater(store.load(), fails(DraftFileFailure.savePending));

    await store.discardPending();
    expect(await backend.read(staging), isNull);
    expect(await store.load(), isNull);
    await store.save(bytesB);
    expect(await store.load(), orderedEquals(bytesB));
  });

  test('discardPending never touches committed bytes and is safe with no '
      'staging', () async {
    await store.save(bytesA);
    await store.discardPending();
    expect(backend.removeStagingCalls, 1);
    expect(await store.load(), orderedEquals(bytesA));

    backend.seed(staging, bytesB);
    await store.discardPending();
    expect(await backend.read(staging), isNull);
    expect(await store.load(), orderedEquals(bytesA));
  });

  test(
    'discardPending reports a backend removal failure and stays wedged',
    () async {
      backend.seed(staging, bytesA);
      backend.failNextRemoveStaging = true;

      await expectLater(
        store.discardPending(),
        fails(DraftFileFailure.discard),
      );
      expect(await backend.read(staging), orderedEquals(bytesA));
      await expectLater(store.load(), fails(DraftFileFailure.savePending));
    },
  );
}
