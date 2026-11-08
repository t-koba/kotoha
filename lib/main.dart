import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'first_strong_direction.dart';
import 'l10n/app_localizations.dart';
import 'text_document_exporter.dart';
import 'text_document_picker.dart';
import 'model_terms_import.dart';
import 'model_package_android.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Unicode Bidi Data',
    ], await rootBundle.loadString('assets/licenses/Unicode-3.0.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'crypto',
    ], await rootBundle.loadString('assets/licenses/crypto-3.0.8.txt'));
  });
  runApp(const KotohaApp());
}

class KotohaApp extends StatefulWidget {
  const KotohaApp({super.key, this.exportText = exportTextDocument});

  final Future<void> Function(String path, String text) exportText;

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
    theme: _themeFor(Brightness.light),
    darkTheme: _themeFor(Brightness.dark),
    themeMode: ThemeMode.system,
    home: TextWorkspacePage(
      onLocaleChanged: (locale) => setState(() => _locale = locale),
      exportText: widget.exportText,
    ),
  );
}

ThemeData _themeFor(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF315F58),
    brightness: brightness,
  ),
  useMaterial3: true,
);

class TextWorkspacePage extends StatefulWidget {
  const TextWorkspacePage({
    super.key,
    required this.onLocaleChanged,
    this.exportText = exportTextDocument,
  });

  final ValueChanged<Locale> onLocaleChanged;
  final Future<void> Function(String path, String text) exportText;

  @override
  State<TextWorkspacePage> createState() => _TextWorkspacePageState();
}

class _TextWorkspacePageState extends State<TextWorkspacePage> {
  final TextEditingController _sourceLanguage = TextEditingController();
  final TextEditingController _sourceText = TextEditingController();
  final FocusNode _addTranslationFocusNode = FocusNode();
  final FocusNode _imePersonalizedLearningFocusNode = FocusNode();
  bool _allowImePersonalizedLearning = false;
  bool _importing = false;
  bool _reviewingModel = false;
  // Volatile session-only digest binding; never persisted. Cleared on a new,
  // declined, failed, or released review and on dispose.
  EphemeralModelAuthorization? _sessionModelAuthorization;
  final List<_TranslationFields> _translations = [_TranslationFields()];

