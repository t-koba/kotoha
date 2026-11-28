import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/consent_store.dart';
import 'package:kotoha/execution_plan.dart';
import 'package:kotoha/model_capabilities.dart';
import 'package:kotoha/model_registry.dart';
import 'package:kotoha/model_terms_import.dart';
import 'package:kotoha/model_use_gate.dart';

const String _manifestDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _termsDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _otherDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _modelId = 'synthetic-translation';
const String _otherModelId = 'other-translation';
const String _capabilityId = 'translation.text';

final DateTime _grantedAt = DateTime.utc(2026, 1, 1);

PlanRequest _request({
  String inputType = 'text',
  String outputType = 'translations',
  String sourceLanguage = 'de',
  String targetLanguage = 'ar',
  int storageBudgetBytes = 100,
  int hostBudgetBytes = 10,
  int acceleratorBudgetBytes = 10,
}) => PlanRequest(
  inputType: inputType,
  outputType: outputType,
  sourceLanguage: sourceLanguage,
  targetLanguage: targetLanguage,
  storageBudgetBytes: storageBudgetBytes,
  hostBudgetBytes: hostBudgetBytes,
  acceleratorBudgetBytes: acceleratorBudgetBytes,
);

DeclaredModelCapabilities _capabilities({
  String capabilityId = _capabilityId,
  List<String> inputTypes = const ['text'],
  List<String> outputTypes = const ['translations'],
  int storageBytes = 32,
}) => DeclaredModelCapabilities(
  modelId: _modelId,
  engineId: 'synthetic-engine',
  adapterId: 'synthetic-adapter',
  tasks: [
    DeclaredTaskCapability(
      id: capabilityId,
      inputTypes: inputTypes,
      outputTypes: outputTypes,
      sourceLanguages: const ['de'],
      targetLanguages: const ['ar'],
      scripts: const ['Latn', 'Arab'],
      routes: const [
        DeclaredRoute(
          source: 'de',
          target: 'ar',
          evidence: DeclaredRouteEvidence.user,
        ),
      ],
    ),
  ],
  requiredCapabilities: const [_capabilityId],
  resources: DeclaredResourceNeeds(
    storageBytes: storageBytes,
    peakHostBytes: 0,
    peakAcceleratorBytes: 0,
    basis: 'declared',
    conditions: 'synthetic declaration',
  ),
);

ConsentReceipt _receipt({
  String id = 'receipt-1',
  String manifestDigest = _manifestDigest,
  String termsDigest = _termsDigest,
  ConsentPurpose purpose = ConsentPurpose.translation,
  String modelId = _modelId,
  Set<String> capabilityIds = const {_capabilityId},
  bool revoked = false,
}) => ConsentReceipt(
  id: id,
  manifestDigest: manifestDigest,
  termsDigest: termsDigest,
  purpose: purpose,
  scope: ConsentScope(modelId: modelId, capabilityIds: capabilityIds),
  grantedAt: _grantedAt,
  revoked: revoked,
);

EphemeralModelAuthorization _authorization({
  String manifestDigest = _manifestDigest,
  String termsDigest = _termsDigest,
  DeclaredModelCapabilities? capabilities,
}) => EphemeralModelAuthorization(
  manifestDigest,
  termsDigest,
  const <DeclaredModelFile>[],
  capabilities ?? _capabilities(),
);

ConsentStore _consentsWith(List<ConsentReceipt> receipts) {
  final store = ConsentStore();
  for (final receipt in receipts) {
    store.grant(receipt);
  }
  return store;
}

ModelRegistry _registryWith(EphemeralModelAuthorization authorization) {
  final registry = ModelRegistry();
  registry.install(authorization);
  return registry;
}

ModelUseGateDecision _evaluate({
  ConsentStore? consents,
  ModelRegistry? registry,
  EphemeralModelAuthorization? authorization,
  ConsentPurpose purpose = ConsentPurpose.translation,
  String modelId = _modelId,
  String capabilityId = _capabilityId,
  PlanRequest? request,
}) {
  final effectiveAuthorization = authorization ?? _authorization();
  return evaluateModelUse(
    consents: consents ?? _consentsWith([_receipt()]),
    registry: registry ?? _registryWith(effectiveAuthorization),
    authorization: effectiveAuthorization,
    purpose: purpose,
    modelId: modelId,
    capabilityId: capabilityId,
    request: request ?? _request(),
  );
}

