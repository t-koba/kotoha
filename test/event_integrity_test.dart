import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/event_integrity.dart';

const String _snapshot =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _otherSnapshot =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ExecutionIdentity _identity({
  String jobId = 'job-1',
  String executionId = 'exec-1',
  String inputSnapshotDigest = _snapshot,
}) => ExecutionIdentity(jobId, executionId, inputSnapshotDigest);

ExecutionEvent _event({
  ExecutionIdentity? identity,
  int sequence = 0,
  EventKind kind = EventKind.partial,
}) => ExecutionEvent(
  identity: identity ?? _identity(),
  sequence: sequence,
  kind: kind,
);

void main() {
  test('validation errors do not echo rejected caller content', () {
    const rejected = '/private/user/secret\u202E';
    String errorFrom(void Function() body) {
      try {
        body();
      } on ArgumentError catch (error) {
        return error.toString();
      }
      throw StateError('expected ArgumentError');
    }

    void expectSafe(String error, String field, String reason) {
      expect(error, contains(field));
      expect(error, contains(reason));
      expect(error, contains('<rejected>'));
      expect(error, isNot(contains(rejected)));
    }

    expectSafe(
      errorFrom(() => _identity(jobId: rejected)),
      'jobId',
      'invalid lowercase id',
    );
    expectSafe(
      errorFrom(() => _identity(executionId: rejected)),
      'executionId',
      'invalid lowercase id',
    );
    expectSafe(
      errorFrom(() => _identity(inputSnapshotDigest: rejected)),
      'inputSnapshotDigest',
      'invalid sha-256 digest',
    );
  });

  test(
    'increasing zero-based sequences are applied and the state tracks them',
    () {
      final gate = ExecutionEventGate(_identity());
      final first = _event(sequence: 0);
      final second = _event(sequence: 1);
      final terminal = _event(sequence: 2, kind: EventKind.terminal);

      expect(gate.lastAppliedSequence, -1);
      expect(gate.terminalApplied, isFalse);
      expect(gate.admit(first), EventDisposition.applied);
      expect(gate.lastAppliedSequence, 0);
      expect(gate.terminalApplied, isFalse);
      expect(gate.admit(second), EventDisposition.applied);
      expect(gate.lastAppliedSequence, 1);
      expect(gate.admit(terminal), EventDisposition.applied);
      expect(gate.lastAppliedSequence, 2);
      expect(gate.terminalApplied, isTrue);
    },
  );

  test(
    'zero-based first events and terminals from the contract are admitted',
    () {
      final gate = ExecutionEventGate(_identity());
      final first = _event(sequence: 0);

      expect(gate.admit(first), EventDisposition.applied);
      expect(gate.lastAppliedSequence, 0);
      expect(gate.admit(_event(sequence: 0)), EventDisposition.outOfOrder);

      // A job whose only event is a zero-based terminal is representable too.
      final terminalGate = ExecutionEventGate(_identity());
      final terminal = _event(sequence: 0, kind: EventKind.terminal);

      expect(terminalGate.admit(terminal), EventDisposition.applied);
      expect(terminalGate.admit(terminal), EventDisposition.duplicate);
      expect(terminalGate.lastAppliedSequence, 0);
      expect(terminalGate.terminalApplied, isTrue);
    },
  );

  test(
    'each identity component mismatch is stale, including old snapshots',
    () {
      final current = _identity();
      final gate = ExecutionEventGate(current);
      final events = <ExecutionEvent>[
        _event(identity: _identity(jobId: 'job-2'), sequence: 0),
        _event(identity: _identity(executionId: 'exec-2'), sequence: 0),
        _event(
          identity: _identity(inputSnapshotDigest: _otherSnapshot),
          sequence: 0,
        ),
      ];

      for (final event in events) {
        expect(event.identity == current, isFalse);
        expect(gate.admit(event), EventDisposition.stale);
      }
      expect(gate.lastAppliedSequence, -1);
      expect(gate.terminalApplied, isFalse);

      // A new snapshot gate cannot admit an event from the previous snapshot,
      // even when its sequence is otherwise perfect.
      final nextGate = ExecutionEventGate(
        _identity(inputSnapshotDigest: _otherSnapshot),
      );
      expect(nextGate.admit(_event(sequence: 0)), EventDisposition.stale);
      expect(
        nextGate.admit(
          _event(
            identity: _identity(inputSnapshotDigest: _otherSnapshot),
            sequence: 0,
          ),
        ),
        EventDisposition.applied,
      );
    },
  );

  test(
    'equal and lower zero-based sequences are outOfOrder before a terminal',
    () {
      final gate = ExecutionEventGate(_identity())..admit(_event(sequence: 2));

      expect(gate.admit(_event(sequence: 2)), EventDisposition.outOfOrder);
      expect(gate.admit(_event(sequence: 1)), EventDisposition.outOfOrder);
      expect(gate.admit(_event(sequence: 0)), EventDisposition.outOfOrder);
      expect(gate.lastAppliedSequence, 2);
      expect(gate.terminalApplied, isFalse);
    },
  );

  test('the terminal is admitted once and an exact replay is duplicate', () {
    final gate = ExecutionEventGate(_identity());
    final terminal = _event(sequence: 2, kind: EventKind.terminal);

    expect(gate.admit(terminal), EventDisposition.applied);
    expect(gate.admit(terminal), EventDisposition.duplicate);
    expect(gate.admit(terminal), EventDisposition.duplicate);
    expect(
      gate.admit(_event(sequence: 3, kind: EventKind.terminal)),
      EventDisposition.afterTerminal,
    );
    expect(
      gate.admit(_event(sequence: 1, kind: EventKind.terminal)),
      EventDisposition.afterTerminal,
    );
    expect(
      gate.admit(_event(sequence: 3, kind: EventKind.partial)),
      EventDisposition.afterTerminal,
    );
    expect(gate.lastAppliedSequence, 2);
    expect(gate.terminalApplied, isTrue);
  });

  test('a higher partial after a terminal is afterTerminal', () {
    final gate = ExecutionEventGate(_identity())
      ..admit(_event(sequence: 0))
      ..admit(_event(sequence: 8, kind: EventKind.terminal));

    expect(
      gate.admit(_event(sequence: 9, kind: EventKind.partial)),
      EventDisposition.afterTerminal,
    );
    expect(
      gate.admit(_event(sequence: 100, kind: EventKind.partial)),
      EventDisposition.afterTerminal,
    );
    expect(gate.lastAppliedSequence, 8);
    expect(gate.terminalApplied, isTrue);
  });

  test('a stale event after a terminal is stale, not duplicate', () {
    final gate = ExecutionEventGate(_identity())
      ..admit(_event(sequence: 0, kind: EventKind.terminal));

    final staleTerminal = _event(
      identity: _identity(executionId: 'exec-2'),
      sequence: 0,
      kind: EventKind.terminal,
    );
    expect(gate.admit(staleTerminal), EventDisposition.stale);
    expect(gate.lastAppliedSequence, 0);
  });

  test('invalid ids, digests and negative sequences fail closed', () {
    for (final jobId in <String>['Job-1', '', '1job']) {
      expect(
        () => _identity(jobId: jobId),
        throwsA(isA<ArgumentError>()),
        reason: 'jobId $jobId',
      );
    }
    for (final executionId in <String>['EXEC-1', '', '-exec']) {
      expect(
        () => _identity(executionId: executionId),
        throwsA(isA<ArgumentError>()),
        reason: 'executionId $executionId',
      );
    }
    for (final digest in <String>['abc', 'A' * 64, 'g' * 64]) {
      expect(
        () => _identity(inputSnapshotDigest: digest),
        throwsA(isA<ArgumentError>()),
      );
    }
    for (final sequence in <int>[-1, -2, -100]) {
      expect(
        () => _event(sequence: sequence),
        throwsA(isA<ArgumentError>()),
        reason: 'sequence $sequence',
      );
    }
    expect(
      () => _event(sequence: -1),
      throwsA(
        isA<ArgumentError>().having((e) => e.invalidValue, 'invalidValue', -1),
      ),
    );
    expect(() => _event(sequence: 0), returnsNormally);
  });

  test('identity equality and hashCode cover every field', () {
    expect(_identity(), _identity());
    expect(_identity().hashCode, _identity().hashCode);
    expect(_identity(jobId: 'job-2') == _identity(), isFalse);
    expect(_identity(executionId: 'exec-2') == _identity(), isFalse);
    expect(
      _identity(inputSnapshotDigest: _otherSnapshot) == _identity(),
      isFalse,
    );
  });

  test('event equality and hashCode cover identity, sequence and kind', () {
    final identity = _identity();
    expect(
      _event(identity: identity, sequence: 2),
      _event(identity: identity, sequence: 2),
    );
    expect(
      _event(identity: identity, sequence: 2).hashCode,
      _event(identity: identity, sequence: 2).hashCode,
    );
    expect(
      _event(identity: identity, sequence: 2) ==
          _event(identity: identity, sequence: 3),
      isFalse,
    );
    expect(
      _event(identity: identity, sequence: 2) ==
          _event(identity: identity, sequence: 2, kind: EventKind.terminal),
      isFalse,
    );
    expect(
      _event(identity: identity, sequence: 2) ==
          _event(identity: _identity(jobId: 'job-2'), sequence: 2),
      isFalse,
    );
    expect(
      _event(identity: identity, sequence: 2).hashCode ==
          _event(identity: identity, sequence: 3).hashCode,
      isFalse,
    );
  });

  test('toString names only ids, order and kind', () {
    final text = _event(sequence: 2, kind: EventKind.terminal).toString();

    expect(text, contains('job-1'));
    expect(text, contains('exec-1'));
    expect(text, contains('2'));
    expect(text, contains('terminal'));
    expect(text, isNot(contains(_snapshot)));
    expect(text, contains('<redacted>'));
  });
}
