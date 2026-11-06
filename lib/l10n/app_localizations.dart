import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ja'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ja, this message translates to:
  /// **'ことは | Kotoha'**
  String get appTitle;

  /// No description provided for @workspaceTitle.
  ///
  /// In ja, this message translates to:
  /// **'テキスト作業'**
  String get workspaceTitle;

  /// No description provided for @manualEditingNotice.
  ///
  /// In ja, this message translates to:
  /// **'原文と手入力した訳文を並べて作業できます。自動翻訳は行いません。'**
  String get manualEditingNotice;

  /// No description provided for @temporaryDraftNotice.
  ///
  /// In ja, this message translates to:
  /// **'この下書きは一時的なものです。このアプリには保存されません。'**
  String get temporaryDraftNotice;

  /// No description provided for @androidImePersonalizedLearning.
  ///
  /// In ja, this message translates to:
  /// **'Androidキーボードの個人学習を許可'**
  String get androidImePersonalizedLearning;

  /// No description provided for @androidImePersonalizedLearningDescription.
  ///
  /// In ja, this message translates to:
  /// **'各セッションの初期設定では無効です。設定変更は次にテキスト欄へフォーカスしたときに反映されます。有効にすると、Androidの入力方法に入力履歴やユーザー辞書などの個人データの更新を許可します。実際の動作はキーボード側で管理されます。'**
  String get androidImePersonalizedLearningDescription;

  /// No description provided for @externalKeyboardPrivacyNotice.
  ///
  /// In ja, this message translates to:
  /// **'このプラットフォームでは、ことはからキーボードの学習を制御できません。入力方法のプライバシー設定をご確認ください。'**
  String get externalKeyboardPrivacyNotice;

  /// No description provided for @sourceLanguage.
  ///
  /// In ja, this message translates to:
  /// **'原文の言語'**
  String get sourceLanguage;

  /// No description provided for @sourceLanguageHint.
  ///
  /// In ja, this message translates to:
  /// **'例: ja'**
  String get sourceLanguageHint;

  /// No description provided for @sourceText.
  ///
  /// In ja, this message translates to:
  /// **'原文'**
  String get sourceText;

  /// No description provided for @translations.
  ///
  /// In ja, this message translates to:
  /// **'訳文'**
  String get translations;

  /// No description provided for @clipboardNotice.
  ///
  /// In ja, this message translates to:
  /// **'コピーした訳文はOSのクリップボードに渡され、OSやクリップボード機能によって参照・保持・共有される場合があります。'**
  String get clipboardNotice;

  /// No description provided for @addTranslation.
  ///
  /// In ja, this message translates to:
  /// **'訳先を追加'**
  String get addTranslation;

  /// No description provided for @targetLanguage.
  ///
  /// In ja, this message translates to:
  /// **'訳先の言語'**
  String get targetLanguage;

  /// No description provided for @targetLanguageHint.
  ///
  /// In ja, this message translates to:
  /// **'例: en'**
  String get targetLanguageHint;

  /// 番号付き訳文のコピー操作ラベル。
  ///
  /// In ja, this message translates to:
  /// **'{number}件目の訳文をコピー'**
  String copyTranslationNumber(int number);

  /// 番号付き訳先の削除操作ラベル。
  ///
  /// In ja, this message translates to:
  /// **'{number}件目の訳先を削除'**
  String removeTranslationNumber(int number);

  /// No description provided for @manualTranslation.
  ///
  /// In ja, this message translates to:
  /// **'手入力した訳文'**
  String get manualTranslation;

  /// No description provided for @emptyTranslationNotice.
  ///
  /// In ja, this message translates to:
  /// **'コピーする訳文を入力してください'**
  String get emptyTranslationNotice;

  /// No description provided for @clipboardFailureNotice.
  ///
  /// In ja, this message translates to:
  /// **'クリップボードにコピーできませんでした'**
  String get clipboardFailureNotice;

  /// No description provided for @copiedTranslationNotice.
  ///
  /// In ja, this message translates to:
  /// **'訳文をコピーしました'**
  String get copiedTranslationNotice;

  /// No description provided for @licenses.
  ///
  /// In ja, this message translates to:
  /// **'ライセンス'**
  String get licenses;

  /// No description provided for @uiLanguage.
  ///
  /// In ja, this message translates to:
  /// **'表示言語'**
  String get uiLanguage;

  /// No description provided for @japanese.
  ///
  /// In ja, this message translates to:
  /// **'日本語'**
  String get japanese;

  /// No description provided for @english.
  ///
  /// In ja, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @importSource.
  ///
  /// In ja, this message translates to:
  /// **'テキスト・Markdownを読み込む'**
  String get importSource;

  /// No description provided for @replaceSourceTitle.
  ///
  /// In ja, this message translates to:
  /// **'原文を置き換えますか？'**
  String get replaceSourceTitle;

  /// No description provided for @replaceSourceQuestion.
  ///
  /// In ja, this message translates to:
  /// **'現在の原文を読み込んだテキストで置き換えます。訳文は変更されません。'**
  String get replaceSourceQuestion;

  /// No description provided for @cancelImport.
  ///
  /// In ja, this message translates to:
  /// **'キャンセル'**
  String get cancelImport;

  /// No description provided for @replaceSource.
  ///
  /// In ja, this message translates to:
  /// **'置き換える'**
  String get replaceSource;

  /// No description provided for @importFailureNotice.
  ///
  /// In ja, this message translates to:
  /// **'読み込めませんでした。UTF-8の.txt、.md、.markdownファイルを選択してください。'**
  String get importFailureNotice;

  /// No description provided for @importSourceChangedNotice.
  ///
  /// In ja, this message translates to:
  /// **'読み込み中に原文が変更されました。編集内容は保持されています。再度読み込んでください。'**
  String get importSourceChangedNotice;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
