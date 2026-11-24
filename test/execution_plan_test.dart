import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/execution_plan.dart';
import 'package:kotoha/model_capabilities.dart';

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
  String id = 'translation.text',
  List<String> inputTypes = const ['text'],
  List<String> outputTypes = const ['translations'],
  List<DeclaredRoute> routes = const [
    DeclaredRoute(
      source: 'de',
      target: 'ar',
      evidence: DeclaredRouteEvidence.user,
    ),
  ],
  int storageBytes = 32,
  int peakHostBytes = 0,
  int peakAcceleratorBytes = 0,
  String basis = 'declared',
}) => DeclaredModelCapabilities(
  modelId: 'synthetic-model',
  engineId: 'synthetic-engine',
  adapterId: 'synthetic-adapter',
  tasks: [
    DeclaredTaskCapability(
      id: id,
      inputTypes: inputTypes,
      outputTypes: outputTypes,
      sourceLanguages: const ['de'],
      targetLanguages: const ['ar'],
      scripts: const ['Latn', 'Arab'],
      routes: routes,
    ),
  ],
  requiredCapabilities: const ['translation.text'],
  resources: DeclaredResourceNeeds(
    storageBytes: storageBytes,
    peakHostBytes: peakHostBytes,
    peakAcceleratorBytes: peakAcceleratorBytes,
    basis: basis,
    conditions: 'synthetic declaration',
  ),
);

