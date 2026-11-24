import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/workspace.dart';

void main() {
  test(
    'round-trips multilingual source and independent manual translations',
    () {
      final draft = TextWorkspaceDraft(
        sourceLanguage: 'ja',
        sourceText: 'こんにちは 👋',
        translations: const [
          ManualTranslationDraft(targetLanguage: 'en', text: 'Hello 👋'),
          ManualTranslationDraft(targetLanguage: 'fr', text: 'Bonjour 👋'),
        ],
      );

      final restored = TextWorkspaceDraft.fromJson(
        jsonDecode(jsonEncode(draft.toJson())),
      );

      expect(restored.sourceText, 'こんにちは 👋');
      expect(restored.translations.map((entry) => entry.targetLanguage), [
        'en',
        'fr',
      ]);
      expect(restored.translations.map((entry) => entry.text), [
        'Hello 👋',
        'Bonjour 👋',
      ]);
      expect(restored.translations, hasLength(2));
    },
  );

  test('rejects unsupported formats and empty translation collections', () {
    final invalid = TextWorkspaceDraft.empty().toJson()..['format_version'] = 2;
    expect(() => TextWorkspaceDraft.fromJson(invalid), throwsFormatException);

    // A double that compares numerically equal to the int version is not a
    // supported format version; every other scalar field is strictly typed.
    final doubleVersion = TextWorkspaceDraft.empty().toJson()
      ..['format_version'] = 1.0;
    expect(
      () => TextWorkspaceDraft.fromJson(doubleVersion),
      throwsFormatException,
    );

    final noTranslations = TextWorkspaceDraft.empty().toJson()
      ..['translations'] = [];
    expect(
      () => TextWorkspaceDraft.fromJson(noTranslations),
      throwsFormatException,
    );
  });

  test('snapshots and protects the translation collection', () {
    final supplied = <ManualTranslationDraft>[
      const ManualTranslationDraft(targetLanguage: 'en', text: 'Hello'),
    ];
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: 'こんにちは',
      translations: supplied,
    );

    supplied.add(
      const ManualTranslationDraft(targetLanguage: 'fr', text: 'Bonjour'),
    );
    expect(draft.translations, hasLength(1));
    expect(draft.translations.single.targetLanguage, 'en');
    expect(
      () => draft.translations.add(
        const ManualTranslationDraft(targetLanguage: 'de', text: 'Hallo'),
      ),
      throwsUnsupportedError,
    );
  });

  test('freezes supplied translations against caller mutation', () {
    final supplied = _MutableTranslationDraft(
      targetLanguage: 'en',
      text: 'Hello',
    );
    final draft = TextWorkspaceDraft(
      sourceLanguage: 'ja',
      sourceText: 'こんにちは',
      translations: [supplied],
    );
    final before = draft.toJson();

    supplied.language = 'ja';
    supplied.body = 'Goodbye';

    expect(draft.toJson(), before);
    expect(draft.translations.single.runtimeType, ManualTranslationDraft);
    final restored = TextWorkspaceDraft.fromJson(before);
    expect(restored.toJson(), before);
  });
}

class _MutableTranslationDraft extends ManualTranslationDraft {
  _MutableTranslationDraft({
    required super.targetLanguage,
    required super.text,
  });

  String language = 'en';
  String body = 'Hello';

  @override
  String get targetLanguage => language;

  @override
  String get text => body;

  @override
  Map<String, Object> toJson() => {
    'target_language': targetLanguage,
    'text': text,
    'unexpected': 'caller content',
  };
}
