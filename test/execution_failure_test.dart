import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/execution_failure.dart';

ExecutionFailure failure({
  FailureCause cause = FailureCause.engine,
  bool retryable = false,
  Set<String>? affectedArtifacts,
  String requiredAction = 'Retry the operation.',
  String userExplanation = 'The operation could not be completed.',
  String developerDiagnostic = 'engine call returned status 7',
}) {
  return ExecutionFailure(
    cause: cause,
    retryable: retryable,
    affectedArtifacts: affectedArtifacts ?? const <String>{'output.document'},
    requiredAction: requiredAction,
    userExplanation: userExplanation,
    developerDiagnostic: developerDiagnostic,
  );
}

void expectFieldRejected(
  String field,
  ExecutionFailure Function() build, {
  String? reason,
  Iterable<String> forbidden = const <String>[],
}) {
  try {
    build();
    fail('Expected $field to be rejected');
  } on ArgumentError catch (error) {
    expect(error.name, field);
    if (reason != null) {
      expect(error.message, reason);
    }
    for (final content in forbidden) {
      expect(error.toString(), isNot(contains(content)));
      expect(error.invalidValue?.toString(), isNot(contains(content)));
    }
  }
}

void main() {
  test('valid construction exposes all fields', () {
    final report = failure(
      cause: FailureCause.input,
      retryable: true,
      affectedArtifacts: const <String>{'output.document'},
    );
    expect(report, isA<Exception>());
    expect(report.cause, FailureCause.input);
    expect(report.retryable, isTrue);
    expect(report.affectedArtifacts, <String>{'output.document'});
    expect(report.requiredAction, 'Retry the operation.');
    expect(report.userExplanation, 'The operation could not be completed.');
    expect(report.developerDiagnostic, 'engine call returned status 7');
  });

  test('artifacts are sorted, copied and unmodifiable', () {
    final labels = <String>{'output.video', 'output.text', 'output.audio'};
    final report = failure(affectedArtifacts: labels);
    expect(report.affectedArtifacts.toList(), <String>[
      'output.audio',
      'output.text',
      'output.video',
    ]);
    labels.add('output.new');
    labels.clear();
    expect(report.affectedArtifacts, <String>{
      'output.audio',
      'output.text',
      'output.video',
    });
    expect(
      () => report.affectedArtifacts.add('output.extra'),
      throwsUnsupportedError,
    );
    expect(() => report.affectedArtifacts.clear(), throwsUnsupportedError);
  });

  test('empty or whitespace-only text fields are rejected', () {
    for (final field in <String>[
      'requiredAction',
      'userExplanation',
      'developerDiagnostic',
    ]) {
      for (final value in <String>['', '   ']) {
        expectFieldRejected(field, () => failureByField(field, value));
      }
    }
  });

  test('control characters are rejected in every text field', () {
    for (final field in <String>[
      'requiredAction',
      'userExplanation',
      'developerDiagnostic',
    ]) {
      expectFieldRejected(
        field,
        () => failureByField(field, 'before\u0001after'),
      );
      expectFieldRejected(field, () => failureByField(field, 'before\nafter'));
    }
  });

  test('bidi format controls are rejected in every text field', () {
    for (final field in <String>[
      'requiredAction',
      'userExplanation',
      'developerDiagnostic',
    ]) {
      expectFieldRejected(
        field,
        () => failureByField(field, 'before\u202Eafter'),
      );
      expectFieldRejected(
        field,
        () => failureByField(field, 'before\u202Cafter'),
      );
    }
  });

  test('rejection errors keep field and reason without caller content', () {
    const privatePath = 'reinstall from /home/alice/Private/secret.gguf';
    const pathReason = 'must not contain paths, URLs or digests';
    for (final field in <String>['requiredAction', 'userExplanation']) {
      expectFieldRejected(
        field,
        () => failureByField(field, privatePath),
        reason: pathReason,
        forbidden: <String>[privatePath, 'secret.gguf', '/home/alice/Private'],
      );
    }

    final digest = 'a' * 64;
    expectFieldRejected(
      'developerDiagnostic',
      () => failure(developerDiagnostic: 'hash $digest'),
      reason: 'must not contain digests',
      forbidden: <String>[digest],
    );

    final labels = <String>{'output.document', 'private.output/secret'};
    expectFieldRejected(
      'affectedArtifacts',
      () => failure(affectedArtifacts: labels),
      reason: 'must contain only stable lowercase artifact labels',
      forbidden: labels,
    );

    const bidi = 'before\u202Eafter';
    expectFieldRejected(
      'userExplanation',
      () => failure(userExplanation: bidi),
      reason: 'must not contain control characters',
      forbidden: <String>[bidi, '\u202E'],
    );
  });

  test('artifact labels must be lowercase stable labels', () {
    for (final labels in <Set<String>>[
      <String>{'Output.Document'},
      <String>{'1output'},
      <String>{'output/document'},
      <String>{'output document'},
      <String>{'a' * 65},
      <String>{'a' * 64},
      <String>{'../output'},
    ]) {
      expectFieldRejected(
        'affectedArtifacts',
        () => failure(affectedArtifacts: labels),
      );
    }
  });

  test('an empty artifact set is rejected', () {
    expectFieldRejected(
      'affectedArtifacts',
      () => failure(affectedArtifacts: const <String>{}),
    );
  });

  test('user explanation rejects paths, schemes and digests', () {
    for (final text in <String>[
      'see /tmp/file',
      r'use C:\temp',
      'file://host/path',
      'http://example.test',
      'https://example.test',
      'digest ${'a' * 64}',
      'digest ${'A' * 64}',
    ]) {
      expectFieldRejected(
        'userExplanation',
        () => failure(userExplanation: text),
      );
    }
  });

  test('required action rejects paths, schemes and digests', () {
    for (final text in <String>[
      'see /tmp/file',
      r'use C:\temp',
      'file://host/path',
      'http://example.test',
      'https://example.test',
      'digest ${'a' * 64}',
      'digest ${'A' * 64}',
      'edit /tmp/secret.txt then retry',
      'visit https://internal.example/token',
      'verify ${'a' * 64}',
    ]) {
      expectFieldRejected(
        'requiredAction',
        () => failure(requiredAction: text),
      );
    }
  });

  test('developer diagnostic rejects digests but allows technical detail', () {
    expectFieldRejected(
      'developerDiagnostic',
      () => failure(developerDiagnostic: 'hash ${'b' * 64}'),
    );
    final report = failure(
      developerDiagnostic: 'engine at /tmp/engine.log returned status 7',
    );
    expect(
      report.developerDiagnostic,
      'engine at /tmp/engine.log returned status 7',
    );
  });

  test('overlong text fields are rejected', () {
    expectFieldRejected(
      'userExplanation',
      () => failure(userExplanation: 'u' * 301),
    );
    expectFieldRejected(
      'requiredAction',
      () => failure(requiredAction: 'a' * 201),
    );
    expectFieldRejected(
      'developerDiagnostic',
      () => failure(developerDiagnostic: 'd' * 2001),
    );
    expect(failure(userExplanation: 'u' * 300).userExplanation.length, 300);
  });

  test('retryability is caller-supplied for every cause', () {
    for (final cause in FailureCause.values) {
      expect(failure(cause: cause, retryable: true).retryable, isTrue);
      expect(failure(cause: cause, retryable: false).retryable, isFalse);
    }
  });

  test('each cause is a distinct classification label', () {
    expect(FailureCause.values.map((cause) => cause.name).toList(), <String>[
      'input',
      'authorization',
      'resource',
      'engine',
      'cancellation',
      'unknown',
    ]);
    for (final cause in FailureCause.values) {
      expect(failure(cause: cause).cause, cause);
    }
  });

  test('toJson contains only classification and report fields', () {
    final report = failure(
      cause: FailureCause.cancellation,
      retryable: true,
      affectedArtifacts: const <String>{'output.text', 'output.audio'},
    );
    expect(report.toJson(), <String, Object?>{
      'cause': 'cancellation',
      'retryable': true,
      'affectedArtifacts': <String>['output.audio', 'output.text'],
      'requiredAction': 'Retry the operation.',
      'userExplanation': 'The operation could not be completed.',
      'developerDiagnostic': 'engine call returned status 7',
    });
  });
}

ExecutionFailure failureByField(String field, String value) {
  switch (field) {
    case 'requiredAction':
      return failure(requiredAction: value);
    case 'userExplanation':
      return failure(userExplanation: value);
    default:
      return failure(developerDiagnostic: value);
  }
}
