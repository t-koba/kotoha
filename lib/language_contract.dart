/// Developer-facing mirror of the model-manifest and engine-event
/// language-text contracts checked by design/specs/validate_specs.py.
///
/// Pure in-memory string check: the caller supplies already-decoded text and
/// this library performs no file I/O, JSON parsing, network, engine or model
/// work. A valid result means those supplied strings agree with the declared
/// contract; it makes no claim about language support, registry coverage,
/// translation quality or adoption.
library;

/// Canonical description shared by the four model-manifest language fields.
const String languageTagDescription =
    'BCP 47 §2.1の構造と重複 variant/singleton を検査した言語タグ。レジストリによる登録情報・正規形の照合は行わない。';

/// Claim that must not appear in a language description.
const String languageTagClaim = '正規形の言語タグ。実行時にBCP 47の構文・登録情報と照合する。';

/// Contract sentence required once in the specs README and once as a
/// paragraph in the HTML acceptance mirror.
const String languageContractSentence =
    '言語タグのBCP 47構造検査（§2.1のABNF、重複 variant/singleton なし）は言語アダプターが担当する。登録情報と正規形の照合は日付付きIANAレジストリを同梱するまでは行わない。付属検査はフィールドの構文と参照整合を扱う。個別言語の翻訳品質は評価プロファイルで測定する。';

/// Stable reason a supplied language-contract text set is rejected.
enum LanguageContractViolation {
  /// The four source/target language descriptions are not all present.
  descriptionCount,

  /// A supplied language description contains the registry-validation claim.
  registryValidationClaim,

  /// A supplied language description differs from the canonical text.
  canonicalDescription,

  /// The model-schema HTML excerpt does not contain four canonical texts.
  htmlDescriptionCount,

  /// The model-schema HTML excerpt contains the registry-validation claim.
  htmlRegistryValidationClaim,

  /// The README does not contain the contract sentence exactly once.
  readmeContractSentence,

  /// The HTML does not contain the contract sentence as a paragraph.
  htmlContractSentence,

  /// The two engine-event language descriptions are not both present.
  engineDescriptionCount,

  /// An engine-event description contains the registry-validation claim.
  engineRegistryValidationClaim,

  /// An engine-event description differs from the canonical text.
  engineCanonicalDescription,

  /// The engine-schema HTML excerpt does not contain two canonical texts.
  engineHtmlDescriptionCount,

  /// The engine-schema HTML excerpt contains the registry-validation claim.
  engineHtmlRegistryValidationClaim,
}

/// Already-decoded engine-event strings to check against the contract.
class EngineLanguageContractInput {
  /// Creates an immutable input set.
  const EngineLanguageContractInput({
    required this.descriptions,
    required this.engineHtml,
  });

  /// The `source_language` and output `language` schema descriptions.
  final List<String> descriptions;

  /// The extracted engine-event schema section of the HTML mirror.
  final String engineHtml;
}

/// Already-decoded strings to check against the language contract.
class LanguageContractInput {
  /// Creates an immutable input set.
  const LanguageContractInput({
    required this.descriptions,
    required this.modelHtml,
    required this.readme,
    required this.html,
  });

  /// The four language descriptions from the model-manifest schema.
  final List<String> descriptions;

  /// The extracted model-manifest schema section of the HTML mirror.
  final String modelHtml;

  /// The specs README text.
  final String readme;

  /// The complete HTML acceptance mirror text.
  final String html;
}

int _count(String haystack, String needle) {
  if (needle.isEmpty) return 0;
  var count = 0;
  var offset = 0;
  while (true) {
    final index = haystack.indexOf(needle, offset);
    if (index < 0) return count;
    count++;
    offset = index + needle.length;
  }
}

/// Returns the first violation, or `null` when the supplied text agrees with
/// the declared language contract.
LanguageContractViolation? validateLanguageContract(
  LanguageContractInput input,
) {
  if (input.descriptions.length != 4) {
    return LanguageContractViolation.descriptionCount;
  }
  if (input.descriptions.any((d) => d.contains(languageTagClaim))) {
    return LanguageContractViolation.registryValidationClaim;
  }
  if (input.descriptions.any((d) => d != languageTagDescription)) {
    return LanguageContractViolation.canonicalDescription;
  }
  if (_count(input.modelHtml, '"description": "$languageTagDescription"') !=
      4) {
    return LanguageContractViolation.htmlDescriptionCount;
  }
  if (input.modelHtml.contains(languageTagClaim)) {
    return LanguageContractViolation.htmlRegistryValidationClaim;
  }
  if (_count(input.readme, languageContractSentence) != 1) {
    return LanguageContractViolation.readmeContractSentence;
  }
  if (!input.html.contains('<p>$languageContractSentence</p>')) {
    return LanguageContractViolation.htmlContractSentence;
  }
  return null;
}

/// Returns the first engine-event violation, or `null` when the supplied text
/// agrees with the declared language contract.
LanguageContractViolation? validateEngineEventLanguageContract(
  EngineLanguageContractInput input,
) {
  if (input.descriptions.length != 2) {
    return LanguageContractViolation.engineDescriptionCount;
  }
  if (input.descriptions.any((d) => d.contains(languageTagClaim))) {
    return LanguageContractViolation.engineRegistryValidationClaim;
  }
  if (input.descriptions.any((d) => d != languageTagDescription)) {
    return LanguageContractViolation.engineCanonicalDescription;
  }
  if (_count(input.engineHtml, '"description": "$languageTagDescription"') !=
      2) {
    return LanguageContractViolation.engineHtmlDescriptionCount;
  }
  if (input.engineHtml.contains(languageTagClaim)) {
    return LanguageContractViolation.engineHtmlRegistryValidationClaim;
  }
  return null;
}
