import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/job_lifecycle.dart';
import 'package:kotoha/model_registry.dart';
import 'package:kotoha/model_terms_import.dart';

String digest(String digit) => digit * 64;

ModelRegistry registryWith(String id) {
  final registry = ModelRegistry();
  registry.install(EphemeralModelAuthorization(id, digest('1')));
  return registry;
}

void expectInvalidTransition(
  JobLifecycleFailure failure,
  void Function() action,
) {
  expect(
    action,
    throwsA(
      isA<JobLifecycleException>().having((e) => e.failure, 'failure', failure),
    ),
  );
}

// Design §10.2-§10.3: that a job never reads a file, invokes an engine or
// touches the network cannot be probed in pure Dart. It is enforced
// structurally: lib/job_lifecycle.dart imports only model_registry.dart (no
// dart:io, dart:ffi, networking, persistence, timers, isolates or engine calls).
// The registry's lease is the real reference counted here.
void main() {
  test('construction pins installed content and starts preparing', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'));
    expect(job.state, JobState.preparing);
    expect(job.isTerminal, isFalse);
    expect(job.holdsLease, isTrue);
    expect(job.pinnedDigest, digest('a'));
    expect(registry.leaseCount(digest('a')), 1);
  });

  test('construction fails closed for an uninstalled digest', () {
    final registry = registryWith(digest('a'));
    expect(
      () => JobLifecycle(registry, digest('b')),
      throwsA(
        isA<ModelRegistryException>().having(
          (e) => e.failure,
          'failure',
          ModelRegistryFailure.notInstalled,
        ),
      ),
    );
    expect(registry.leaseCount(digest('a')), 0);
  });

  test('happy path releases the lease exactly once at success', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'));
    job.toWaiting();
    expect(registry.leaseCount(digest('a')), 1);
    job.toRunning();
    expect(registry.leaseCount(digest('a')), 1);
    job.succeed();
    expect(job.state, JobState.succeeded);
    expect(job.isTerminal, isTrue);
    expect(job.holdsLease, isFalse);
    expect(registry.leaseCount(digest('a')), 0);
  });

  test('pause and resume keep the same pin', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'))
      ..toWaiting()
      ..toRunning()
      ..toPaused();
    expect(job.state, JobState.paused);
    expect(job.holdsLease, isTrue);
    expect(registry.leaseCount(digest('a')), 1);
    job.toRunning();
    expect(job.state, JobState.running);
    expect(registry.leaseCount(digest('a')), 1);
  });

  test('cooperative cancellation keeps the pin until confirmed', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'))
      ..toWaiting()
      ..toRunning()
      ..requestCancel();
    expect(job.state, JobState.cancelRequested);
    expect(job.isTerminal, isFalse);
    expect(job.holdsLease, isTrue);
    expect(registry.leaseCount(digest('a')), 1);
    // A model in use is still not removable while cancellation is pending.
    expect(
      () => registry.remove(digest('a')),
      throwsA(
        isA<ModelRegistryException>().having(
          (e) => e.failure,
          'failure',
          ModelRegistryFailure.inUse,
        ),
      ),
    );
    job.confirmCancelled();
    expect(job.state, JobState.cancelled);
    expect(job.holdsLease, isFalse);
    expect(registry.leaseCount(digest('a')), 0);
    registry.remove(digest('a'));
  });

  test(
    'cancellation can be requested before running and can fail in teardown',
    () {
      final registry = registryWith(digest('a'));
      final job = JobLifecycle(registry, digest('a'))..requestCancel();
      expect(job.state, JobState.cancelRequested);
      job.fail();
      expect(job.state, JobState.failed);
      expect(job.holdsLease, isFalse);
      expect(registry.leaseCount(digest('a')), 0);
    },
  );

  test('fail from every non-terminal state releases the lease', () {
    for (final prepare in <void Function(JobLifecycle)>[
      (job) {},
      (job) => job.toWaiting(),
      (job) {
        job.toWaiting();
        job.toRunning();
      },
      (job) {
        job.toWaiting();
        job.toRunning();
        job.toPaused();
      },
    ]) {
      final registry = registryWith(digest('a'));
      final job = JobLifecycle(registry, digest('a'));
      prepare(job);
      job.fail();
      expect(job.state, JobState.failed);
      expect(job.holdsLease, isFalse);
      expect(registry.leaseCount(digest('a')), 0);
    }
  });

  test('out-of-order transitions fail closed without changing state', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'));
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.toRunning,
    );
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.toPaused,
    );
    expectInvalidTransition(JobLifecycleFailure.invalidTransition, job.succeed);
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.confirmCancelled,
    );
    expect(job.state, JobState.preparing);
    expect(registry.leaseCount(digest('a')), 1);
  });

  test('leaving a terminal state fails closed and never re-releases', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'))
      ..toWaiting()
      ..toRunning()
      ..succeed();
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.toWaiting,
    );
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.toRunning,
    );
    expectInvalidTransition(
      JobLifecycleFailure.invalidTransition,
      job.requestCancel,
    );
    expectInvalidTransition(JobLifecycleFailure.invalidTransition, job.fail);
    expect(job.state, JobState.succeeded);
    expect(job.holdsLease, isFalse);
    expect(registry.leaseCount(digest('a')), 0);
  });

  test('multiple jobs pin the same digest independently', () {
    final registry = registryWith(digest('a'));
    final first = JobLifecycle(registry, digest('a'));
    final second = JobLifecycle(registry, digest('a'))..toWaiting();
    expect(registry.leaseCount(digest('a')), 2);
    first
      ..toWaiting()
      ..toRunning()
      ..succeed();
    expect(registry.leaseCount(digest('a')), 1);
    expect(() => registry.remove(digest('a')), throwsA(isA<Exception>()));
    second
      ..toRunning()
      ..fail();
    expect(registry.leaseCount(digest('a')), 0);
    registry.remove(digest('a'));
  });

  test('a later registry switch does not change what a job pinned', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'));
    registry.install(EphemeralModelAuthorization(digest('b'), digest('1')));
    registry.activate(digest('b'));
    expect(registry.activeId, digest('b'));
    expect(job.pinnedDigest, digest('a'));
    expect(registry.leaseCount(digest('a')), 1);
    expect(registry.leaseCount(digest('b')), 0);
  });

  test('exception classification names only states and the operation', () {
    final registry = registryWith(digest('a'));
    final job = JobLifecycle(registry, digest('a'));
    try {
      job.succeed();
      fail('expected a refusal');
    } on JobLifecycleException catch (e) {
      expect(e.failure, JobLifecycleFailure.invalidTransition);
      expect(e.from, JobState.preparing);
      expect(e.attempted, 'succeed');
      expect(
        e.toString(),
        'JobLifecycleException(invalidTransition: succeed from preparing)',
      );
      expect(e.toString(), isNot(contains(digest('a'))));
    }
  });
}
