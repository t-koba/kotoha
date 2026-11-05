/// A manually edited translation. It is never presented as generated output.
class ManualTranslationDraft {
  const ManualTranslationDraft({
    required this.targetLanguage,
    required this.text,
  });

  factory ManualTranslationDraft.empty() =>
      const ManualTranslationDraft(targetLanguage: '', text: '');

  final String targetLanguage;
  final String text;

  ManualTranslationDraft copyWith({String? targetLanguage, String? text}) =>
      ManualTranslationDraft(
        targetLanguage: targetLanguage ?? this.targetLanguage,
        text: text ?? this.text,
      );

  Map<String, Object> toJson() => {
    'target_language': targetLanguage,
    'text': text,
  };

  factory ManualTranslationDraft.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference({'target_language', 'text'}).isNotEmpty ||
        value.keys.toSet().length != 2 ||
        value['target_language'] is! String ||
        value['text'] is! String) {
      throw const FormatException('Invalid manual translation draft.');
    }
    return ManualTranslationDraft(
      targetLanguage: value['target_language'] as String,
      text: value['text'] as String,
    );
  }
}

/// The editable, model-independent text workspace; every translation is manual.
class TextWorkspaceDraft {
  TextWorkspaceDraft({
    required this.sourceLanguage,
    required this.sourceText,
    required List<ManualTranslationDraft> translations,
  }) : translations = List.unmodifiable(translations) {
    if (this.translations.isEmpty) {
      throw ArgumentError.value(
        translations,
        'translations',
        'Must not be empty.',
      );
    }
  }

  factory TextWorkspaceDraft.empty() => TextWorkspaceDraft(
    sourceLanguage: '',
    sourceText: '',
    translations: [ManualTranslationDraft.empty()],
  );

  static const int currentFormatVersion = 1;

  final String sourceLanguage;
  final String sourceText;
  final List<ManualTranslationDraft> translations;

  TextWorkspaceDraft copyWith({
    String? sourceLanguage,
    String? sourceText,
    List<ManualTranslationDraft>? translations,
  }) => TextWorkspaceDraft(
    sourceLanguage: sourceLanguage ?? this.sourceLanguage,
    sourceText: sourceText ?? this.sourceText,
    translations: translations ?? this.translations,
  );

  Map<String, Object> toJson() => {
    'format_version': currentFormatVersion,
    'source_language': sourceLanguage,
    'source_text': sourceText,
    'translations': translations
        .map((translation) => translation.toJson())
        .toList(),
  };

  factory TextWorkspaceDraft.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference({
          'format_version',
          'source_language',
          'source_text',
          'translations',
        }).isNotEmpty ||
        value.keys.toSet().length != 4 ||
        value['format_version'] != currentFormatVersion ||
        value['source_language'] is! String ||
        value['source_text'] is! String ||
        value['translations'] is! List) {
      throw const FormatException('Invalid text workspace draft.');
    }

    final translations = (value['translations'] as List)
        .map(ManualTranslationDraft.fromJson)
        .toList(growable: false);
    if (translations.isEmpty) {
      throw const FormatException(
        'A workspace needs at least one translation.',
      );
    }
    return TextWorkspaceDraft(
      sourceLanguage: value['source_language'] as String,
      sourceText: value['source_text'] as String,
      translations: translations,
    );
  }
}
