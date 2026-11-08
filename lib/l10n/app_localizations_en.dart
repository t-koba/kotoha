// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Kotoha';

  @override
  String get workspaceTitle => 'Text workspace';

  @override
  String get manualEditingNotice =>
      'Work with source text and manually entered translations side by side. No automatic translation is performed.';

  @override
  String get temporaryDraftNotice =>
      'This draft is temporary. It is not saved in this app.';

  @override
  String get androidImePersonalizedLearning =>
      'Allow Android keyboard learning';

  @override
  String get androidImePersonalizedLearningDescription =>
      'Off by default each session. Changes apply the next time you focus a text field. When enabled, the Android input method may update personalized typing history or dictionaries; actual behavior is controlled by the keyboard.';

  @override
  String get externalKeyboardPrivacyNotice =>
      'Kotoha cannot control keyboard learning on this platform. Check your input method\'s privacy settings.';

  @override
  String get sourceLanguage => 'Source language';

  @override
  String get sourceLanguageHint => 'e.g. ja';

  @override
  String get sourceText => 'Source text';

  @override
  String get translations => 'Translations';

  @override
  String get clipboardNotice =>
      'Copied translations are sent to the OS clipboard and may be accessed, retained, or shared by the OS or clipboard features.';

  @override
  String get exportTranslationNotice =>
      'Export writes only the selected translation to a file you choose; the workspace and other drafts remain temporary.';

  @override
  String get addTranslation => 'Add translation';

  @override
  String get targetLanguage => 'Target language';

  @override
  String get targetLanguageHint => 'e.g. en';

  @override
  String copyTranslationNumber(int number) {
    return 'Copy translation $number';
  }

  @override
  String exportTranslationNumber(int number) {
    return 'Export translation $number';
  }

  @override
  String removeTranslationNumber(int number) {
    return 'Remove translation $number';
  }

  @override
  String get manualTranslation => 'Manual translation';

  @override
  String get emptyTranslationNotice => 'Enter a translation to copy.';

  @override
  String get clipboardFailureNotice => 'Could not copy to the clipboard.';

  @override
  String get copiedTranslationNotice => 'Translation copied.';

  @override
  String get emptyTranslationExportNotice => 'Enter a translation to export.';

  @override
  String get exportFailureNotice => 'Could not export the translation.';

  @override
  String get exportedTranslationNotice => 'Translation exported.';

  @override
  String get exportFileButton => 'Export';

  @override
  String get licenses => 'Licenses';

  @override
  String get uiLanguage => 'Interface language';

  @override
  String get japanese => '日本語';

  @override
  String get english => 'English';

  @override
  String get importSource => 'Import text or Markdown';

  @override
  String get replaceSourceTitle => 'Replace source text?';

  @override
  String get replaceSourceQuestion =>
      'The imported text will replace your current source text. Translations will not change.';

  @override
  String get cancelImport => 'Cancel';

  @override
  String get replaceSource => 'Replace';

  @override
  String get importFailureNotice =>
      'Could not import this document. Choose a UTF-8 .txt, .md, or .markdown file.';

  @override
  String get importSourceChangedNotice =>
      'Source text changed during import. Your edits were kept; import again to retry.';

  @override
  String get reviewModelTerms => 'Review model package terms';

  @override
  String modelTermsTitle(Object name) {
    return 'Terms for $name';
  }

  @override
  String get modelRuntimeDisabled =>
      'Reviewing and accepting terms does not install a model or enable runtime use. Only the manifest and declared terms are read.';

  @override
  String get modelUsageRequirements => 'Usage requirements';

  @override
  String get modelAttributions => 'Required attributions';

  @override
  String get modelAccept => 'Accept for this session';

  @override
  String get modelDecline => 'Decline';

  @override
  String get modelTermsDeclined => 'Terms declined; no approval was recorded.';

  @override
  String get modelConsentSessionOnly =>
      'Terms accepted for this session only. Runtime is not enabled.';

  @override
  String get modelPackageFailure => 'Could not safely verify this package.';

  @override
  String get modelIntegrityOnly =>
      'SHA-256 hashes confirm the files read match the manifest. They do not prove origin, authenticity, or license approval.';

  @override
  String modelPackageId(String id) {
    return 'Package ID: $id';
  }

  @override
  String modelDeclaredPublisher(String publisher) {
    return 'Declared publisher (unverified): $publisher';
  }

  @override
  String modelAllTermsVerified(int count) {
    return 'All $count declared terms files were verified before review.';
  }

  @override
  String get modelSessionActive =>
      'Session acceptance recorded (digests only). No model is installed and runtime is not enabled.';
}
