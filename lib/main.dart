import 'dart:async';
import 'dart:convert';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show AttributedString, LocaleStringAttribute, ScrollCacheExtent, TextRange;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import 'content_locale.dart';
import 'document_format_support.dart';
import 'document_outline.dart';
import 'editor_config.dart';
import 'first_strong_direction.dart';
import 'structured_json_panel.dart';
import 'text_find_replace.dart';
import 'l10n/app_localizations.dart';
import 'text_document_exporter.dart';
import 'text_document_picker.dart';
import 'workspace.dart';
import 'workspace_export.dart';
import 'model_terms_import.dart';
import 'model_file_integrity.dart';
import 'model_package_android.dart';

const ValueKey<String> _modelConsentStatusKey = ValueKey(
  'model-consent-status',
);
const ValueKey<String> _modelIntegritySuccessKey = ValueKey(
  'model-integrity-success',
);
const ValueKey<String> _modelIntegrityFailureKey = ValueKey(
  'model-integrity-failure',
);
final Set<ValueKey<String>> _modelStatusKeys = {
  _modelConsentStatusKey,
  _modelIntegritySuccessKey,
  _modelIntegrityFailureKey,
};

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

bool _sameWorkspaceDraft(TextWorkspaceDraft a, TextWorkspaceDraft b) {
  if (a.sourceLanguage != b.sourceLanguage ||
      a.sourceText != b.sourceText ||
      a.translations.length != b.translations.length) {
    return false;
  }
  for (var index = 0; index < a.translations.length; index++) {
    final left = a.translations[index];
    final right = b.translations[index];
    if (left.targetLanguage != right.targetLanguage ||
        left.text != right.text) {
      return false;
    }
  }
  return true;
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

class _TextWorkspacePageState extends State<TextWorkspacePage>
    with WidgetsBindingObserver {
  late final _sourceLanguage = _DraftController(() => _appResumed);
  late final _sourceText = _DraftController(() => _appResumed);
  late final _findQuery = _DraftController(() => _appResumed);
  late final _findReplacement = _DraftController(() => _appResumed);
  bool _findReplaceOpen = false;
  TextEditingController? _selectedFindTarget;
  int _findCount = 0;
  _FindStatus _findStatus = _FindStatus.none;
  String _findStatusQuery = '';
  // Removing a found card clears find feedback. Remember its query while the
  // panel stays open so Escape can still hand focus to a stable widget.
  String? _removedFoundQuery;
  String _findQueryText = '';
  bool _findSubmitWasComposing = false;
  final FocusNode _addTranslationFocusNode = FocusNode();
  final FocusNode _sourceTextFocusNode = FocusNode();
  final FocusNode _imePersonalizedLearningFocusNode = FocusNode();
  final FocusNode _findQueryFocusNode = FocusNode();
  final FocusNode _findTargetFocusNode = FocusNode();
  final FocusNode _findToggleFocusNode = FocusNode();
  final FocusScopeNode _workspaceFocusNode = FocusScopeNode(
    skipTraversal: true,
  );
  bool _allowImePersonalizedLearning = false;
  bool _appResumed = true;
  bool _importing = false;
  // Increment only for whole-source replacements: the JSON editor uses this
  // to discard pending edits when another document has identical bytes.
  int _documentRevision = 0;
  // Import feedback lives in the source panel so it never joins the
  // ScaffoldMessenger queue behind another visible notice.
  String? _sourceImportNotice;
  Timer? _sourceImportNoticeTimer;
  bool _reviewingModel = false;
  bool _verifyingModel = false;
  // Volatile session-only digest binding; never persisted. Cleared on a new,
  // declined, failed, or released review and on dispose.
  EphemeralModelAuthorization? _sessionModelAuthorization;
  // Tracks the model status at the front of the messenger. Model statuses
  // clear the queue before being shown, so the tracked one is never queued.
  ValueKey<String>? _visibleModelStatusKey;
  late List<_TranslationFields> _translations = [
    _TranslationFields(() => _appResumed),
  ];

  @override
  void initState() {
    super.initState();
    _findQuery.addListener(_onFindQueryChanged);
    _selectedFindTarget ??= _sourceText;
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null) {
      _appResumed = lifecycle == AppLifecycleState.resumed;
    }
    _logAccessibilityState('init');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (_appResumed != resumed) setState(() => _appResumed = resumed);
    _logAccessibilityState('lifecycle-${state.name}');
  }

  @override
  void didChangeAccessibilityFeatures() {
    _logAccessibilityState('accessibility-features');
  }

  void _logAccessibilityState(String event) {
    if (!kDebugMode) return;
    final binding = WidgetsBinding.instance;
    debugPrint(
      'KotohaAccessibilityState event=$event '
      'lifecycle=${binding.lifecycleState?.name ?? 'unknown'} '
      'appResumed=$_appResumed '
      'semanticsEnabled=${binding.platformDispatcher.semanticsEnabled}',
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sessionModelAuthorization = null;
    _sourceImportNoticeTimer?.cancel();
    _sourceLanguage.dispose();
    _sourceText.dispose();
    _findQuery.removeListener(_onFindQueryChanged);
    _findQuery.dispose();
    _findReplacement.dispose();
    _addTranslationFocusNode.dispose();
    _sourceTextFocusNode.dispose();
    _imePersonalizedLearningFocusNode.dispose();
    _findQueryFocusNode.dispose();
    _findTargetFocusNode.dispose();
    _findToggleFocusNode.dispose();
    _workspaceFocusNode.dispose();
    for (final translation in _translations) {
      translation.dispose();
    }
    super.dispose();
  }

  void _addTranslation() {
    setState(() => _translations.add(_TranslationFields(() => _appResumed)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _addTranslationFocusNode.requestFocus();
    });
  }

  Future<void> _importSource() async {
    if (_importing || _reviewingModel || _verifyingModel) {
      return;
    }
    _clearSourceImportNotice();
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
        throw const UnsupportedTextDocument();
      }
      // Desktop reads in place; mobile returns only in-memory bytes.
      // utf8.decode is strict by default and strips a leading UTF-8 BOM.
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: false);
      if (!mounted) return;
      if (sourceChanged || _sourceText.text != snapshot) {
        _showSourceImportNotice(
          AppLocalizations.of(context)!.importSourceChangedNotice,
        );
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
        _showSourceImportNotice(
          AppLocalizations.of(context)!.importSourceChangedNotice,
        );
        return;
      }
      setState(() => _replaceDocumentText(_sourceText, text));
    } on TextDocumentTooLarge {
      if (mounted) {
        _showSourceImportNotice(
          AppLocalizations.of(context)!.importSourceTooLargeNotice,
        );
      }
    } on Exception {
      if (mounted) {
        _showSourceImportNotice(
          AppLocalizations.of(context)!.importFailureNotice,
        );
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
            scrollable: true,
            title: Text(strings.modelTermsTitle(review.modelName)),
            content: SizedBox(
              width: 560,
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

  void _removeCurrentModelStatus() {
    // Invalidating a model binding flushes the shared snack-bar queue: Flutter
    // drops every notice, so neither a stale status nor a queued notice can
    // surface once the binding is gone.
    if (_modelStatusKeys.contains(_visibleModelStatusKey)) {
      ScaffoldMessenger.of(context).clearSnackBars();
      _visibleModelStatusKey = null;
    }
  }

  void _showModelConsentStatus(SnackBar status) {
    final key = status.key;
    if (key is ValueKey<String> && _modelStatusKeys.contains(key)) {
      // Model statuses own the messenger: clearing first keeps a newer status
      // (or withdrawal confirmation) from queued behind another notice.
      ScaffoldMessenger.of(context).clearSnackBars();
      _visibleModelStatusKey = key;
      ScaffoldMessenger.of(context)
          .showSnackBar(status)
          .closed
          .whenComplete(() {
            if (_visibleModelStatusKey == key) _visibleModelStatusKey = null;
          });
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(status);
  }

  Future<void> _importModelTerms() async {
    if (_reviewingModel || _importing || _verifyingModel) {
      return;
    }
    // The old binding's status no longer applies as soon as a new review starts.
    _removeCurrentModelStatus();
    setState(() {
      _reviewingModel = true;
      // A new review invalidates any prior session binding.
      _sessionModelAuthorization = null;
    });
    var reviewed = false;
    var accepted = false;
    var failed = false;
    var releaseFailed = false;
    try {
      if (!await AndroidPackageReader.select() || !mounted) return;
      reviewed = true;
      final authorization = await const ModelTermsImport().run(
        AndroidPackageReader(),
        _reviewModelTerms,
      );
      if (!mounted) return;
      // Hold only the digest binding in volatile state; never persist it.
      accepted = authorization != null;
      setState(() => _sessionModelAuthorization = authorization);
    } on Exception {
      failed = true;
      if (mounted) {
        setState(() => _sessionModelAuthorization = null);
        _showModelConsentStatus(
          SnackBar(
            key: _modelConsentStatusKey,
            content: Text(AppLocalizations.of(context)!.modelPackageFailure),
          ),
        );
      }
    } finally {
      // A successful release leaves the volatile digest binding unchanged.
      // If release fails, the binding is revoked and the fixed notice below
      // reports only that state change; no exception detail is echoed.
      try {
        await AndroidPackageReader.release();
      } on Exception {
        releaseFailed = true;
        if (mounted) setState(() => _sessionModelAuthorization = null);
      }
      if (mounted) {
        setState(() => _reviewingModel = false);
        if (reviewed && !failed) {
          final strings = AppLocalizations.of(context)!;
          final message = releaseFailed && accepted
              ? strings.modelReleaseFailure
              : accepted
              ? strings.modelConsentSessionOnly
              : strings.modelTermsDeclined;
          _showModelConsentStatus(
            SnackBar(key: _modelConsentStatusKey, content: Text(message)),
          );
        }
      }
    }
  }

  /// Withdraws the volatile digest binding after explicit user action. Only
  /// in-memory session state changes; no engine, file, network or persisted
  /// authorization is involved.
  void _clearModelConsent() {
    if (_reviewingModel || _verifyingModel || _importing) return;
    setState(() => _sessionModelAuthorization = null);
    _showModelConsentStatus(
      SnackBar(
        key: _modelConsentStatusKey,
        content: Text(AppLocalizations.of(context)!.modelConsentCleared),
      ),
    );
  }

  Future<bool> _confirmModelFileIntegrity() async {
    final strings = AppLocalizations.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('model-integrity-consent-dialog'),
            title: Text(strings.modelIntegrityConsentTitle),
            content: Text(strings.modelIntegrityConsent),
            actions: [
              TextButton(
                key: const ValueKey('decline-model-integrity'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.modelIntegrityCancel),
              ),
              FilledButton(
                key: const ValueKey('confirm-model-integrity'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.modelIntegrityConfirm),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showModelIntegrityResult(bool matched) {
    final strings = AppLocalizations.of(context)!;
    _showModelConsentStatus(
      SnackBar(
        key: matched ? _modelIntegritySuccessKey : _modelIntegrityFailureKey,
        content: Text(
          matched
              ? strings.modelIntegritySuccess
              : strings.modelIntegrityFailure,
        ),
      ),
    );
  }

  Future<void> _verifyModelFiles() async {
    final authorization = _sessionModelAuthorization;
    if (authorization == null ||
        _verifyingModel ||
        _reviewingModel ||
        _importing) {
      return;
    }
    if (!await _confirmModelFileIntegrity() || !mounted) return;
    setState(() => _verifyingModel = true);
    try {
      // The grant from terms review was released; ask for a fresh temporary,
      // non-persistable selection for this one streaming check.
      if (!await AndroidPackageReader.select()) {
        if (mounted) _showModelIntegrityResult(false);
        return;
      }
      final matched = await const ModelFileIntegrity().verify(
        authorization.declaredFiles,
      );
      if (mounted) _showModelIntegrityResult(matched);
    } on Exception {
      if (mounted) _showModelIntegrityResult(false);
    } finally {
      try {
        await AndroidPackageReader.release();
      } on Exception {
        // Nothing is stored or changed by an integrity check.
      } finally {
        if (mounted) setState(() => _verifyingModel = false);
      }
    }
  }

  void _importNotice(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  void _clearSourceImportNotice() {
    _sourceImportNoticeTimer?.cancel();
    _sourceImportNoticeTimer = null;
    if (_sourceImportNotice != null && mounted) {
      setState(() => _sourceImportNotice = null);
    }
  }

  void _showSourceImportNotice(String message) {
    _clearSourceImportNotice();
    if (mounted) setState(() => _sourceImportNotice = message);
    _sourceImportNoticeTimer = Timer(const Duration(seconds: 4), () {
      _sourceImportNoticeTimer = null;
      if (!mounted) return;
      setState(() => _sourceImportNotice = null);
    });
  }

  Future<void> _copyTranslation(_TranslationFields fields) async {
    // The rendered button keeps its card; a callback made stale by a removal
    // must no-op before reading a controller at an index that no longer exists.
    if (!_translations.contains(fields)) return;
    final text = fields.text.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.emptyTranslationNotice),
        ),
      );
      return;
    }
    await _copyToClipboard(
      content: text,
      successNotice: AppLocalizations.of(context)!.copiedTranslationNotice,
    );
  }

  Future<void> _exportTranslation(_TranslationFields fields) async {
    if (!_translations.contains(fields)) return;
    final strings = AppLocalizations.of(context)!;
    final text = fields.text.text;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.emptyTranslationExportNotice)),
      );
      return;
    }

    await _exportToFile(
      content: text,
      suggestedName: 'translation.txt',
      successNotice: strings.exportedTranslationNotice,
      failureNotice: strings.exportFailureNotice,
    );
  }

  // Every field, including empty bodies and language labels, so an edit guard
  // never treats a language-only change as no change.
  TextWorkspaceDraft _workspaceDraft() => TextWorkspaceDraft(
    sourceLanguage: _sourceLanguage.text,
    sourceText: _sourceText.text,
    translations: [
      for (final fields in _translations)
        ManualTranslationDraft(
          targetLanguage: fields.language.text,
          text: fields.text.text,
        ),
    ],
  );

  // Snapshot the in-memory fields once for both output routes. Null means
  // no text and no added card to copy or export.
  TextWorkspaceDraft? _nonEmptyWorkspaceDraft() {
    // Any populated field counts, matching restore's unsaved-change check:
    // a language-only workspace round-trips through the export format.
    if (!_workspaceHasWorkspaceContent()) return null;
    return _workspaceDraft();
  }

  bool _workspaceHasWorkspaceContent() =>
      _workspaceHasAnyText() ||
      // The format keeps one entry per card, so cards the user explicitly
      // added are workspace content even while their fields are still blank.
      _translations.length > 1;

  bool _workspaceHasAnyText() =>
      _sourceLanguage.text.isNotEmpty ||
      _sourceText.text.isNotEmpty ||
      _translations.any(
        (fields) =>
            fields.language.text.isNotEmpty || fields.text.text.isNotEmpty,
      );

  Future<void> _restoreWorkspace() async {
    if (_importing || _reviewingModel || _verifyingModel) return;
    final strings = AppLocalizations.of(context)!;
    setState(() => _importing = true);
    final before = _workspaceDraft();
    try {
      final file = await pickTextDocument();
      if (!mounted || file == null) return;
      final name = file.name.toLowerCase();
      if (!['.txt', '.md', '.markdown'].any(name.endsWith)) {
        throw const UnsupportedTextDocument();
      }
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: false);
      if (!mounted) return;
      final restored = parseWorkspaceExport(text);
      final editable = normalizeWorkspaceDraftForEditing(restored);
      bool changed() => !_sameWorkspaceDraft(_workspaceDraft(), before);

      if (changed()) {
        _importNotice(strings.restoreWorkspaceChangedNotice);
        return;
      }
      if (editable != null) {
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.restoreWorkspaceSurrogatesTitle),
            content: Text(strings.restoreWorkspaceSurrogatesQuestion),
            actions: [
              TextButton(
                key: const ValueKey('restore-workspace-surrogate-cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancelImport),
              ),
              TextButton(
                key: const ValueKey('restore-workspace-surrogate-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.restoreWorkspaceReplace),
              ),
            ],
          ),
        );
        if (!mounted || accepted != true) return;
        if (changed()) {
          _importNotice(strings.restoreWorkspaceChangedNotice);
          return;
        }
      }
      if (_workspaceHasWorkspaceContent()) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(strings.restoreWorkspaceTitle),
            content: Text(strings.restoreWorkspaceQuestion),
            actions: [
              TextButton(
                key: const ValueKey('restore-workspace-cancel'),
                onPressed: () => Navigator.pop(context, false),
                child: Text(strings.cancelImport),
              ),
              TextButton(
                key: const ValueKey('restore-workspace-confirm'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(strings.restoreWorkspaceReplace),
              ),
            ],
          ),
        );
        if (!mounted || replace != true) return;
        if (changed()) {
          _importNotice(strings.restoreWorkspaceChangedNotice);
          return;
        }
      }

      final target = editable ?? restored;
      final fields = [
        for (final translation in target.translations)
          _TranslationFields(() => _appResumed)
            ..language.replaceText(translation.targetLanguage)
            ..text.replaceText(translation.text),
      ];
      setState(() {
        _sourceLanguage.replaceText(target.sourceLanguage);
        _replaceDocumentText(_sourceText, target.sourceText);
        for (final old in _translations) {
          if (identical(_selectedFindTarget, old.text)) {
            _selectedFindTarget = null;
          }
          old.dispose();
        }
        _translations = fields;
      });
      if (!mounted) return;
      _importNotice(strings.restoredWorkspaceNotice);
    } on UnsupportedTextDocument {
      if (mounted) _importNotice(strings.restoreWorkspaceUnsupportedTypeNotice);
    } on TextDocumentTooLarge {
      if (mounted) _importNotice(strings.restoreWorkspaceTooLargeNotice);
    } on FormatException {
      if (mounted) _importNotice(strings.restoreWorkspaceUnsupportedNotice);
    } on PlatformException catch (e) {
      if (!mounted) return;
      _importNotice(switch (e.code) {
        'too_large' => strings.restoreWorkspaceTooLargeNotice,
        'unsupported_type' => strings.restoreWorkspaceUnsupportedTypeNotice,
        _ => strings.restoreWorkspaceFailureNotice,
      });
    } on Exception {
      if (mounted) _importNotice(strings.restoreWorkspaceFailureNotice);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _exportWorkspace() async {
    final strings = AppLocalizations.of(context)!;
    final draft = _nonEmptyWorkspaceDraft();
    if (draft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.emptyWorkspaceExportNotice)),
      );
      return;
    }

    final content = formatWorkspaceExport(draft);
    // Restore applies the same bounded reader to every document it accepts.
    // Disclose an over-limit export before saving, but keep the user's text
    // savable as a plain UTF-8 file and report it as non-restorable.
    final tooLarge = utf8.encode(content).length > maxTextImportBytes;
    if (tooLarge) {
      final saveAnyway = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.workspaceExportTooLargeTitle),
          content: Text(strings.workspaceExportTooLargeQuestion),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.cancelImport),
            ),
            TextButton(
              key: const ValueKey('workspace-export-too-large-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.workspaceExportTooLargeContinue),
            ),
          ],
        ),
      );
      if (!mounted || saveAnyway != true) return;
    }
    await _exportToFile(
      content: content,
      suggestedName: 'workspace.txt',
      successNotice: tooLarge
          ? strings.exportedWorkspaceTooLargeNotice
          : strings.exportedWorkspaceNotice,
      failureNotice: strings.workspaceExportFailureNotice,
    );
  }

  Future<void> _copyWorkspace() async {
    final strings = AppLocalizations.of(context)!;
    final draft = _nonEmptyWorkspaceDraft();
    if (draft == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(strings.emptyWorkspaceCopyNotice)));
      return;
    }
    await _copyToClipboard(
      content: formatWorkspaceExport(draft),
      successNotice: strings.copiedWorkspaceNotice,
    );
  }

  // One owner for the OS clipboard write and its failure contract. Callers
  // decide what to copy and which success notice to report.
  Future<void> _copyToClipboard({
    required String content,
    required String successNotice,
  }) async {
    // Win32 CF_UNICODETEXT is NUL-terminated, so pasting a raw NUL would
    // silently truncate the text. Workspace copy is escaped by its format.
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.windows &&
        content.contains('\u0000')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.clipboardNulNotice),
        ),
      );
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: content));
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successNotice)));
  }

  // One owner for the save-location, write and notice contract shared by the
  // single-translation and whole-workspace exports.
  Future<void> _exportToFile({
    required String content,
    required String suggestedName,
    required String successNotice,
    required String failureNotice,
  }) async {
    try {
      final location = await FileSelectorPlatform.instance.getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(
            extensions: ['txt'],
            uniformTypeIdentifiers: ['public.utf8-plain-text'],
          ),
        ],
        options: SaveDialogOptions(
          suggestedName: suggestedName,
          confirmButtonText: AppLocalizations.of(context)!.exportFileButton,
        ),
      );
      if (!mounted || location == null) return;
      await widget.exportText(location.path, content);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failureNotice)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(successNotice)));
  }

  Future<void> _removeTranslation(_TranslationFields fields) async {
    // A rendered Remove button keeps the card it was built for. A stale
    // callback (invoked twice before a rebuild) must be a no-op before any
    // controller is read, not an index into a list that has since shrunk.
    if (_translations.length == 1 || !_translations.contains(fields)) return;
    if (fields.language.text.isNotEmpty || fields.text.text.isNotEmpty) {
      final strings = AppLocalizations.of(context)!;
      final remove = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(strings.removeTranslationTitle),
          content: Text(strings.removeTranslationQuestion),
          actions: [
            TextButton(
              key: const ValueKey('remove-translation-cancel'),
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.removeTranslationCancel),
            ),
            TextButton(
              key: const ValueKey('remove-translation-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.removeTranslationConfirm),
            ),
          ],
        ),
      );
      if (!mounted || remove != true) return;
    }

    final currentIndex = _translations.indexOf(fields);
    if (currentIndex < 0 || _translations.length == 1) return;
    // When a following field shifts into this slot, keep keyboard focus on it
    // so removal does not drop focus back to the enclosing scope. Removing the
    // last field hands focus to the Add button, whose activation adds a card.
    final following = currentIndex + 1 < _translations.length
        ? _translations[currentIndex + 1]
        : null;
    final removed = _translations[currentIndex];
    setState(() {
      if (identical(_selectedFindTarget, removed.text)) {
        if (_findReplaceOpen &&
            _findStatus == _FindStatus.found &&
            _findStatusQuery == _findQuery.text) {
          _removedFoundQuery = _findQuery.text;
        }
        _selectedFindTarget = null;
        _clearFindFeedback();
      }
      _translations.removeAt(currentIndex).dispose();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (following != null && _translations.contains(following)) {
        following.textFocusNode.requestFocus();
      } else {
        _addTranslationFocusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final scaffold = Scaffold(
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
      // Keep offscreen body geometry from reordering traversal around the toolbar.
      body: FocusTraversalGroup(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                // Let toolbar focus use the standard Page Up/Down scroll actions
                // on desktop too, without overriding text-editing shortcuts.
                primary: true,
                // Lazy children need to be built before Tab can reach them.
                // Scale this bounded cache with the viewport and accessibility text.
                scrollCacheExtent: ScrollCacheExtent.viewport(
                  4 * MediaQuery.textScalerOf(context).scale(1),
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(20),
                children: [
                  // Keep the initial fields focusable even when a short
                  // viewport excludes them from the lazy scroll cache.
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          key: const ValueKey(
                            'android-ime-personalized-learning',
                          ),
                          contentPadding: EdgeInsets.zero,
                          focusNode: _imePersonalizedLearningFocusNode,
                          value: _allowImePersonalizedLearning,
                          onChanged: (value) {
                            // Reopen the input connection on the next field focus so
                            // Android receives the updated IME configuration.
                            if (!_imePersonalizedLearningFocusNode.hasFocus) {
                              FocusManager.instance.primaryFocus?.unfocus();
                            }
                            setState(
                              () => _allowImePersonalizedLearning = value,
                            );
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
                            onPressed:
                                _importing || _reviewingModel || _verifyingModel
                                ? null
                                : _importSource,
                            icon: const Icon(Icons.file_open_outlined),
                            label: Text(strings.importSource),
                          ),
                        ),
                      if (_sourceImportNotice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            label: _sourceImportNotice!,
                            excludeSemantics: true,
                            child: Text(
                              _sourceImportNotice!,
                              key: const ValueKey('source-import-notice'),
                            ),
                          ),
                        ),
                      if (defaultTargetPlatform == TargetPlatform.android) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const ValueKey('review-model-terms'),
                            onPressed:
                                _reviewingModel || _importing || _verifyingModel
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
                        if (_sessionModelAuthorization != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                key: const ValueKey('clear-model-consent'),
                                onPressed:
                                    _reviewingModel ||
                                        _verifyingModel ||
                                        _importing
                                    ? null
                                    : _clearModelConsent,
                                icon: const Icon(Icons.delete_outline),
                                label: Text(strings.clearModelConsent),
                              ),
                            ),
                          ),
                        if (_sessionModelAuthorization != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                key: const ValueKey('verify-model-files'),
                                onPressed:
                                    _verifyingModel ||
                                        _reviewingModel ||
                                        _importing
                                    ? null
                                    : _verifyModelFiles,
                                icon: const Icon(Icons.fingerprint_outlined),
                                label: Text(strings.verifyModelFiles),
                              ),
                            ),
                          ),
                      ],
                      _manualTextField(
                        key: const ValueKey('source-text'),
                        controller: _sourceText,
                        contentLanguage: _sourceLanguage,
                        label: strings.sourceText,
                        focusNode: _sourceTextFocusNode,
                        minLines: 5,
                        maxLines: 12,
                      ),
                      DocumentOutline(
                        controller: _sourceText,
                        sourceFocusNode: _sourceTextFocusNode,
                        enableIMEPersonalizedLearning:
                            _allowImePersonalizedLearning,
                      ),
                      const DocumentFormatSupport(),
                      StructuredJsonPanel(
                        controller: _sourceText,
                        sourceRevision: _documentRevision,
                        enableIMEPersonalizedLearning:
                            _allowImePersonalizedLearning,
                      ),
                      const SizedBox(height: 12),
                      // Keep the toggle in normal Tab order; Ctrl/⌘+F is an
                      // additional way to reach the same action.
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: strings.findReplaceShortcut,
                          child: OutlinedButton.icon(
                            key: const ValueKey('find-replace-toggle'),
                            focusNode: _findToggleFocusNode,
                            onPressed: _toggleFindReplace,
                            icon: const Icon(Icons.search),
                            label: Text(strings.findReplaceTitle),
                          ),
                        ),
                      ),
                      if (_findReplaceOpen) _findReplacePanel(strings),
                      const SizedBox(height: 24),
                      Text(
                        strings.translations,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(strings.clipboardNotice),
                      const SizedBox(height: 8),
                      Text(strings.copyWorkspaceNotice),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const ValueKey('copy-workspace'),
                          onPressed: _copyWorkspace,
                          icon: const Icon(Icons.copy_all_outlined),
                          label: Text(strings.copyWorkspace),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(strings.restoreWorkspaceNotice),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          key: const ValueKey('restore-workspace'),
                          onPressed:
                              _importing || _reviewingModel || _verifyingModel
                              ? null
                              : _restoreWorkspace,
                          icon: const Icon(Icons.restore_outlined),
                          label: Text(strings.restoreWorkspace),
                        ),
                      ),
                      if (!kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.macOS ||
                              defaultTargetPlatform ==
                                  TargetPlatform.windows)) ...[
                        const SizedBox(height: 8),
                        Text(strings.exportTranslationNotice),
                        const SizedBox(height: 8),
                        Text(strings.exportWorkspaceNotice),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const ValueKey('export-workspace'),
                            onPressed: _exportWorkspace,
                            icon: const Icon(Icons.file_download_outlined),
                            label: Text(strings.exportWorkspace),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _translationCard(0),
                    ],
                  ),
                  for (var index = 1; index < _translations.length; index++)
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
      ),
    );
    return _privacyShield(
      CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            control: true,
            includeRepeats: false,
          ): _findFromShortcut,
          const SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            includeRepeats: false,
          ): _findFromShortcut,
          if (_findReplaceOpen)
            const SingleActivator(
              LogicalKeyboardKey.escape,
              includeRepeats: false,
            ): _closeFindReplace,
        },
        child: FocusScope(
          node: _workspaceFocusNode,
          autofocus: true,
          skipTraversal: true,
          child: scaffold,
        ),
      ),
      strings,
    );
  }

  void _clearFindFeedback() {
    _findStatus = _FindStatus.none;
    _findStatusQuery = '';
    _findCount = 0;
  }

  /// A programmatic document replacement bypasses TextField.onChanged, so it
  /// must clear find feedback itself. Callers own the surrounding setState.
  void _replaceDocumentText(_DraftController controller, String text) {
    controller.replaceText(text);
    _documentRevision++;
    _clearFindFeedback();
  }

  void _onDocumentChanged() {
    _removedFoundQuery = null;
    if (_findStatus == _FindStatus.none &&
        _findStatusQuery.isEmpty &&
        _findCount == 0) {
      return;
    }
    setState(_clearFindFeedback);
  }

  void _onFindQueryChanged() {
    final text = _findQuery.text;
    if (text == _findQueryText) return;
    _findQueryText = text;
    _removedFoundQuery = null;
    if (_findStatus == _FindStatus.none &&
        _findStatusQuery.isEmpty &&
        _findCount == 0) {
      return;
    }
    setState(_clearFindFeedback);
  }

  void _toggleFindReplace() {
    if (!_appResumed) return;
    _removedFoundQuery = null;
    setState(() => _findReplaceOpen = !_findReplaceOpen);
  }

  void _focusFindQuery() {
    _findQuery.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _findQuery.text.length,
    );
    // requestFocus() scrolls a newly focused field into view, but a repeated
    // shortcut on an already focused field produces no focus change, so scroll
    // explicitly for that case.
    if (_findQueryFocusNode.hasPrimaryFocus) {
      final context = _findQueryFocusNode.context;
      if (context != null && context.mounted) {
        Scrollable.ensureVisible(context, alignment: 0.5);
      }
    }
    _findQueryFocusNode.requestFocus();
  }

  void _findFromShortcut() {
    if (!_appResumed) return;
    _removedFoundQuery = null;
    if (!_findReplaceOpen) {
      setState(() => _findReplaceOpen = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_appResumed || !_findReplaceOpen) return;
        _focusFindQuery();
      });
      return;
    }
    _focusFindQuery();
  }

  void _closeFindReplace() {
    if (!_appResumed || !_findReplaceOpen) return;
    final hasCurrentFind =
        _findStatus == _FindStatus.found && _findStatusQuery == _findQuery.text;
    final hasRemovedFind =
        _selectedFindTarget == null &&
        _removedFoundQuery != null &&
        _removedFoundQuery == _findQuery.text;
    // Only hand focus back while Escape closes a find still owned by the
    // query. A click into another editor already moved focus deliberately.
    final handOffFocus =
        _findQueryFocusNode.hasPrimaryFocus &&
        (hasCurrentFind || hasRemovedFind);
    final foundEditor = handOffFocus
        ? _findTargetEditorFocusNode(_findTargetController())
        : null;
    _removedFoundQuery = null;
    _findQueryFocusNode.unfocus(
      disposition: UnfocusDisposition.previouslyFocusedChild,
    );
    setState(() => _findReplaceOpen = false);
    if (!handOffFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _findReplaceOpen) return;
      final context = foundEditor?.context;
      if (context != null && context.mounted) {
        foundEditor!.requestFocus();
      } else {
        _findToggleFocusNode.requestFocus();
      }
    });
  }

  TextEditingController? _currentFindTarget(TextEditingController? candidate) {
    if (candidate == null) return null;
    if (identical(candidate, _sourceText)) return _sourceText;
    for (final fields in _translations) {
      if (identical(fields.text, candidate)) return fields.text;
    }
    return null;
  }

  TextEditingController? _findTargetController() =>
      _currentFindTarget(_selectedFindTarget);

  FocusNode? _findTargetEditorFocusNode(TextEditingController? controller) {
    if (controller == null) return null;
    if (identical(controller, _sourceText)) return _sourceTextFocusNode;
    for (final fields in _translations) {
      if (identical(fields.text, controller)) return fields.textFocusNode;
    }
    return null;
  }

  void _findOnEnter(bool composing) {
    if (composing || !_appResumed || _findQuery.text.isEmpty) return;
    _runFindNext();
  }

  void _runFindNext() {
    final controller = _findTargetController();
    if (controller == null) return;
    final found = findNext(controller, _findQuery.text);
    setState(() {
      _findCount = 0;
      _findStatusQuery = _findQuery.text;
      _findStatus = found ? _FindStatus.found : _FindStatus.noMatch;
    });
  }

  void _runReplaceSelection() {
    final controller = _findTargetController();
    if (controller == null) return;
    final replaced = replaceSelection(
      controller,
      _findQuery.text,
      _findReplacement.text,
    );
    setState(() {
      _findCount = replaced ? 1 : 0;
      _findStatusQuery = _findQuery.text;
      _findStatus = replaced ? _FindStatus.replaced : _FindStatus.mismatch;
    });
  }

  void _runReplaceAll() {
    final controller = _findTargetController();
    if (controller == null) return;
    final count = replaceAll(
      controller,
      _findQuery.text,
      _findReplacement.text,
      maxOutputLength: replaceAllOutputLimit,
    );
    setState(() {
      _findCount = count < 0 ? 0 : count;
      _findStatusQuery = _findQuery.text;
      _findStatus = switch (count) {
        -1 => _FindStatus.limitExceeded,
        0 => _FindStatus.noMatch,
        _ => _FindStatus.replaced,
      };
    });
  }

  String? _statusForQuery(TextEditingValue query, AppLocalizations strings) {
    if (query.text != _findStatusQuery) return null;
    return switch (_findStatus) {
      _FindStatus.none => null,
      _FindStatus.found => strings.findMatchFound,
      _FindStatus.noMatch => strings.findNoMatch,
      _FindStatus.mismatch => strings.findSelectionMismatch,
      _FindStatus.replaced => strings.findReplacedCount(_findCount),
      _FindStatus.limitExceeded => strings.findLimitExceeded,
    };
  }

  Widget _findReplacePanel(AppLocalizations strings) {
    // The selector and every action resolve the chosen field by identity, so
    // removing an earlier card cannot redirect edits to a different draft.
    final target = _findTargetController();
    final hasTarget = target != null;
    final panel = Column(
      key: const ValueKey('find-replace-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        // The status shares the target row so a match stays in view while the
        // query is focused near the bottom of a short workspace.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _findQuery,
          builder: (context, query, _) => Row(
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: const ValueKey('find-target'),
                  child: DropdownButtonFormField<TextEditingController>(
                    key: ValueKey(target ?? 'find-target-none'),
                    focusNode: _findTargetFocusNode,
                    initialValue: target,
                    hint: Text(strings.findTarget),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: strings.findTarget,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem<TextEditingController>(
                        key: const ValueKey('find-target-source'),
                        value: _sourceText,
                        child: Text(strings.findSourceTarget),
                      ),
                      for (var index = 0; index < _translations.length; index++)
                        DropdownMenuItem<TextEditingController>(
                          key: ValueKey('find-target-translation-${index + 1}'),
                          value: _translations[index].text,
                          child: Text(strings.findTranslationTarget(index + 1)),
                        ),
                    ],
                    onChanged: !_appResumed
                        ? null
                        : (value) => setState(() {
                            _selectedFindTarget = _currentFindTarget(value);
                            _removedFoundQuery = null;
                            _clearFindFeedback();
                          }),
                  ),
                ),
              ),
              if (_statusForQuery(query, strings) case final String status)
                Flexible(
                  child: Semantics(
                    container: true,
                    liveRegion: true,
                    label: status,
                    excludeSemantics: true,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(status, key: const ValueKey('find-status')),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _findQuery,
          builder: (context, value, _) => CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): () {
                // An Enter that commits an IME candidate must not search on
                // text that the IME has not committed yet.
                _findOnEnter(_findQuery.value.composing.isValid);
              },
            },
            child: TextField(
              key: const ValueKey('find-query'),
              controller: _findQuery,
              focusNode: _findQueryFocusNode,
              readOnly: !_appResumed,
              enableIMEPersonalizedLearning: _allowImePersonalizedLearning,
              textDirection: firstStrongDirection(value.text),
              keyboardType: TextInputType.text,
              minLines: 1,
              maxLines: 2,
              textInputAction: TextInputAction.search,
              onEditingComplete: () {
                // The submit callback runs after editing completes, so record
                // an in-progress IME candidate before clearing it.
                _findSubmitWasComposing = _findQuery.value.composing.isValid;
                _findQuery.clearComposing();
              },
              onSubmitted: (_) {
                _findOnEnter(_findSubmitWasComposing);
                _findSubmitWasComposing = false;
              },
              decoration: InputDecoration(
                labelText: strings.findQuery,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _findReplacement,
          builder: (context, value, _) => TextField(
            key: const ValueKey('find-replacement'),
            controller: _findReplacement,
            readOnly: !_appResumed,
            enableIMEPersonalizedLearning: _allowImePersonalizedLearning,
            textDirection: firstStrongDirection(value.text),
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: strings.findReplacement,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(strings.findLiteralNotice),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _findQuery,
          builder: (context, query, _) {
            final canAct = _appResumed && hasTarget && query.text.isNotEmpty;
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton(
                    key: const ValueKey('find-next'),
                    onPressed: canAct ? _runFindNext : null,
                    child: Text(strings.findNextButton),
                  ),
                  OutlinedButton(
                    key: const ValueKey('replace-selection'),
                    onPressed: canAct ? _runReplaceSelection : null,
                    child: Text(strings.replaceButton),
                  ),
                  OutlinedButton(
                    key: const ValueKey('replace-all'),
                    onPressed: canAct ? _runReplaceAll : null,
                    child: Text(strings.replaceAllButton),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeFindReplace,
      },
      child: panel,
    );
  }

  Widget _privacyShield(Widget child, AppLocalizations strings) => Stack(
    fit: StackFit.expand,
    children: [
      Focus(
        key: const ValueKey('workspace-keyboard-shield'),
        skipTraversal: true,
        onKeyEvent: (_, _) =>
            _appResumed ? KeyEventResult.ignored : KeyEventResult.handled,
        child: AbsorbPointer(
          key: const ValueKey('workspace-input-shield'),
          absorbing: !_appResumed,
          child: ExcludeSemantics(
            key: const ValueKey('workspace-semantics-shield'),
            excluding: !_appResumed,
            child: child,
          ),
        ),
      ),
      if (!_appResumed)
        Positioned.fill(
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  strings.inactiveDraftNotice,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          ),
        ),
    ],
  );

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
                    strings.targetLanguageNumber(index + 1),
                    strings.targetLanguageHint,
                    key: ValueKey('target-language-$index'),
                  ),
                ),
                IconButton(
                  key: ValueKey('copy-translation-$index'),
                  tooltip: strings.copyTranslationNumber(index + 1),
                  onPressed: () => _copyTranslation(fields),
                  icon: const Icon(Icons.content_copy),
                ),
                if (!kIsWeb &&
                    (defaultTargetPlatform == TargetPlatform.macOS ||
                        defaultTargetPlatform == TargetPlatform.windows))
                  IconButton(
                    key: ValueKey('export-translation-$index'),
                    tooltip: strings.exportTranslationNumber(index + 1),
                    onPressed: () => _exportTranslation(fields),
                    icon: const Icon(Icons.file_download_outlined),
                  ),
                if (_translations.length > 1)
                  IconButton(
                    key: ValueKey('remove-translation-$index'),
                    tooltip: strings.removeTranslationNumber(index + 1),
                    onPressed: () => _removeTranslation(fields),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _manualTextField(
              key: ValueKey('translation-text-$index'),
              controller: fields.text,
              contentLanguage: fields.language,
              focusNode: fields.textFocusNode,
              label: strings.manualTranslationNumber(index + 1),
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
        readOnly: !_appResumed,
        enableIMEPersonalizedLearning: _allowImePersonalizedLearning,
        textDirection: firstStrongDirection(value.text),
        minLines: 1,
        maxLines: 2,
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
    TextEditingController? contentLanguage,
    FocusNode? focusNode,
  }) {
    Widget field(Locale? locale) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        // Attribute the exact value the field already exposes, so native
        // accessibility reads of the text stay byte-identical; only the voice
        // hint changes. Empty fields are left untouched.
        final attributedValue = locale == null || value.text.isEmpty
            ? null
            : AttributedString(
                value.text,
                attributes: [
                  LocaleStringAttribute(
                    range: TextRange(start: 0, end: value.text.length),
                    locale: locale,
                  ),
                ],
              );
        return Semantics(
          identifier: key.value,
          attributedValue: attributedValue,
          child: TextField(
            key: key,
            controller: controller,
            focusNode: focusNode,
            onChanged: (_) => _onDocumentChanged(),
            readOnly: !_appResumed,
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
        );
      },
    );
    if (contentLanguage == null) return field(null);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: contentLanguage,
      builder: (context, language, _) =>
          field(parseContentLocale(language.text)),
    );
  }
}