  @override
  void dispose() {
    _sessionModelAuthorization = null;
    _sourceLanguage.dispose();
    _sourceText.dispose();
    _addTranslationFocusNode.dispose();
    _imePersonalizedLearningFocusNode.dispose();
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

  Future<void> _importSource() async {
    if (_importing || _reviewingModel) return;
    setState(() => _importing = true);
    // Watch text edits, not selection/focus changes caused by the OS dialog.
    final snapshot = _sourceText.text;
    var sourceChanged = false;
    void watchSource() {
      if (_sourceText.text != snapshot) sourceChanged = true;
    }

    _sourceText.addListener(watchSource);
    try {
      final file = await pickTextDocument();
      if (!mounted || file == null) return;
      // The OS filter is advisory. Reject unsupported names before reading.
      final name = file.name.toLowerCase();
      if (!['.txt', '.md', '.markdown'].any(name.endsWith)) {
        throw const FormatException('Unsupported text document.');
      }
      // Desktop reads in place; mobile returns only in-memory bytes.
      // utf8.decode is strict by default and strips a leading UTF-8 BOM.
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: false);
      if (!mounted) return;
      if (sourceChanged || _sourceText.text != snapshot) {
        _importNotice(AppLocalizations.of(context)!.importSourceChangedNotice);
        return;
      }
      if (snapshot.isNotEmpty) {
        final strings = AppLocalizations.of(context)!;
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.replaceSourceTitle),
            content: Text(strings.replaceSourceQuestion),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancelImport),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.replaceSource),
              ),
            ],
          ),
        );
        if (!mounted || replace != true) return;
      }
      if (sourceChanged || _sourceText.text != snapshot) {
        _importNotice(AppLocalizations.of(context)!.importSourceChangedNotice);
        return;
      }
      _sourceText.text = text;
    } on Exception {
      if (mounted) {
        _importNotice(AppLocalizations.of(context)!.importFailureNotice);
      }
    } finally {
      _sourceText.removeListener(watchSource);
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<bool> _reviewModelTerms(VerifiedTerms review) async {
    final strings = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.modelTermsTitle(review.modelName)),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(strings.modelRuntimeDisabled),
                    const SizedBox(height: 8),
                    Text(strings.modelIntegrityOnly),
                    const SizedBox(height: 8),
                    Text(strings.modelPackageId(review.modelId)),
                    const SizedBox(height: 4),
                    Text(strings.modelDeclaredPublisher(review.publisher)),
                    const SizedBox(height: 8),
                    Text(
                      strings.modelAllTermsVerified(
                        review.verifiedTermsFileCount,
                      ),
                    ),
                    for (final document in review.documents) ...[
                      const SizedBox(height: 12),
                      Text(
                        document.id,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SelectableText(document.text),
                      if (document.usageRequirements.isNotEmpty) ...[
                        Text(strings.modelUsageRequirements),
                        for (final value in document.usageRequirements)
                          Text('• $value'),
                      ],
                      if (document.attributions.isNotEmpty) ...[
                        Text(strings.modelAttributions),
                        for (final value in document.attributions)
                          Text('• $value'),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                key: const ValueKey('decline-model-terms'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.modelDecline),
              ),
              FilledButton(
                key: const ValueKey('accept-model-terms'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.modelAccept),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _importModelTerms() async {
    if (_reviewingModel || _importing) return;
    setState(() {
      _reviewingModel = true;
      // A new review invalidates any prior session binding.
      _sessionModelAuthorization = null;
    });
    try {
      if (!await AndroidPackageReader.select() || !mounted) return;
      final authorization = await const ModelTermsImport().run(
        AndroidPackageReader(),
        _reviewModelTerms,
      );
      if (!mounted) return;
      // Hold only the digest binding in volatile state; never persist it.
      setState(() => _sessionModelAuthorization = authorization);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authorization == null
                ? AppLocalizations.of(context)!.modelTermsDeclined
                : AppLocalizations.of(context)!.modelConsentSessionOnly,
          ),
        ),
      );
    } on Exception {
      if (mounted) {
        setState(() => _sessionModelAuthorization = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.modelPackageFailure),
          ),
        );
      }
    } finally {
      // Releasing the temporary directory grant does not persist or revoke the
      // accepted digest binding; it remains only in volatile session state.
      try {
        await AndroidPackageReader.release();
      } on Exception {
        if (mounted) setState(() => _sessionModelAuthorization = null);
      } finally {
        if (mounted) setState(() => _reviewingModel = false);
      }
    }
  }

  void _importNotice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

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

  Future<void> _exportTranslation(int index) async {
    final strings = AppLocalizations.of(context)!;
    final text = _translations[index].text.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.emptyTranslationExportNotice)),
      );
      return;
    }

    try {
      final location = await FileSelectorPlatform.instance.getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(
            extensions: ['txt'],
            uniformTypeIdentifiers: ['public.utf8-plain-text'],
          ),
        ],
        options: SaveDialogOptions(
          suggestedName: 'translation.txt',
          confirmButtonText: strings.exportFileButton,
        ),
      );
      if (!mounted || location == null) return;
      await widget.exportText(location.path, text);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.exportFailureNotice)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(strings.exportedTranslationNotice)));
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
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                const SizedBox(height: 8),
                if (defaultTargetPlatform == TargetPlatform.android)
                  SwitchListTile(
                    key: const ValueKey('android-ime-personalized-learning'),
                    contentPadding: EdgeInsets.zero,
                    focusNode: _imePersonalizedLearningFocusNode,
                    value: _allowImePersonalizedLearning,
                    onChanged: (value) {
                      // Reopen the input connection on the next field focus so
                      // Android receives the updated IME configuration.
                      if (!_imePersonalizedLearningFocusNode.hasFocus) {
                        FocusManager.instance.primaryFocus?.unfocus();
                      }
                      setState(() => _allowImePersonalizedLearning = value);
                    },
                    title: Text(strings.androidImePersonalizedLearning),
                    subtitle: Text(
                      strings.androidImePersonalizedLearningDescription,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(strings.externalKeyboardPrivacyNotice),
                  ),
                const SizedBox(height: 12),
                _languageField(
                  _sourceLanguage,
                  strings.sourceLanguage,
                  strings.sourceLanguageHint,
                  key: const ValueKey('source-language'),
                ),
                const SizedBox(height: 12),
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.windows ||
                        defaultTargetPlatform == TargetPlatform.android ||
                        defaultTargetPlatform == TargetPlatform.iOS))
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('import-source'),
                      onPressed: _importing || _reviewingModel
                          ? null
                          : _importSource,
                      icon: const Icon(Icons.file_open_outlined),
                      label: Text(strings.importSource),
                    ),
                  ),
                if (defaultTargetPlatform == TargetPlatform.android) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('review-model-terms'),
                      onPressed: _reviewingModel || _importing
                          ? null
                          : _importModelTerms,
                      icon: const Icon(Icons.policy_outlined),
                      label: Text(strings.reviewModelTerms),
                    ),
                  ),
                  if (_sessionModelAuthorization != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        strings.modelSessionActive,
                        key: const ValueKey('model-session-active'),
                      ),
                    ),
                ],
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
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.windows)) ...[
                  const SizedBox(height: 8),
                  Text(strings.exportTranslationNotice),
                ],
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
                    key: ValueKey('target-language-$index'),
                  ),
                ),
                IconButton(
                  key: ValueKey('copy-translation-$index'),
                  tooltip: strings.copyTranslationNumber(index + 1),
                  onPressed: () => _copyTranslation(index),
                  icon: const Icon(Icons.content_copy),
                ),
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.windows))
                  IconButton(
                    key: ValueKey('export-translation-$index'),
                    tooltip: strings.exportTranslationNumber(index + 1),
                    onPressed: () => _exportTranslation(index),
                    icon: const Icon(Icons.file_download_outlined),
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
    String hint, {
    required ValueKey<String> key,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => Semantics(
      identifier: key.value,
      child: TextField(
        key: key,
        controller: controller,
        enableIMEPersonalizedLearning: _allowImePersonalizedLearning,
        textDirection: firstStrongDirection(value.text),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    ),
  );

  Widget _manualTextField({
    required ValueKey<String> key,
    required TextEditingController controller,
    required String label,
    required int minLines,
    required int maxLines,
  }) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => Semantics(
      identifier: key.value,
      child: TextField(
        key: key,
        controller: controller,
        enableIMEPersonalizedLearning: _allowImePersonalizedLearning,
        textDirection: firstStrongDirection(value.text),
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          alignLabelWithHint: true,
          border: const OutlineInputBorder(),
        ),
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
