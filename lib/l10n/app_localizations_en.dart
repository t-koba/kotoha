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
  String get addTranslation => 'Add translation';

  @override
  String get targetLanguage => 'Target language';

  @override
  String get targetLanguageHint => 'e.g. en';

  @override
  String get copyTranslation => 'Copy translation';

  @override
  String get removeTranslation => 'Remove this target';

  @override
  String get manualTranslation => 'Manual translation';

  @override
  String get emptyTranslationNotice => 'Enter a translation to copy.';

  @override
  String get clipboardFailureNotice => 'Could not copy to the clipboard.';

  @override
  String get copiedTranslationNotice => 'Translation copied.';

  @override
  String get licenses => 'Licenses';

  @override
  String get uiLanguage => 'Interface language';

  @override
  String get japanese => '日本語';

  @override
  String get english => 'English';
}
