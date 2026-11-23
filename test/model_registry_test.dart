import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/model_registry.dart';
import 'package:kotoha/model_terms_import.dart';

String digest(String digit) => digit * 64;

void expectFailure(ModelRegistryFailure failure, void Function() action) {
  expect(
    action,
    throwsA(
      isA<ModelRegistryException>().having(
        (e) => e.failure,
        'failure',
        failure,
      ),
    ),
  );
}

// Design §7.5: that install/activate/pin never change a file or invoke an
// engine cannot be probed in pure Dart. It is enforced structurally instead:
// lib/model_registry.dart imports only dart:core (implicit) and
// model_terms_import.dart — no dart:io, dart:ffi, networking, persistence,
// timers, isolates or engine/plugin calls.
void main() {
  test('install rejects malformed digests and duplicates', () {
    final registry = ModelRegistry();
    final terms = digest('1');
    for (final bad in <String>[
      '',
      'abc',
      'A' * 64,
      'g' * 64,
      'a' * 63,
      'a' * 65,
    ]) {
      expectFailure(
        ModelRegistryFailure.invalidBinding,
        () => registry.install(EphemeralModelAuthorization(bad, terms)),
      );
    }
    expectFailure(
      ModelRegistryFailure.invalidBinding,
      () => registry.install(
        EphemeralModelAuthorization(digest('a'), 'not-a-digest'),
      ),
    );
    registry.install(EphemeralModelAuthorization(digest('a'), terms));
    expectFailure(
      ModelRegistryFailure.duplicate,
      () => registry.install(
        EphemeralModelAuthorization(digest('a'), digest('2')),
      ),
    );
    // The first binding survives the refused overwrite.
    expect(registry.lookup(digest('a'))!.termsDigest, terms);
    expect(
      const ModelRegistryException(ModelRegistryFailure.inUse).toString(),
      'ModelRegistryException(inUse)',
    );
  });

  test('install snapshots declared files unmodifiably', () {
    final registry = ModelRegistry();
    final files = <DeclaredModelFile>[
      DeclaredModelFile(
        path: 'weights.bin',
        role: 'weights',
        sizeBytes: 8,
        sha256: digest('1'),
      ),
    ];
    registry.install(
      EphemeralModelAuthorization(digest('a'), digest('1'), files),
    );
    files.add(
      const DeclaredModelFile(
        path: 'extra.bin',
        role: 'weights',
        sizeBytes: 1,
        sha256: '0',
      ),
    );
    files.clear();
    final stored = registry.lookup(digest('a'))!.declaredFiles;
    expect(stored, hasLength(1));
    expect(stored.single.path, 'weights.bin');
    expect(() => stored.add(stored.single), throwsUnsupportedError);
    expect(() => stored.clear(), throwsUnsupportedError);
  });

  test(
    'installedIds is sorted and unmodifiable; lookup misses return null',
    () {
      final registry = ModelRegistry()
        ..install(EphemeralModelAuthorization(digest('c'), digest('1')))
        ..install(EphemeralModelAuthorization(digest('a'), digest('2')))
        ..install(EphemeralModelAuthorization(digest('b'), digest('3')));
      expect(registry.installedIds, [digest('a'), digest('b'), digest('c')]);
      expect(
        () => (registry.installedIds as List<String>).add('x'),
        throwsUnsupportedError,
      );
      expect(registry.lookup(digest('f')), isNull);
    },
  );

  test('activate switches and keeps the previous binding installed', () {
    final registry = ModelRegistry();
    final a = digest('a'), b = digest('b');
    expectFailure(
      ModelRegistryFailure.notInstalled,
      () => registry.activate(a),
    );
    registry
      ..install(EphemeralModelAuthorization(a, digest('1')))
      ..install(EphemeralModelAuthorization(b, digest('2')));
    registry.activate(a);
    expect(registry.activeId, a);
    registry.activate(a);
    expect(registry.activeId, a);
    registry.activate(b);
    expect(registry.activeId, b);
    expect(registry.lookup(a), isNotNull);
    registry.activate(a);
    expect(registry.activeId, a);
    expect(registry.lookup(b), isNotNull);
  });

  test('pin binds exact content and survives active switches', () {
    final registry = ModelRegistry();
    final a = digest('a'), b = digest('b');
    expectFailure(ModelRegistryFailure.notInstalled, () => registry.pin(a));
    registry
      ..install(EphemeralModelAuthorization(a, digest('1')))
      ..install(EphemeralModelAuthorization(b, digest('2')));
    registry.activate(a);
    final first = registry.pin(a);
    final second = registry.pin(a);
    expect(first.manifestDigest, a);
    expect(registry.leaseCount(a), 2);
    expect(registry.leaseCount(b), 0);
    final pinnedB = registry.pin(b);
    registry.activate(b);
    expect(first.manifestDigest, a);
    expect(second.manifestDigest, a);
    expect(registry.leaseCount(a), 2);
    expect(pinnedB.manifestDigest, b);
    expect(registry.leaseCount(b), 1);
    expect(registry.activeId, b);
  });

  test('release is owner-bound and rejects double release', () {
    final registry = ModelRegistry();
    final other = ModelRegistry();
    final a = digest('a');
    final authorization = EphemeralModelAuthorization(a, digest('1'));
    registry.install(authorization);
    other.install(authorization);
    final lease = registry.pin(a);
    final foreign = other.pin(a);
    expectFailure(
      ModelRegistryFailure.invalidLease,
      () => registry.release(foreign),
    );
    expect(registry.leaseCount(a), 1);
    expect(other.leaseCount(a), 1);
    registry.release(lease);
    expect(registry.leaseCount(a), 0);
    expectFailure(
      ModelRegistryFailure.invalidLease,
      () => registry.release(lease),
    );
    expect(other.leaseCount(a), 1);
  });

  test('remove refuses in-use ids and succeeds after release and switch', () {
    final registry = ModelRegistry();
    final a = digest('a'), b = digest('b');
    expectFailure(ModelRegistryFailure.notInstalled, () => registry.remove(a));
    registry
      ..install(EphemeralModelAuthorization(a, digest('1')))
      ..install(EphemeralModelAuthorization(b, digest('2')));
    registry.activate(a);
    expectFailure(ModelRegistryFailure.inUse, () => registry.remove(a));
    registry.activate(b);
    final lease = registry.pin(a);
    expectFailure(ModelRegistryFailure.inUse, () => registry.remove(a));
    registry.release(lease);
    registry.remove(a);
    expect(registry.lookup(a), isNull);
    expect(registry.activeId, b);
    expect(registry.installedIds, [b]);
    registry.install(EphemeralModelAuthorization(a, digest('1')));
    expect(registry.lookup(a), isNotNull);
  });
}
