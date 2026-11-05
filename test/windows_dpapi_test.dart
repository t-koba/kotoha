import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/protected_key_store.dart';
import 'package:kotoha/windows_protected_key_store.dart';

void main() {
  test('real user-scope DPAPI save/reopen, no-overwrite and corruption preservation', () async {
    final directory = await Directory.systemTemp.createTemp('kotoha-dpapi-');
    addTearDown(() => directory.delete(recursive: true));
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final store = await openWindowsProtectedKeyStore(directory: directory);
    expect(await store.load(), isNull);
    await store.create(key);
    final file = File('${directory.path}${Platform.pathSeparator}db-key.dpapi');
    final original = await file.readAsBytes();
    expect(original, isNot(equals(key)));
    final reopened = await openWindowsProtectedKeyStore(directory: directory);
    expect(await reopened.load(), key);
    await expectLater(
      reopened.create(Uint8List(32)),
      throwsA(isA<ProtectedKeyStoreException>()),
    );
    expect(await file.readAsBytes(), original);
    expect(await reopened.load(), key);
    expect(await File('${file.path}.pending').exists(), isFalse);

    // Keep the format header valid, but truncate the authenticated DPAPI blob.
    final corrupt = Uint8List.fromList(original.take(6).toList());
    await file.writeAsBytes(corrupt, flush: true);
    await expectLater(
      reopened.load(),
      throwsA(
        isA<ProtectedKeyStoreException>().having(
          (e) => e.failure,
          'failure',
          KeyStoreFailure.unprotect,
        ),
      ),
    );
    expect(await file.readAsBytes(), corrupt);
    await expectLater(
      reopened.create(key),
      throwsA(isA<ProtectedKeyStoreException>()),
    );
    expect(await file.readAsBytes(), corrupt);
  }, skip: !Platform.isWindows);

  test('real concurrent creators publish exactly one whole key; stale staging blocks reset', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kotoha-dpapi-race-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final stores = await Future.wait(
      List.generate(
        2,
        (_) => openWindowsProtectedKeyStore(directory: directory),
      ),
    );
    final keys = [Uint8List(32), Uint8List.fromList(List.filled(32, 1))];
    final results = await Future.wait(
      List.generate(2, (i) async {
        try {
          await stores[i].create(keys[i]);
          return true;
        } on ProtectedKeyStoreException {
          return false;
        }
      }),
    );
    expect(results.where((won) => won), hasLength(1));
    expect(await stores[0].load(), keys[results.indexOf(true)]);
    final pending = File(
      '${directory.path}${Platform.pathSeparator}db-key.dpapi.pending',
    );
    expect(await pending.exists(), isFalse);

    final interruptedDirectory = await directory.createTemp('interrupted-');
    final interrupted = await openWindowsProtectedKeyStore(
      directory: interruptedDirectory,
    );
    final interruptedPending = File(
      '${interruptedDirectory.path}${Platform.pathSeparator}db-key.dpapi.pending',
    );
    await interruptedPending.writeAsBytes([1, 2, 3]);
    await expectLater(
      interrupted.load(),
      throwsA(
        isA<ProtectedKeyStoreException>().having(
          (e) => e.failure,
          'failure',
          KeyStoreFailure.creationPending,
        ),
      ),
    );
    await expectLater(
      interrupted.create(keys[0]),
      throwsA(isA<ProtectedKeyStoreException>()),
    );
    expect(await interruptedPending.readAsBytes(), [1, 2, 3]);
  }, skip: !Platform.isWindows);
}
