import 'package:flutter/material.dart';

import 'workspace.dart';

void main() => runApp(const KotohaApp());

class KotohaApp extends StatelessWidget {
  const KotohaApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ことは | Kotoha',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315F58)),
      useMaterial3: true,
    ),
    home: const TextWorkspacePage(),
  );
}

class TextWorkspacePage extends StatefulWidget {
  const TextWorkspacePage({super.key});

  @override
  State<TextWorkspacePage> createState() => _TextWorkspacePageState();
}

class _TextWorkspacePageState extends State<TextWorkspacePage> {
  late TextWorkspaceDraft _draft = TextWorkspaceDraft.empty();
  final TextEditingController _sourceLanguage = TextEditingController();
  final TextEditingController _sourceText = TextEditingController();
  final List<_TranslationFields> _translations = [_TranslationFields()];

  @override
  void dispose() {
    _sourceLanguage.dispose();
    _sourceText.dispose();
    for (final translation in _translations) {
      translation.dispose();
    }
    super.dispose();
  }

  void _addTranslation() => setState(() {
    _translations.add(_TranslationFields());
    _draft = _draft.copyWith(
      translations: [..._draft.translations, ManualTranslationDraft.empty()],
    );
  });

  void _updateTranslation(int index, {String? language, String? text}) {
    final translations = [..._draft.translations];
    translations[index] = translations[index].copyWith(
      targetLanguage: language,
      text: text,
    );
    setState(() => _draft = _draft.copyWith(translations: translations));
  }

  void _removeTranslation(int index) {
    if (_translations.length == 1) return;
    setState(() {
      _translations.removeAt(index).dispose();
      final translations = [..._draft.translations]..removeAt(index);
      _draft = _draft.copyWith(translations: translations);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ことは | Kotoha')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text('テキスト作業', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '原文と手入力した訳文を並べて作業できます。自動翻訳は行いません。',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),
              const _TemporaryDraftNotice(),
              const SizedBox(height: 20),
              _languageField(
                _sourceLanguage,
                '原文の言語',
                '例: ja',
                onChanged: (value) => setState(
                  () => _draft = _draft.copyWith(sourceLanguage: value),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('source-text'),
                controller: _sourceText,
                onChanged: (value) =>
                    setState(() => _draft = _draft.copyWith(sourceText: value)),
                minLines: 5,
                maxLines: 12,
                decoration: const InputDecoration(
                  labelText: '原文',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              Text('訳文', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (var index = 0; index < _translations.length; index++)
                _translationCard(index),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addTranslation,
                  icon: const Icon(Icons.add),
                  label: const Text('訳先を追加'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _translationCard(int index) {
    final fields = _translations[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _languageField(
                    fields.language,
                    '訳先の言語',
                    '例: en',
                    onChanged: (value) =>
                        _updateTranslation(index, language: value),
                  ),
                ),
                if (_translations.length > 1) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    key: ValueKey('remove-translation-$index'),
                    tooltip: 'この訳先を削除',
                    onPressed: () => _removeTranslation(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: ValueKey('translation-text-$index'),
              controller: fields.text,
              onChanged: (value) => _updateTranslation(index, text: value),
              minLines: 4,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '手入力した訳文',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageField(
    TextEditingController controller,
    String label,
    String hint, {
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );
}

class _TemporaryDraftNotice extends StatelessWidget {
  const _TemporaryDraftNotice();

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(8),
      child: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('この下書きは一時的なものです。このビルドでは保存されません。'),
      ),
    ),
  );
}

class _TranslationFields {
  final TextEditingController language = TextEditingController();
  final TextEditingController text = TextEditingController();

  void dispose() {
    language.dispose();
    text.dispose();
  }
}
