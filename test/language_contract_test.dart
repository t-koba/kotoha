import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/language_contract.dart';

LanguageContractInput _valid() => LanguageContractInput(
  descriptions: List<String>.filled(4, languageTagDescription),
  modelHtml: List<String>.filled(
    4,
    '"description": "$languageTagDescription"\n',
  ).join(),
  readme: languageContractSentence,
  html: '<p>$languageContractSentence</p>',
);

void main() {
  group('validateLanguageContract', () {
    test('accepts the declared text copies', () {
      expect(validateLanguageContract(_valid()), isNull);
    });

    test('requires four language descriptions', () {
      final input = _valid();
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: input.descriptions.sublist(0, 3),
            modelHtml: input.modelHtml,
            readme: input.readme,
            html: input.html,
          ),
        ),
        LanguageContractViolation.descriptionCount,
      );
    });

    test('rejects a registry-validation claim in a description', () {
      final input = _valid();
      final descriptions = List<String>.from(input.descriptions);
      descriptions[1] = '$languageTagDescription $languageTagClaim';
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: descriptions,
            modelHtml: input.modelHtml,
            readme: input.readme,
            html: input.html,
          ),
        ),
        LanguageContractViolation.registryValidationClaim,
      );
    });

    test('rejects a non-canonical description', () {
      final input = _valid();
      final descriptions = List<String>.from(input.descriptions);
      descriptions[2] = 'another description';
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: descriptions,
            modelHtml: input.modelHtml,
            readme: input.readme,
            html: input.html,
          ),
        ),
        LanguageContractViolation.canonicalDescription,
      );
    });

    test('requires four canonical descriptions in the HTML model section', () {
      final input = _valid();
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: input.descriptions,
            modelHtml: input.modelHtml.replaceFirst(
              '"description": "$languageTagDescription"\n',
              '',
            ),
            readme: input.readme,
            html: input.html,
          ),
        ),
        LanguageContractViolation.htmlDescriptionCount,
      );
    });

    test('rejects a registry-validation claim in the HTML model section', () {
      final input = _valid();
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: input.descriptions,
            modelHtml: '$languageTagClaim ${input.modelHtml}',
            readme: input.readme,
            html: input.html,
          ),
        ),
        LanguageContractViolation.htmlRegistryValidationClaim,
      );
    });

    test('requires the README sentence exactly once', () {
      final input = _valid();
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: input.descriptions,
            modelHtml: input.modelHtml,
            readme: '$languageContractSentence $languageContractSentence',
            html: input.html,
          ),
        ),
        LanguageContractViolation.readmeContractSentence,
      );
    });

    test('requires the contract sentence as an HTML paragraph', () {
      final input = _valid();
      expect(
        validateLanguageContract(
          LanguageContractInput(
            descriptions: input.descriptions,
            modelHtml: input.modelHtml,
            readme: input.readme,
            html: '<div>$languageContractSentence</div>',
          ),
        ),
        LanguageContractViolation.htmlContractSentence,
      );
    });
  });

  group('validateEngineEventLanguageContract', () {
    EngineLanguageContractInput validEngine() => EngineLanguageContractInput(
      descriptions: List<String>.filled(2, languageTagDescription),
      engineHtml: List<String>.filled(
        2,
        '"description": "$languageTagDescription"\n',
      ).join(),
    );

    test('accepts the declared text copies', () {
      expect(validateEngineEventLanguageContract(validEngine()), isNull);
    });

    test('requires two language descriptions', () {
      final input = validEngine();
      expect(
        validateEngineEventLanguageContract(
          EngineLanguageContractInput(
            descriptions: input.descriptions.sublist(0, 1),
            engineHtml: input.engineHtml,
          ),
        ),
        LanguageContractViolation.engineDescriptionCount,
      );
    });

    test('rejects a registry-validation claim in a description', () {
      final input = validEngine();
      final descriptions = List<String>.from(input.descriptions);
      descriptions[1] = '$languageTagDescription $languageTagClaim';
      expect(
        validateEngineEventLanguageContract(
          EngineLanguageContractInput(
            descriptions: descriptions,
            engineHtml: input.engineHtml,
          ),
        ),
        LanguageContractViolation.engineRegistryValidationClaim,
      );
    });

    test('rejects a non-canonical description', () {
      final input = validEngine();
      final descriptions = List<String>.from(input.descriptions);
      descriptions[0] = 'another description';
      expect(
        validateEngineEventLanguageContract(
          EngineLanguageContractInput(
            descriptions: descriptions,
            engineHtml: input.engineHtml,
          ),
        ),
        LanguageContractViolation.engineCanonicalDescription,
      );
    });

    test('requires two canonical descriptions in the HTML engine section', () {
      final input = validEngine();
      expect(
        validateEngineEventLanguageContract(
          EngineLanguageContractInput(
            descriptions: input.descriptions,
            engineHtml: input.engineHtml.replaceFirst(
              '"description": "$languageTagDescription"\n',
              '',
            ),
          ),
        ),
        LanguageContractViolation.engineHtmlDescriptionCount,
      );
    });

    test('rejects a registry-validation claim in the HTML engine section', () {
      final input = validEngine();
      expect(
        validateEngineEventLanguageContract(
          EngineLanguageContractInput(
            descriptions: input.descriptions,
            engineHtml: '$languageTagClaim ${input.engineHtml}',
          ),
        ),
        LanguageContractViolation.engineHtmlRegistryValidationClaim,
      );
    });
  });
}
