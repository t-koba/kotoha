import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'first_strong_direction.dart';
import 'l10n/app_localizations.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Unicode Bidi Data',
    ], await rootBundle.loadString('assets/licenses/Unicode-3.0.txt'));
  });
  runApp(const KotohaApp());
}

class KotohaApp extends StatefulWidget {
  const KotohaApp({super.key});

  @override
  State<KotohaApp> createState() => _KotohaAppState();
}

class _KotohaAppState extends State<KotohaApp> {
  // Null follows the device's supported locales; an override lasts this session only.
  Locale? _locale;

  @override
  Widget build(BuildContext context) => MaterialApp(
    onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
    locale: _locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315F58)),
      useMaterial3: true,
    ),
    home: TextWorkspacePage(
      onLocaleChanged: (locale) => setState(() => _locale = locale),
    ),
  );
}

class TextWorkspacePage extends StatefulWidget {
  const TextWorkspacePage({super.key, required this.onLocaleChanged});

  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<TextWorkspacePage> createState() => _TextWorkspacePageState();
}

class _TextWorkspacePageState extends State<TextWorkspacePage> {
  final TextEditingController _sourceLanguage = TextEditingController();
  final TextEditingController _sourceText = TextEditingController();
  final FocusNode _addTranslationFocusNode = FocusNode();
  final List<_TranslationFields> _translations = [_TranslationFields()];

  @override
  void dispose() {
    _sourceLanguage.dispose();
    _sourceText.dispose();
    _addTranslationFocusNode.dispose();
    for (final translation in _translations) {
      translation.dispose();
    }
    super.dispose();
  }

  void _addTranslation() {
    setState(() => _translations.add(_TranslationFields()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addTranslationFocusNode.requestFocus();
    });
  }

  Future<void> _copyTranslation(int index) async {
    final text = _translations[index].text.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.emptyTranslationNotice),
        ),
      );
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.clipboardFailureNotice),
        ),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.copiedTranslationNotice),
      ),
    );
  }

  void _removeTranslation(int index) {
    if (_translations.length == 1) return;
    setState(() {
      _translations.removeAt(index).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(strings.appTitle),
        actions: [
          PopupMenuButton<Locale>(
            key: const ValueKey('ui-language'),
            tooltip: strings.uiLanguage,
            initialValue: Localizations.localeOf(context),
            onSelected: widget.onLocaleChanged,
            icon: const Icon(Icons.translate),
            itemBuilder: (context) {
              final selectedLocale = Localizations.localeOf(context);
              return [
                CheckedPopupMenuItem<Locale>(
                  value: const Locale('ja'),
                  checked: selectedLocale.languageCode == 'ja',
                  child: Text(strings.japanese),
                ),
                CheckedPopupMenuItem<Locale>(
                  value: const Locale('en'),
                  checked: selectedLocale.languageCode == 'en',
                  child: Text(strings.english),
                ),
              ];
            },
          ),
          Builder(
            builder: (innerContext) => IconButton(
              key: const ValueKey('show-licenses'),
              tooltip: strings.licenses,
              onPressed: () => showLicensePage(context: innerContext),
              icon: const Icon(Icons.info_outline),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  strings.workspaceTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.manualEditingNotice,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                const _TemporaryDraftNotice(),
                const SizedBox(height: 20),
                _languageField(
                  _sourceLanguage,
                  strings.sourceLanguage,
                  strings.sourceLanguageHint,
                ),
                const SizedBox(height: 12),
                _manualTextField(
                  key: const ValueKey('source-text'),
                  controller: _sourceText,
                  label: strings.sourceText,
                  minLines: 5,
                  maxLines: 12,
                ),
                const SizedBox(height: 24),
                Text(
                  strings.translations,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(strings.clipboardNotice),
                const SizedBox(height: 12),
                for (var index = 0; index < _translations.length; index++)
                  _translationCard(index),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    focusNode: _addTranslationFocusNode,
                    onPressed: _addTranslation,
                    icon: const Icon(Icons.add),
                    label: Text(strings.addTranslation),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _translationCard(int index) {
    final strings = AppLocalizations.of(context)!;
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
                    strings.targetLanguage,
                    strings.targetLanguageHint,
                  ),
                ),
                IconButton(
                  key: ValueKey('copy-translation-$index'),
                  tooltip: strings.copyTranslationNumber(index + 1),
                  onPressed: () => _copyTranslation(index),
                  icon: const Icon(Icons.content_copy),
                ),
                if (_translations.length > 1)
                  IconButton(
                    key: ValueKey('remove-translation-$index'),
                    tooltip: strings.removeTranslationNumber(index + 1),
                    onPressed: () => _removeTranslation(index),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _manualTextField(
              key: ValueKey('translation-text-$index'),
              controller: fields.text,
              label: strings.manualTranslation,
              minLines: 4,
              maxLines: 10,
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageField(
    TextEditingController controller,
    String label,
    String hint,
  ) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );

  Widget _manualTextField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required int minLines,
    required int maxLines,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => TextField(
      key: key,
      controller: controller,
      textDirection: firstStrongDirection(value.text),
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        border: const OutlineInputBorder(),
      ),
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
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(AppLocalizations.of(context)!.temporaryDraftNotice),
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
