/// In-memory, fail-closed admission decisions for design §9.3 event integrity.
///
/// An event carries the identity of its job, execution and input snapshot, plus
/// a monotonic sequence within that execution. Only events matching the
/// current identity and advancing the sequence are admitted; the terminal
/// event is admitted once and its exact replay is idempotent.
///
/// This library only decides admission, recording the minimum decision state
/// needed for that decision. It never applies, persists, displays or emits an
/// event. A matching event proves nothing about origin, authenticity or that
/// any work was actually performed. There is no I/O, persistence, UI, engine
/// use, networking or quality claim here.
library;

final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');

String _requireId(String value, String name) {
  if (!_idPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'invalid lowercase id');
  }
  return value;
}

String _requireDigest(String value, String name) {
  if (!_digestPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'invalid sha-256 digest');
  }
  return value;
}

int _requireSequence(int value) {
  if (value < 1) {
    throw ArgumentError.value(value, 'sequence', 'sequence must be positive');
  }
  return value;
}

/// The exact job, execution and input snapshot an event belongs to.
///
/// Changing any component starts a new identity, so events from an edited
/// source or an earlier execution cannot be admitted to the current one.
/// Digests bind identity only: they prove nothing about origin, authenticity
/// or content quality.
class ExecutionIdentity {
  ExecutionIdentity(
    String jobId,
    String executionId,
    String inputSnapshotDigest,
  ) : jobId = _requireId(jobId, 'jobId'),
      executionId = _requireId(executionId, 'executionId'),
      inputSnapshotDigest = _requireDigest(
        inputSnapshotDigest,
        'inputSnapshotDigest',
      );

  final String jobId;
  final String executionId;
  final String inputSnapshotDigest;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExecutionIdentity &&
          other.jobId == jobId &&
          other.executionId == executionId &&
          other.inputSnapshotDigest == inputSnapshotDigest);

  @override
  int get hashCode => Object.hash(jobId, executionId, inputSnapshotDigest);

  /// Names the two ids only; the snapshot digest and any content are omitted.
  @override
  String toString() =>
      'ExecutionIdentity(jobId: $jobId, executionId: $executionId, '
      'inputSnapshotDigest: <redacted>)';
}

/// Whether an event reports partial output or ends the execution.
enum EventKind { partial, terminal }

/// An ordered event about one execution. It carries no content or result.
class ExecutionEvent {
  ExecutionEvent({
    required this.identity,
    required int sequence,
    required this.kind,
  }) : sequence = _requireSequence(sequence);

  final ExecutionIdentity identity;
  final int sequence;
  final EventKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExecutionEvent &&
          other.identity == identity &&
          other.sequence == sequence &&
          other.kind == kind);

  @override
  int get hashCode => Object.hash(identity, sequence, kind);

  /// Names only ids, order and kind; never content, digest or result data.
  @override
  String toString() =>
      'ExecutionEvent(identity: $identity, sequence: $sequence, '
      'kind: ${kind.name})';
}

/// The decision returned for a submitted [ExecutionEvent].
enum EventDisposition { applied, duplicate, stale, outOfOrder, afterTerminal }

/// In-memory gate over one [ExecutionIdentity].
///
/// [admit] only classifies an event against the current identity, the highest
/// admitted sequence and the admitted terminal event. Admission changes no
/// content, model, job state, storage or display; the caller owns any effect.
class ExecutionEventGate {
  ExecutionEventGate(this.current);

  /// The one identity this gate accepts. Replacing it requires a new gate.
  final ExecutionIdentity current;

  ExecutionEvent? _terminal;
  int _lastAppliedSequence = 0;

  /// Highest sequence admitted by this gate, or zero before any admission.
  int get lastAppliedSequence => _lastAppliedSequence;

  /// Whether a terminal event has been admitted by this gate.
  bool get terminalApplied => _terminal != null;

  /// Decides whether [event] may be admitted, without applying any effect.
  ///
  /// Identity is checked first, so changed input snapshots, jobs and
  /// executions are all stale. After a terminal, only the exact admitted
  /// terminal event is an idempotent duplicate; every other event is
  /// [EventDisposition.afterTerminal]. Refusals leave the decision state
  /// unchanged.
  EventDisposition admit(ExecutionEvent event) {
    if (event.identity != current) return EventDisposition.stale;

    final terminal = _terminal;
    if (terminal != null) {
      return event == terminal
          ? EventDisposition.duplicate
          : EventDisposition.afterTerminal;
    }

    if (event.sequence <= _lastAppliedSequence) {
      return EventDisposition.outOfOrder;
    }

    _lastAppliedSequence = event.sequence;
    if (event.kind == EventKind.terminal) _terminal = event;
    return EventDisposition.applied;
  }
}
