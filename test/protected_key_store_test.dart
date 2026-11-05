import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/protected_key_store.dart';
import 'package:kotoha/windows_protected_key_store.dart';

Matcher fails(KeyStoreFailure failure) => throwsA(
  isA<ProtectedKeyStoreException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

// Fault boundaries deliberately have no reset/delete/replace operations.
class MemoryKeyFile implements ProtectedKeyFile {
  Uint8List? bytes;
  Exception? createError;
  int creates = 0;

  @override
  Future<Uint8List?> read() async {
    return bytes == null ? null : Uint8List.fromList(bytes!);
  }

  @override
  Future<void> create(Uint8List ciphertext) async {
    creates++;
    if (createError != null) throw createError!;
    if (bytes != null) {
      throw const ProtectedKeyStoreException(KeyStoreFailure.alreadyExists);
    }
    bytes = Uint8List.fromList(ciphertext);
  }
}

// Reversible synthetic transform only; NOT encryption or a production backend.
class SyntheticProtector implements KeyProtector {
  Exception? protectError;
  Exception? unprotectError;
  int decrypts = 0;

  @override
  Uint8List protect(Uint8List key) {
    if (protectError != null) throw protectError!;
    return Uint8List.fromList(key.map((byte) => byte ^ 0xa5).toList());
  }

  @override
  Uint8List unprotect(Uint8List ciphertext) {
    decrypts++;
    if (unprotectError != null) throw unprotectError!;
    return protect(ciphertext);
  }
}

class ReadFaultFile extends Fake implements File {
  ReadFaultFile(this.original, this.error);
  final File original;
  final FileSystemException error;

  @override
  String get path => original.path;

  @override
  Future<Uint8List> readAsBytes() async => throw error;
}

class MissingThenReadFaultFile extends Fake implements File {
  MissingThenReadFaultFile(this.path, this.recheckError);

  @override
  final String path;
  final FileSystemException recheckError;
  var _reads = 0;

  @override
  Future<Uint8List> readAsBytes() async {
    if (_reads++ == 0) {
      throw FileSystemException(
        'injected initial absence',
        path,
        OSError('', 2),
      );
    }
    throw recheckError;
  }
}

class PublishingFile extends Fake implements File {
  PublishingFile(this.original, this.ciphertext);

  final File original;
  final Uint8List ciphertext;
  var _firstRead = true;

  @override
  String get path => original.path;

  @override
  Future<Uint8List> readAsBytes() async {
    if (_firstRead) {
      _firstRead = false;
      // Model a destination read that observed absence, whose error is
      // delivered after a concurrent creator publishes its pending bytes.
      final pending = File('$path.pending');
      await pending.writeAsBytes(ciphertext, flush: true);
      await pending.rename(path);
      throw FileSystemException(
        'injected stale not-found read',
        path,
        OSError('', 2),
      );
    }
    return original.readAsBytes();
  }
}

void main() {
  final key = Uint8List.fromList(List.generate(32, (i) => i));
  late MemoryKeyFile file;
  late SyntheticProtector protector;
  late ProtectedKeyStore store;

  setUp(() {
    file = MemoryKeyFile();
    protector = SyntheticProtector();
    store = ProtectedKeyStore(file: file, protector: protector);
  });

  test(
    'first use is absent without generating; explicit create round-trips',
    () async {
      expect(await store.load(), isNull);
      expect(file.creates, 0);
      await expectLater(
        store.create(Uint8List(0)),
        fails(KeyStoreFailure.format),
      );
      expect(file.bytes, isNull);
      await store.create(key);
      expect(file.bytes, isNot(equals(key)));
      final reopened = ProtectedKeyStore(file: file, protector: protector);
      expect(await reopened.load(), key);
      final original = Uint8List.fromList(file.bytes!);
      await expectLater(
        store.create(Uint8List.fromList([99])),
        fails(KeyStoreFailure.alreadyExists),
      );
      expect(file.bytes, original);
      expect(await store.load(), key);
    },
  );

  test(
    'protect and create failures propagate without replacing ciphertext',
    () async {
      await store.create(key);
      final original = Uint8List.fromList(file.bytes!);
      protector.protectError = const FormatException('injected native failure');
      await expectLater(store.create(key), fails(KeyStoreFailure.protect));
      expect(file.creates, 1);
      protector.protectError = null;
      file.createError = const FileSystemException('injected write failure');
      await expectLater(store.create(key), fails(KeyStoreFailure.create));
      expect(file.bytes, original);
    },
  );

  test('invalid/truncated format is preserved and never decrypted', () async {
    await store.create(key);
    final valid = file.bytes!;
    for (final bytes in [
      <int>[],
      valid.sublist(0, 5),
      [0, ...valid.skip(1)],
      [...valid.take(4), 2, ...valid.skip(5)],
    ]) {
      file.bytes = Uint8List.fromList(bytes);
      await expectLater(store.load(), fails(KeyStoreFailure.format));
      expect(file.bytes, bytes);
    }
    expect(protector.decrypts, 0);
  });

  test(
    'actual file bytes survive parse, decrypt, permission and read errors',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kotoha-key-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final actual = File('${directory.path}/key');
      await store.create(key);
      final original = file.bytes!;
      await actual.writeAsBytes(original);
      final diskStore = ProtectedKeyStore(
        file: WindowsProtectedKeyFile(actual),
        protector: protector,
      );
      protector.unprotectError = const FormatException('injected DPAPI error');
      await expectLater(diskStore.load(), fails(KeyStoreFailure.unprotect));
      expect(await actual.readAsBytes(), original);
      for (final code in [5, 23]) {
        final faulty = ProtectedKeyStore(
          file: WindowsProtectedKeyFile(
            ReadFaultFile(
              actual,
              FileSystemException('injected', actual.path, OSError('', code)),
            ),
          ),
          protector: protector,
        );
        await expectLater(faulty.load(), fails(KeyStoreFailure.read));
        expect(await actual.readAsBytes(), original);
      }
      protector.unprotectError = null;
      expect(await diskStore.load(), key);
      final corrupt = Uint8List.fromList([0, ...original.skip(1)]);
      await actual.writeAsBytes(corrupt);
      await expectLater(diskStore.load(), fails(KeyStoreFailure.format));
      expect(await actual.readAsBytes(), corrupt);
    },
  );

  test('preserves destination errors during the absence recheck', () async {
    final directory = await Directory.systemTemp.createTemp(
      'kotoha-key-recheck-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final target = File('${directory.path}/key');
    final file = WindowsProtectedKeyFile(
      MissingThenReadFaultFile(
        target.path,
        FileSystemException(
          'injected access denied',
          target.path,
          OSError('', 5),
        ),
      ),
    );

    await expectLater(
      file.read(),
      throwsA(
        isA<ProtectedKeyStoreException>()
            .having((error) => error.failure, 'failure', KeyStoreFailure.read)
            .having((error) => error.osError, 'osError', 5),
      ),
    );
  });

  test(
    'rechecks destination when a creator commits between missing reads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kotoha-key-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/key');
      final ciphertext = Uint8List.fromList([1, 2, 3]);
      final file = WindowsProtectedKeyFile(PublishingFile(target, ciphertext));

      expect(await file.read(), ciphertext);
      expect(await target.readAsBytes(), ciphertext);
      expect(await File('${target.path}.pending').exists(), isFalse);
    },
  );

  test(
    'pending ciphertext is not absence and is never silently removed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'kotoha-key-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final target = File('${directory.path}/key');
      final pending = File('${target.path}.pending');
      final diskStore = ProtectedKeyStore(
        file: WindowsProtectedKeyFile(target),
        protector: protector,
      );
      expect(await diskStore.load(), isNull);
      await pending.writeAsBytes([1, 2, 3]);
      await expectLater(
        diskStore.load(),
        fails(KeyStoreFailure.creationPending),
      );
      expect(await pending.readAsBytes(), [1, 2, 3]);
      expect(await target.exists(), isFalse);
    },
  );

  test('non-Windows entry points fail closed without loading DLLs', () async {
    await expectLater(
      openWindowsProtectedKeyStore(),
      fails(KeyStoreFailure.unsupportedPlatform),
    );
    expect(
      () => WindowsDpapiProtector().protect(key),
      fails(KeyStoreFailure.unsupportedPlatform),
    );
    expect(
      () => WindowsDpapiProtector().unprotect(key),
      fails(KeyStoreFailure.unsupportedPlatform),
    );
  }, skip: Platform.isWindows);
}
