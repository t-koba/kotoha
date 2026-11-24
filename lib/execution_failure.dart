/// Report classification labels for a failed execution (design §10.3).
///
/// These labels describe a report, not measured engine or model facts. They
/// make no claim about support, availability or output quality, and assign no
/// liability. Retryability is supplied by the caller, never inferred here.
enum FailureCause {
  /// The supplied input was rejected or could not be processed.
  input,

  /// The caller lacked the needed permission or authorization.
  authorization,

  /// A local resource (memory, storage, time) was unavailable.
  resource,

  /// An engine call reported a failure.
  engine,

  /// The caller cancelled the operation.
  cancellation,

  /// No more specific classification was supplied.
  unknown,
}

/// An immutable report of a failed execution (design §10.3).
///
/// Holds a cause classification, caller-supplied retryability, stable labels
/// for the affected artifacts, the action required of the caller, and two
/// separate explanations: one safe to show to a user and one for developer
/// diagnosis. This is a value object only: it performs no I/O, engine,
/// network or persistence work, wires no UI, and makes no support,
/// availability, quality or liability claim.
class ExecutionFailure implements Exception {
  static const int _maxUserExplanationLength = 300;
  static const int _maxRequiredActionLength = 200;
  static const int _maxDeveloperDiagnosticLength = 2000;

  ExecutionFailure({
    required this.cause,
    required this.retryable,
    required Set<String> affectedArtifacts,
    required String requiredAction,
    required String userExplanation,
    required String developerDiagnostic,
  }) : affectedArtifacts = _validatedArtifacts(affectedArtifacts),
       requiredAction = _validatedText(
         requiredAction,
         'requiredAction',
         _maxRequiredActionLength,
       ),
       userExplanation = _validatedUserExplanation(userExplanation),
       developerDiagnostic = _validatedDeveloperDiagnostic(developerDiagnostic);

  final FailureCause cause;
  final bool retryable;

  /// Sorted, unmodifiable local artifact labels (never paths or digests).
  final Set<String> affectedArtifacts;

  /// The action the caller must take, free of technical detail.
  final String requiredAction;

  /// A short, non-technical explanation safe to show to a user.
  final String userExplanation;

  /// Technical detail for developers; never shown as user-facing text.
  final String developerDiagnostic;

  /// Classification and report fields only; no I/O or serialization.
  Map<String, Object?> toJson() => <String, Object?>{
    'cause': cause.name,
    'retryable': retryable,
    'affectedArtifacts': affectedArtifacts.toList(),
    'requiredAction': requiredAction,
    'userExplanation': userExplanation,
    'developerDiagnostic': developerDiagnostic,
  };

  static Set<String> _validatedArtifacts(Set<String> labels) {
    if (labels.isEmpty) {
      throw ArgumentError.value(
        labels,
        'affectedArtifacts',
        'must not be empty',
      );
    }
    for (final label in labels) {
      if (!_artifactLabelPattern.hasMatch(label) ||
          _digestPattern.hasMatch(label)) {
        throw ArgumentError.value(
          labels,
          'affectedArtifacts',
          'must contain only stable lowercase artifact labels',
        );
      }
    }
    final sorted = labels.toList()..sort();
    return Set<String>.unmodifiable(sorted);
  }

  static String _validatedUserExplanation(String value) {
    final text = _validatedText(
      value,
      'userExplanation',
      _maxUserExplanationLength,
    );
    if (_pathLikePattern.hasMatch(text) || _digestPattern.hasMatch(text)) {
      throw ArgumentError.value(
        value,
        'userExplanation',
        'must not contain paths, URLs or digests',
      );
    }
    return text;
  }

  static String _validatedDeveloperDiagnostic(String value) {
    final text = _validatedText(
      value,
      'developerDiagnostic',
      _maxDeveloperDiagnosticLength,
    );
    if (_digestPattern.hasMatch(text)) {
      throw ArgumentError.value(
        value,
        'developerDiagnostic',
        'must not contain digests',
      );
    }
    return text;
  }

  static String _validatedText(String value, String name, int maxLength) {
    if (_controlCharacterPattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        name,
        'must not contain control characters',
      );
    }
    final text = value.trim();
    if (text.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    if (text.runes.length > maxLength) {
      throw ArgumentError.value(
        value,
        name,
        'must be at most $maxLength characters',
      );
    }
    return text;
  }
}

final RegExp _artifactLabelPattern = RegExp(r'^[a-z][a-z0-9._-]{0,63}$');
final RegExp _digestPattern = RegExp(r'[0-9a-fA-F]{64}');
final RegExp _pathLikePattern = RegExp(
  r'[/\\]|(?:file|https?)://',
  caseSensitive: false,
);
final RegExp _controlCharacterPattern = RegExp(r'\p{Cc}', unicode: true);
