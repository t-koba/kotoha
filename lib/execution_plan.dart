/// Declaration-level eligibility of a processing request (design §6.2).
///
/// This is a pure, in-memory decision over a caller's request and manifest-
/// declared capabilities. It is not an engine, OS, licence, consent or
/// permission check; it performs no I/O and no model execution, and makes no
/// claim about output quality or runtime availability. A positive result means
/// only that the declared types, route and numbers match the request and its
/// budgets. Declared resource numbers are treated as declarations regardless
/// of their `basis`; they are not measured or verified here.
library;

import 'model_capabilities.dart';

/// A processing request to check against declared capabilities.
///
/// Text tokens are non-empty ASCII tokens of letters, digits, `.`, `_` or `-`,
/// normalized to lowercase exactly once here. Budgets must be non-negative.
class PlanRequest {
  PlanRequest({
    required String inputType,
    required String outputType,
    required String sourceLanguage,
    required String targetLanguage,
    required int storageBudgetBytes,
    required int hostBudgetBytes,
    required int acceleratorBudgetBytes,
  }) : inputType = _token(inputType, 'inputType'),
       outputType = _token(outputType, 'outputType'),
       sourceLanguage = _token(sourceLanguage, 'sourceLanguage'),
       targetLanguage = _token(targetLanguage, 'targetLanguage'),
       storageBudgetBytes = _budget(storageBudgetBytes, 'storageBudgetBytes'),
       hostBudgetBytes = _budget(hostBudgetBytes, 'hostBudgetBytes'),
       acceleratorBudgetBytes = _budget(
         acceleratorBudgetBytes,
         'acceleratorBudgetBytes',
       );

  /// Declared input type requested, normalized to lowercase.
  final String inputType;

  /// Declared output type requested, normalized to lowercase.
  final String outputType;

  /// Source language tag, normalized to lowercase.
  final String sourceLanguage;

  /// Target language tag, normalized to lowercase.
  final String targetLanguage;

  /// Maximum declared storage the caller is willing to accept, in bytes.
  final int storageBudgetBytes;

  /// Maximum declared host memory the caller is willing to accept, in bytes.
  final int hostBudgetBytes;

  /// Maximum declared accelerator memory the caller will accept, in bytes.
  final int acceleratorBudgetBytes;
}

/// Reasons a request can fail declaration-level eligibility.
enum PlanIneligibility {
  /// No task with the supplied id is declared.
  unknownTask,

  /// The declared task does not declare this exact input type.
  inputType,

  /// The declared task does not declare this exact output type.
  outputType,

  /// The task does not declare this exact source/target route.
  route,

  /// A declared resource need is negative or exceeds its budget.
  resource,
}

/// Immutable result of a declaration-level eligibility decision.
class PlanEligibility {
  PlanEligibility(Set<PlanIneligibility> reasons)
    : _reasons = Set<PlanIneligibility>.unmodifiable(
        reasons.toList()..sort((a, b) => a.index.compareTo(b.index)),
      );

  final Set<PlanIneligibility> _reasons;

  /// No declared mismatch or budget overrun was found.
  bool get eligible => _reasons.isEmpty;

  /// All failing reasons, sorted and unmodifiable.
  Set<PlanIneligibility> get reasons => _reasons;

  bool get unknownTask => _reasons.contains(PlanIneligibility.unknownTask);
  bool get inputType => _reasons.contains(PlanIneligibility.inputType);
  bool get outputType => _reasons.contains(PlanIneligibility.outputType);
  bool get route => _reasons.contains(PlanIneligibility.route);
  bool get resource => _reasons.contains(PlanIneligibility.resource);
}

/// Checks a request against one task's declarations via [CapabilityResolver].
///
/// An unknown task id yields only [PlanIneligibility.unknownTask]; otherwise
/// every failing reason is collected. Type support is an exact match after case normalization against
/// the declared types, routes are the resolver's exact declared source/target
/// pairs, and all three declared resource numbers must be non-negative and
/// within the corresponding budget. No other claim is made.
PlanEligibility evaluateDeclaredEligibility(
  PlanRequest request,
  DeclaredModelCapabilities capabilities,
  String capabilityId,
) {
  final resolver = CapabilityResolver(capabilities);
  final task = resolver.capability(capabilityId);
  if (task == null) {
    return PlanEligibility(const {PlanIneligibility.unknownTask});
  }

  final reasons = <PlanIneligibility>{};
  if (!task.inputTypes.any((type) => type.toLowerCase() == request.inputType)) {
    reasons.add(PlanIneligibility.inputType);
  }
  if (!task.outputTypes.any(
    (type) => type.toLowerCase() == request.outputType,
  )) {
    reasons.add(PlanIneligibility.outputType);
  }
  if (!resolver.declaresRoute(
    capabilityId,
    request.sourceLanguage,
    request.targetLanguage,
  )) {
    reasons.add(PlanIneligibility.route);
  }

  final resources = capabilities.resources;
  if (resources.storageBytes < 0 ||
      resources.storageBytes > request.storageBudgetBytes ||
      resources.peakHostBytes < 0 ||
      resources.peakHostBytes > request.hostBudgetBytes ||
      resources.peakAcceleratorBytes < 0 ||
      resources.peakAcceleratorBytes > request.acceleratorBudgetBytes) {
    reasons.add(PlanIneligibility.resource);
  }
  return PlanEligibility(reasons);
}

final RegExp _tokenPattern = RegExp(r'[A-Za-z0-9._-]+');

String _token(String value, String name) {
  final match = _tokenPattern.matchAsPrefix(value);
  if (match == null || match.end != value.length) {
    throw ArgumentError.value(
      value,
      name,
      'must be a non-empty ASCII token of letters, digits, ., _ or -',
    );
  }
  return value.toLowerCase();
}

int _budget(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative');
  }
  return value;
}