// That the gate performs no I/O, engine call, lease or consent mutation cannot
// be probed at runtime in pure Dart. It is structural: lib/model_use_gate.dart
// imports only the four declaration/consent/registry libraries, and the state
// snapshots below cover every mutable object the gate receives.
void main() {
  test('eligible when consent, binding and declarations agree', () {
    final decision = _evaluate();

    expect(decision.eligible, isTrue);
    expect(decision.failures, isEmpty);
    expect(decision.planReasons, isEmpty);
  });

  test('failure and reason sets are unmodifiable', () {
    final decision = _evaluate();

    expect(
      () => decision.failures.add(ModelUseGateFailure.consentMissing),
      throwsUnsupportedError,
    );
    expect(
      () => decision.planReasons.add(PlanIneligibility.resource),
      throwsUnsupportedError,
    );
  });

  test('no consent fails closed', () {
    final decision = _evaluate(consents: ConsentStore());

    expect(decision.eligible, isFalse);
    expect(decision.failures, {ModelUseGateFailure.consentMissing});
    expect(decision.planReasons, isEmpty);
  });

  test('revoked consent fails closed', () {
    final consents = _consentsWith([_receipt()]);
    expect(consents.revoke('receipt-1'), isTrue);

    expect(_evaluate(consents: consents).failures, {
      ModelUseGateFailure.consentMissing,
    });
  });

  test('ambiguous active consent is never coverage', () {
    final consents = _consentsWith([
      _receipt(id: 'receipt-1'),
      _receipt(id: 'receipt-2', modelId: _otherModelId),
    ]);
    expect(
      consents.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        _capabilityId,
      ),
      isNull,
    );

    final decision = _evaluate(consents: consents);
    expect(decision.failures, {ModelUseGateFailure.consentMissing});
  });

  test('consent for another model reports a scope mismatch', () {
    final consents = _consentsWith([_receipt(modelId: _otherModelId)]);

    final decision = _evaluate(consents: consents);
    expect(decision.failures, {ModelUseGateFailure.consentScopeMismatch});
  });

  test('wrong consent purpose, terms digest or capability is not coverage', () {
    final cases = <ConsentStore>[
      _consentsWith([_receipt(purpose: ConsentPurpose.ocr)]),
      _consentsWith([_receipt(termsDigest: _otherDigest)]),
      _consentsWith([
        _receipt(capabilityIds: const {'ocr.text'}),
      ]),
    ];
    for (final consents in cases) {
      expect(_evaluate(consents: consents).failures, {
        ModelUseGateFailure.consentMissing,
      });
    }
  });

  test('authorization digests that consent does not cover fail closed', () {
    final authorization = _authorization(termsDigest: _otherDigest);

    final decision = _evaluate(authorization: authorization);
    expect(decision.failures, {ModelUseGateFailure.consentMissing});
  });

  test('wrong evaluation purpose or capability cannot reuse consent', () {
    expect(_evaluate(purpose: ConsentPurpose.asr).failures, {
      ModelUseGateFailure.consentMissing,
    });
    expect(_evaluate(capabilityId: 'ocr.text').failures, {
      ModelUseGateFailure.consentMissing,
      ModelUseGateFailure.declarationIneligible,
    });
  });

  test('uninstalled manifest digest fails closed', () {
    final decision = _evaluate(registry: ModelRegistry());

    expect(decision.eligible, isFalse);
    expect(decision.failures, {ModelUseGateFailure.notInstalled});
  });

  test('installed binding accepted under other terms fails closed', () {
    final authorization = _authorization();
    final registry = _registryWith(_authorization(termsDigest: _otherDigest));

    final decision = _evaluate(
      registry: registry,
      authorization: authorization,
    );
    expect(decision.failures, {ModelUseGateFailure.bindingMismatch});
  });

  test('unknown capability preserves the unknownTask plan reason', () {
    // Consent covers the requested capability, but the manifest declares only
    // translation.text, so the declaration check alone must fail.
    final consents = _consentsWith([
      _receipt(capabilityIds: const {'ocr.text'}),
    ]);
    final decision = _evaluate(consents: consents, capabilityId: 'ocr.text');

    expect(decision.failures, {ModelUseGateFailure.declarationIneligible});
    expect(decision.planReasons, {PlanIneligibility.unknownTask});
  });

  test('resource budget overrun preserves the resource plan reason', () {
    final decision = _evaluate(request: _request(storageBudgetBytes: 1));

    expect(decision.failures, {ModelUseGateFailure.declarationIneligible});
    expect(decision.planReasons, {PlanIneligibility.resource});
  });

  test('all declaration reasons are copied into planReasons', () {
    final decision = _evaluate(
      request: _request(
        inputType: 'image',
        outputType: 'text',
        sourceLanguage: 'fr',
        targetLanguage: 'ja',
        storageBudgetBytes: 1,
      ),
    );

    expect(decision.failures, {ModelUseGateFailure.declarationIneligible});
    expect(decision.planReasons, {
      PlanIneligibility.inputType,
      PlanIneligibility.outputType,
      PlanIneligibility.route,
      PlanIneligibility.resource,
    });
  });

  test('all independent failures are collected together', () {
    final decision = _evaluate(
      consents: ConsentStore(),
      registry: ModelRegistry(),
      capabilityId: 'ocr.text',
    );

    expect(decision.failures, {
      ModelUseGateFailure.consentMissing,
      ModelUseGateFailure.notInstalled,
      ModelUseGateFailure.declarationIneligible,
    });
    expect(decision.planReasons, {PlanIneligibility.unknownTask});
  });

  test(
    'evaluation leaves activation, leases and consent records untouched',
    () {
      final consents = _consentsWith([
        _receipt(),
        _receipt(id: 'old-receipt', purpose: ConsentPurpose.ocr),
      ]);
      consents.revoke('old-receipt');
      final registry = _registryWith(_authorization());
      registry.activate(_manifestDigest);
      final lease = registry.pin(_manifestDigest);

      final receiptsBefore = List<ConsentReceipt>.of(consents.receipts);
      final installedBefore = registry.installedIds.toList();

      expect(
        _evaluate(consents: consents, registry: registry).eligible,
        isTrue,
      );
      expect(
        _evaluate(
          consents: consents,
          registry: registry,
          request: _request(storageBudgetBytes: 1),
        ).failures,
        {ModelUseGateFailure.declarationIneligible},
      );
      expect(
        _evaluate(consents: ConsentStore(), registry: ModelRegistry()).failures,
        {ModelUseGateFailure.consentMissing, ModelUseGateFailure.notInstalled},
      );

      expect(registry.activeId, _manifestDigest);
      expect(registry.leaseCount(_manifestDigest), 1);
      expect(registry.installedIds, installedBefore);
      expect(registry.lookup(_manifestDigest)!.termsDigest, _termsDigest);
      expect(consents.receipts, receiptsBefore);
      registry.release(lease);
    },
  );
}