enum _FindStatus { none, found, noMatch, mismatch, replaced, limitExceeded }

class _TemporaryDraftNotice extends StatelessWidget {
  const _TemporaryDraftNotice();

  @override
  Widget build(BuildContext context) {
    final notice = AppLocalizations.of(context)!.temporaryDraftNotice;
    return Semantics(
      label: notice,
      container: true,
      liveRegion: true,
      excludeSemantics: true,
      child: Material(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(12), child: Text(notice)),
      ),
    );
  }
}

class _TranslationFields {
  _TranslationFields(this.inputEnabled);

  final bool Function() inputEnabled;
  late final language = _DraftController(inputEnabled);
  late final text = _DraftController(inputEnabled);
  final textFocusNode = FocusNode();

  void dispose() {
    language.dispose();
    text.dispose();
    textFocusNode.dispose();
  }
}

// A stale input-channel update can reach the controller before a readOnly
// rebuild, so guard the entire editing value synchronously.
class _DraftController extends TextEditingController {
  _DraftController(this.inputEnabled);

  final bool Function() inputEnabled;

  @override
  set value(TextEditingValue newValue) {
    if (inputEnabled()) super.value = newValue;
  }

  // File import is a programmatic replacement, not incoming user input.
  void replaceText(String text) {
    super.value = TextEditingValue(text: text);
  }
}
