/// A single, fail-closed decision combining digest consent, the installed
/// binding and declaration-level plan eligibility (design §7.4, §7.5, §6.2).
///
/// This is purely a declaration/consent/registry decision. It reads no files,
/// invokes no engine, uses no networking or persistence, creates no leases,
/// never activates or deactivates models, and does not mutate consent records.
/// A positive result is NOT engine authorization, runtime support, origin or
/// authenticity verification, license approval, or quality evidence. Digests
/// and declared capabilities prove only that the declarations match.
library;

import 'consent_store.dart';
import 'execution_plan.dart';
import 'model_registry.dart';
import 'model_terms_import.dart';

/// Reasons a model use is not allowed by the declaration-level gate.
///
/// Failures carry no path, provider name, digest, model id or content.
enum ModelUseGateFailure {
  /// No unique active consent receipt covers the declared bindings.
  consentMissing,

  /// The active receipt was granted for another model.
  consentScopeMismatch,

  /// The declared manifest digest is not installed in the registry.
  notInstalled,

  /// The installed binding was accepted under different terms.
  bindingMismatch,

  /// The request does not match the model's declared capabilities.
  declarationIneligible,
}

/// Immutable outcome of [evaluateModelUse].
///
/// Exposes only failure categories and declaration-level plan reasons: never
/// paths, digests, model ids, provider names, content or runtime state.
class ModelUseGateDecision {
  const ModelUseGateDecision._(this._failures, this._planReasons);

  final Set<ModelUseGateFailure> _failures;
  final Set<PlanIneligibility> _planReasons;

  /// Every independent reason the gate refused the use; empty when eligible.
  Set<ModelUseGateFailure> get failures => _failures;

  /// Declaration reasons from [evaluateDeclaredEligibility], when it failed.
  Set<PlanIneligibility> get planReasons => _planReasons;

  /// Whether all three declaration-level checks passed.
  ///
  /// This says nothing about engine authorization, runtime availability,
  /// origin, licensing or output quality.
  bool get eligible => failures.isEmpty;
}

/// Collects consent, registry and declaration failures in one fail-closed
/// decision; a failure in one area does not skip the other checks.
///
/// [authorization] is the digest binding from an accepted review; its
/// capabilities are manifest declarations, not verified runtime support.
/// Ambiguous consent fails closed: consent is used only when [consents] returns
/// one unique active receipt, and that receipt must name [modelId].
ModelUseGateDecision evaluateModelUse({
  required ConsentStore consents,
  required ModelRegistry registry,
  required EphemeralModelAuthorization authorization,
  required ConsentPurpose purpose,
  required String modelId,
  required String capabilityId,
  required PlanRequest request,
}) {
  final failures = <ModelUseGateFailure>{};
  final planReasons = <PlanIneligibility>{};

  final receipt = consents.activeFor(
    authorization.manifestDigest,
    authorization.termsDigest,
    purpose,
    capabilityId,
  );
  if (receipt == null) {
    failures.add(ModelUseGateFailure.consentMissing);
  } else if (receipt.scope.modelId != modelId) {
    failures.add(ModelUseGateFailure.consentScopeMismatch);
  }

  final installed = registry.lookup(authorization.manifestDigest);
  if (installed == null) {
    failures.add(ModelUseGateFailure.notInstalled);
  } else if (installed.termsDigest != authorization.termsDigest) {
    failures.add(ModelUseGateFailure.bindingMismatch);
  }

  final eligibility = evaluateDeclaredEligibility(
    request,
    authorization.capabilities,
    capabilityId,
  );
  if (!eligibility.eligible) {
    failures.add(ModelUseGateFailure.declarationIneligible);
    planReasons.addAll(eligibility.reasons);
  }

  return ModelUseGateDecision._(
    Set<ModelUseGateFailure>.unmodifiable(failures),
    Set<PlanIneligibility>.unmodifiable(planReasons),
  );
}
