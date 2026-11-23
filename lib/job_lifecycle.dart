import 'model_registry.dart';

/// Job states of design §10.3. Terminal states fix the outcome and end the
/// job's hold on its pinned content; no transition leaves a terminal state.
enum JobState {
  preparing,
  waiting,
  running,
  paused,
  cancelRequested,
  succeeded,
  cancelled,
  failed;

  bool get isTerminal =>
      this == JobState.succeeded ||
      this == JobState.cancelled ||
      this == JobState.failed;
}

/// Classification of a refused lifecycle operation. Deliberately carries no
/// path, provider, digest, content or engine detail.
enum JobLifecycleFailure { invalidTransition }

/// A refused transition. [from] and [attempted] name only states and the
/// caller-supplied operation label, never content or external identifiers.
class JobLifecycleException implements Exception {
  const JobLifecycleException(this.failure, this.from, this.attempted);

  final JobLifecycleFailure failure;
  final JobState from;
  final String attempted;

  @override
  String toString() =>
      'JobLifecycleException(${failure.name}: $attempted from ${from.name})';
}

/// In-memory job state machine over an immutable content pin.
///
/// Construction pins an already-installed digest through [ModelRegistry.pin],
/// so the job holds exactly one lease it owns. That lease is released only on
/// a confirmed terminal transition, making design §7.5's "deletion of content
/// in use is synchronized with release of references" enforceable: while a
/// job is non-terminal the registry refuses to remove its pinned model.
///
/// Cancellation is cooperative (design §10.2): [requestCancel] records the
/// request and keeps the pin until [confirmCancelled] confirms termination.
/// This module never reads a file, invokes an engine, uses networking or
/// persistence, or claims support, availability, quality or runtime
/// authorization. A terminal state records the outcome only.
class JobLifecycle {
  JobLifecycle(this._registry, String manifestDigest)
    : pinnedDigest = manifestDigest,
      _lease = _registry.pin(manifestDigest);

  final ModelRegistry _registry;

  /// The exact installed digest identity pinned at construction. A later
  /// registry switch never changes what this job holds.
  final String pinnedDigest;

  ModelLease? _lease;
  JobState _state = JobState.preparing;

  JobState get state => _state;
  bool get isTerminal => _state.isTerminal;

  /// Whether the job still holds its content pin. False only after a terminal
  /// transition has released it.
  bool get holdsLease => _lease != null;

  void toWaiting() => _transition(
    JobState.waiting,
    'toWaiting',
    const <JobState>{JobState.preparing},
  );

  /// Starts a waiting job, or resumes a paused one.
  void toRunning() => _transition(
    JobState.running,
    'toRunning',
    const <JobState>{JobState.waiting, JobState.paused},
  );

  void toPaused() => _transition(JobState.paused, 'toPaused', const <JobState>{
    JobState.running,
  });

  /// Requests cancellation cooperatively; the pin is kept until
  /// [confirmCancelled] confirms termination and resource release.
  void requestCancel() =>
      _transition(JobState.cancelRequested, 'requestCancel', const <JobState>{
        JobState.preparing,
        JobState.waiting,
        JobState.running,
        JobState.paused,
      });

  void confirmCancelled() => _transition(
    JobState.cancelled,
    'confirmCancelled',
    const <JobState>{JobState.cancelRequested},
  );

  void succeed() => _transition(JobState.succeeded, 'succeed', const <JobState>{
    JobState.running,
  });

  /// A job can fail at any non-terminal point, including during teardown of a
  /// cancellation request.
  void fail() => _transition(JobState.failed, 'fail', const <JobState>{
    JobState.preparing,
    JobState.waiting,
    JobState.running,
    JobState.paused,
    JobState.cancelRequested,
  });

  void _transition(JobState next, String op, Set<JobState> allowed) {
    if (!allowed.contains(_state)) {
      throw JobLifecycleException(
        JobLifecycleFailure.invalidTransition,
        _state,
        op,
      );
    }
    _state = next;
    if (next.isTerminal) _releaseLease();
  }

  void _releaseLease() {
    final lease = _lease;
    if (lease == null) return;
    _registry.release(lease);
    _lease = null;
  }
}