void main() {
  test('matching declaration with declared basis is eligible', () {
    final result = evaluateDeclaredEligibility(
      _request(),
      _capabilities(),
      'translation.text',
    );
    expect(result.eligible, isTrue);
    expect(result.reasons, isEmpty);
    expect(result.unknownTask, isFalse);
    expect(result.inputType, isFalse);
    expect(result.outputType, isFalse);
    expect(result.route, isFalse);
    expect(result.resource, isFalse);
  });

  test('declared types are matched case-insensitively like route tags', () {
    final result = evaluateDeclaredEligibility(
      _request(inputType: 'TEXT', outputType: 'Translations'),
      _capabilities(
        inputTypes: const ['TEXT'],
        outputTypes: const ['Translations'],
      ),
      'translation.text',
    );
    expect(result.eligible, isTrue);
    expect(result.reasons, isEmpty);
  });

  test('budgets equal to declared needs are eligible', () {
    final result = evaluateDeclaredEligibility(
      _request(
        storageBudgetBytes: 32,
        hostBudgetBytes: 4,
        acceleratorBudgetBytes: 2,
      ),
      _capabilities(
        storageBytes: 32,
        peakHostBytes: 4,
        peakAcceleratorBytes: 2,
      ),
      'translation.text',
    );
    expect(result.reasons, isEmpty);
  });

  test('each mismatch is reported on its own', () {
    expect(
      evaluateDeclaredEligibility(
        _request(),
        _capabilities(inputTypes: const ['image']),
        'translation.text',
      ).reasons,
      {PlanIneligibility.inputType},
    );
    expect(
      evaluateDeclaredEligibility(
        _request(),
        _capabilities(outputTypes: const ['audio']),
        'translation.text',
      ).reasons,
      {PlanIneligibility.outputType},
    );
    expect(
      evaluateDeclaredEligibility(
        _request(),
        _capabilities(
          routes: const [
            DeclaredRoute(
              source: 'de',
              target: 'en',
              evidence: DeclaredRouteEvidence.provider,
            ),
          ],
        ),
        'translation.text',
      ).reasons,
      {PlanIneligibility.route},
    );
    expect(
      evaluateDeclaredEligibility(
        _request(storageBudgetBytes: 31),
        _capabilities(storageBytes: 32),
        'translation.text',
      ).reasons,
      {PlanIneligibility.resource},
    );
    expect(
      evaluateDeclaredEligibility(
        _request(hostBudgetBytes: 0),
        _capabilities(peakHostBytes: 1),
        'translation.text',
      ).reasons,
      {PlanIneligibility.resource},
    );
    expect(
      evaluateDeclaredEligibility(
        _request(acceleratorBudgetBytes: 0),
        _capabilities(peakAcceleratorBytes: 1),
        'translation.text',
      ).reasons,
      {PlanIneligibility.resource},
    );
  });

  test('independent mismatches are collected together', () {
    final result = evaluateDeclaredEligibility(
      _request(storageBudgetBytes: 0),
      _capabilities(
        inputTypes: const ['image'],
        outputTypes: const ['audio'],
        routes: const [
          DeclaredRoute(
            source: 'de',
            target: 'en',
            evidence: DeclaredRouteEvidence.user,
          ),
        ],
        storageBytes: 1,
      ),
      'translation.text',
    );
    expect(result.eligible, isFalse);
    expect(result.reasons, {
      PlanIneligibility.inputType,
      PlanIneligibility.outputType,
      PlanIneligibility.route,
      PlanIneligibility.resource,
    });
    expect(result.unknownTask, isFalse);
    expect(result.inputType, isTrue);
    expect(result.outputType, isTrue);
    expect(result.route, isTrue);
    expect(result.resource, isTrue);
  });

  test('unknown task reports only unknownTask', () {
    final result = evaluateDeclaredEligibility(
      _request(),
      _capabilities(),
      'ocr.text',
    );
    expect(result.eligible, isFalse);
    expect(result.reasons, {PlanIneligibility.unknownTask});
    expect(result.unknownTask, isTrue);
    expect(result.inputType, isFalse);
    expect(result.outputType, isFalse);
    expect(result.route, isFalse);
    expect(result.resource, isFalse);
  });

  test(
    'request tokens are normalized once and compared case-insensitively',
    () {
      final request = _request(
        inputType: 'TEXT',
        outputType: 'Translations',
        sourceLanguage: 'DE',
        targetLanguage: 'Ar',
      );
      expect(request.inputType, 'text');
      expect(request.outputType, 'translations');
      expect(request.sourceLanguage, 'de');
      expect(request.targetLanguage, 'ar');

      final result = evaluateDeclaredEligibility(
        request,
        _capabilities(
          routes: const [
            DeclaredRoute(
              source: 'DE',
              target: 'AR',
              evidence: DeclaredRouteEvidence.evaluation,
            ),
          ],
        ),
        'translation.text',
      );
      expect(result.reasons, isEmpty);
    },
  );

  test('malformed requests are rejected', () {
    expect(() => _request(inputType: ''), throwsArgumentError);
    expect(() => _request(outputType: ' '), throwsArgumentError);
    expect(() => _request(sourceLanguage: 'de '), throwsArgumentError);
    expect(() => _request(targetLanguage: 'ar\n'), throwsArgumentError);
    expect(() => _request(inputType: 'te xt'), throwsArgumentError);
    expect(() => _request(sourceLanguage: '日本語'), throwsArgumentError);
    expect(() => _request(inputType: 'text/raw'), throwsArgumentError);
    expect(() => _request(storageBudgetBytes: -1), throwsArgumentError);
    expect(() => _request(hostBudgetBytes: -1), throwsArgumentError);
    expect(() => _request(acceleratorBudgetBytes: -1), throwsArgumentError);
  });

  test('negative declared resources are ineligible', () {
    for (final capabilities in [
      _capabilities(storageBytes: -1),
      _capabilities(peakHostBytes: -1),
      _capabilities(peakAcceleratorBytes: -1),
    ]) {
      expect(
        evaluateDeclaredEligibility(
          _request(),
          capabilities,
          'translation.text',
        ).reasons,
        {PlanIneligibility.resource},
      );
    }
  });

  test('reasons are unmodifiable and copied from the caller', () {
    final supplied = <PlanIneligibility>{PlanIneligibility.route};
    final eligibility = PlanEligibility(supplied);
    supplied.add(PlanIneligibility.resource);
    expect(eligibility.reasons, {PlanIneligibility.route});
    expect(
      () => eligibility.reasons.add(PlanIneligibility.unknownTask),
      throwsUnsupportedError,
    );
    expect(() => eligibility.reasons.clear(), throwsUnsupportedError);
  });
}
