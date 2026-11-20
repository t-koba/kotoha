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

  /// No description provided for @inactiveDraftNotice.
  ///
  /// In ja, this message translates to:
  /// **'下書きはメモリ内にのみ保持され、Kotohaが非アクティブの間は非表示です。'**
  String get inactiveDraftNotice;

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

  /// No description provided for @exportTranslationNotice.
  ///
  /// In ja, this message translates to:
  /// **'書き出しでは、選択した訳文だけを選んだファイルに保存します。作業内容全体や他の下書きは保存されません。'**
  String get exportTranslationNotice;

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

  /// 番号付き訳文の書き出し操作ラベル。
  ///
  /// In ja, this message translates to:
  /// **'{number}件目の訳文を書き出す'**
  String exportTranslationNumber(int number);

  /// 番号付き訳先の削除操作ラベル。
  ///
  /// In ja, this message translates to:
  /// **'{number}件目の訳先を削除'**
  String removeTranslationNumber(int number);

  /// 入力済みの訳文を削除する確認ダイアログのタイトル。
  ///
  /// In ja, this message translates to:
  /// **'訳文を削除しますか？'**
  String get removeTranslationTitle;

  /// 訳文を破棄すると元に戻せないことを伝える警告。
  ///
  /// In ja, this message translates to:
  /// **'この訳文の言語とテキストは破棄されます。元に戻せません。'**
  String get removeTranslationQuestion;

  /// 訳文の削除を確定するボタン。
  ///
  /// In ja, this message translates to:
  /// **'削除'**
  String get removeTranslationConfirm;

  /// 訳文を削除せずに保持するボタン。
  ///
  /// In ja, this message translates to:
  /// **'保持する'**
  String get removeTranslationCancel;

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

  /// No description provided for @emptyTranslationExportNotice.
  ///
  /// In ja, this message translates to:
  /// **'書き出す訳文を入力してください'**
  String get emptyTranslationExportNotice;

  /// No description provided for @exportFailureNotice.
  ///
  /// In ja, this message translates to:
  /// **'訳文を書き出せませんでした'**
  String get exportFailureNotice;

  /// No description provided for @exportedTranslationNotice.
  ///
  /// In ja, this message translates to:
  /// **'訳文を書き出しました'**
  String get exportedTranslationNotice;

  /// テキスト作業全体を選んだファイルへ書き出せなかったときの案内。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を書き出せませんでした'**
  String get workspaceExportFailureNotice;

  /// テキスト作業全体をOSのクリップボードにコピーする操作のラベル。
  ///
  /// In ja, this message translates to:
  /// **'作業内容をコピー'**
  String get copyWorkspace;

  /// 作業内容全体のコピーでOSのクリップボードを使い、作業内容自体は保存しない旨の案内。
  ///
  /// In ja, this message translates to:
  /// **'コピーすると原文とすべての訳文がOSのクリップボードに渡されます。作業内容は一時的なままです。'**
  String get copyWorkspaceNotice;

  /// テキストがない状態で作業内容全体のコピーを求められたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'コピーする原文または訳文を入力してください。'**
  String get emptyWorkspaceCopyNotice;

  /// 作業内容全体のコピーが完了したことを伝える案内。
  ///
  /// In ja, this message translates to:
  /// **'作業内容をコピーしました。'**
  String get copiedWorkspaceNotice;

  /// 以前エクスポートした作業全体を復元する操作のラベル。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を復元'**
  String get restoreWorkspace;

  /// 復元が現在の作業内容をファイルから置き換える旨の案内。
  ///
  /// In ja, this message translates to:
  /// **'復元するとKotoha v2の作業ファイルを読み込み、現在の原文と訳文を置き換えます。'**
  String get restoreWorkspaceNotice;

  /// 作業内容の置き換え前に表示する確認ダイアログのタイトル。
  ///
  /// In ja, this message translates to:
  /// **'現在の作業内容を置き換えますか？'**
  String get restoreWorkspaceTitle;

  /// 作業内容の置き換え確認ダイアログの本文。
  ///
  /// In ja, this message translates to:
  /// **'復元するとこのセッションの原文の言語、原文、すべての訳文が置き換わります。続けますか？'**
  String get restoreWorkspaceQuestion;

  /// 作業内容の置き換えを確定するボタン。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を置き換える'**
  String get restoreWorkspaceReplace;

  /// 作業内容の復元が完了したことを伝える案内。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を復元しました。'**
  String get restoredWorkspaceNotice;

  /// ファイルの読み取りや選択に失敗したときの案内。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を復元できませんでした。'**
  String get restoreWorkspaceFailureNotice;

  /// v2の作業エクスポートとして解析できないファイルの案内。
  ///
  /// In ja, this message translates to:
  /// **'このファイルはKotoha v2の作業エクスポートではありません。'**
  String get restoreWorkspaceUnsupportedNotice;

  /// 作業ファイルがサイズ上限を超えたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'このファイルは大きすぎて復元できません。小さい作業エクスポートを選んでください。'**
  String get restoreWorkspaceTooLargeNotice;

  /// 拡張子が対象外の作業ファイルを選んだときの案内。
  ///
  /// In ja, this message translates to:
  /// **'復元するには.txt、.md、.markdownファイルを選んでください。'**
  String get restoreWorkspaceUnsupportedTypeNotice;

  /// テキスト作業全体を一つのファイルに書き出す操作のラベル。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を書き出す'**
  String get exportWorkspace;

  /// 作業内容全体の書き出しで一つのファイルに保存し、作業内容自体は保存しない旨の案内。
  ///
  /// In ja, this message translates to:
  /// **'書き出しでは、原文とすべての訳文を選んだ一つのファイルに保存します。作業内容は一時的なままです。'**
  String get exportWorkspaceNotice;

  /// テキストがない状態で作業内容全体の書き出しを求められたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'書き出す原文または訳文を入力してください。'**
  String get emptyWorkspaceExportNotice;

  /// 作業内容全体の書き出しが完了したことを伝える案内。
  ///
  /// In ja, this message translates to:
  /// **'作業内容を書き出しました。'**
  String get exportedWorkspaceNotice;

  /// 復元可能なサイズを超える作業エクスポートを保存する前の警告タイトル。
  ///
  /// In ja, this message translates to:
  /// **'復元できないファイルを保存しますか？'**
  String get workspaceExportTooLargeTitle;

  /// サイズ超過の作業エクスポートを保存する前の案内。
  ///
  /// In ja, this message translates to:
  /// **'この作業内容はKotohaで復元できるサイズを超えています。UTF-8テキストとしては保存できますが、復元では読み込めません。続けますか？'**
  String get workspaceExportTooLargeQuestion;

  /// 復元できない作業テキストの保存を確定するボタン。
  ///
  /// In ja, this message translates to:
  /// **'それでも保存'**
  String get workspaceExportTooLargeContinue;

  /// サイズ超過の作業テキストを保存した後の案内。
  ///
  /// In ja, this message translates to:
  /// **'テキストとして保存しましたが、Kotohaでは復元できません。'**
  String get exportedWorkspaceTooLargeNotice;

  /// No description provided for @exportFileButton.
  ///
  /// In ja, this message translates to:
  /// **'書き出す'**
  String get exportFileButton;

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

  /// 読み込むテキストがサイズ上限を超えたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'このファイルは大きすぎて読み込めません。小さいUTF-8テキストドキュメントを選んでください。'**
  String get importSourceTooLargeNotice;

  /// No description provided for @importSourceChangedNotice.
  ///
  /// In ja, this message translates to:
  /// **'読み込み中に原文が変更されました。編集内容は保持されています。再度読み込んでください。'**
  String get importSourceChangedNotice;

  /// No description provided for @reviewModelTerms.
  ///
  /// In ja, this message translates to:
  /// **'モデルパッケージの利用条件を確認'**
  String get reviewModelTerms;

  /// 確認するモデル利用条件のタイトル。
  ///
  /// In ja, this message translates to:
  /// **'{name} の利用条件'**
  String modelTermsTitle(Object name);

  /// No description provided for @modelRuntimeDisabled.
  ///
  /// In ja, this message translates to:
  /// **'利用条件の確認・同意はモデルのインストールや実行を有効にしません。マニフェストと宣言された利用条件のみを読み込みます。'**
  String get modelRuntimeDisabled;

  /// No description provided for @modelUsageRequirements.
  ///
  /// In ja, this message translates to:
  /// **'利用要件'**
  String get modelUsageRequirements;

  /// No description provided for @modelAttributions.
  ///
  /// In ja, this message translates to:
  /// **'必要な帰属表示'**
  String get modelAttributions;

  /// No description provided for @modelAccept.
  ///
  /// In ja, this message translates to:
  /// **'このセッションで同意'**
  String get modelAccept;

  /// No description provided for @modelDecline.
  ///
  /// In ja, this message translates to:
  /// **'同意しない'**
  String get modelDecline;

  /// No description provided for @modelTermsDeclined.
  ///
  /// In ja, this message translates to:
  /// **'利用条件に同意しませんでした。承認は記録されていません。'**
  String get modelTermsDeclined;

  /// No description provided for @modelConsentSessionOnly.
  ///
  /// In ja, this message translates to:
  /// **'このセッションのみ利用条件に同意しました。実行機能は有効ではありません。'**
  String get modelConsentSessionOnly;

  /// No description provided for @modelPackageFailure.
  ///
  /// In ja, this message translates to:
  /// **'パッケージを安全に検証できませんでした。'**
  String get modelPackageFailure;

  /// No description provided for @modelIntegrityOnly.
  ///
  /// In ja, this message translates to:
  /// **'SHA-256ハッシュは読み込んだファイルがマニフェストと一致することのみを確認します。出所・真正性・ライセンス承認を証明するものではありません。'**
  String get modelIntegrityOnly;

  /// 選択したモデルパッケージに記載された未検証の識別子。
  ///
  /// In ja, this message translates to:
  /// **'パッケージID: {id}'**
  String modelPackageId(String id);

  /// 選択したパッケージに記載された未検証の発行者名。
  ///
  /// In ja, this message translates to:
  /// **'申告された発行者（未検証）: {publisher}'**
  String modelDeclaredPublisher(String publisher);

  /// 表示前に宣言された利用条件ファイルをすべて検証した旨。
  ///
  /// In ja, this message translates to:
  /// **'宣言された利用条件ファイル{count}件すべてを検証してから表示しています。'**
  String modelAllTermsVerified(int count);

  /// No description provided for @modelSessionActive.
  ///
  /// In ja, this message translates to:
  /// **'セッションの同意を記録しました（ダイジェストのみ）。モデルはインストールされず、実行機能は有効ではありません。'**
  String get modelSessionActive;

  /// 原文から解析したブロック一覧の見出し。
  ///
  /// In ja, this message translates to:
  /// **'原文の構成'**
  String get documentOutline;

  /// 構成が解析対象の先頭または表示件数の上限を超えた原文の一部を省略したときの案内。
  ///
  /// In ja, this message translates to:
  /// **'構成は原文の先頭のみを表示します。全文は引き続き編集できます。'**
  String get documentOutlineTruncated;

  /// 原文に表示できるブロックがないときの案内。
  ///
  /// In ja, this message translates to:
  /// **'原文にはまだブロックがありません。'**
  String get documentOutlineEmpty;

  /// 解析した文字列が空のブロックに付ける代替ラベル。
  ///
  /// In ja, this message translates to:
  /// **'（空のブロック）'**
  String get documentOutlineUntitled;

  /// 原文の構成をローカルで絞り込む入力欄のラベル。
  ///
  /// In ja, this message translates to:
  /// **'構成を検索'**
  String get documentOutlineSearch;

  /// 原文の構成をローカルで絞り込む入力欄のヒント。
  ///
  /// In ja, this message translates to:
  /// **'構成の項目を絞り込む'**
  String get documentOutlineSearchHint;

  /// 空でない検索語に一致する構成の項目がないときの案内。
  ///
  /// In ja, this message translates to:
  /// **'検索に一致する構成の項目はありません。'**
  String get documentOutlineNoMatches;

  /// 検索に一致する構成の項目が表示件数の上限を超えたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'一致する構成の項目は最初の200件のみ表示します。'**
  String get documentOutlineMatchesTruncated;

  /// 解析範囲は全文だが構成の項目が表示件数の上限を超えたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'構成の項目は最初の200件のみ表示します。全文は引き続き編集できます。'**
  String get documentOutlineEntriesTruncated;

  /// ローカルのテキスト形式に関する対応範囲の見出し。
  ///
  /// In ja, this message translates to:
  /// **'テキスト形式の対応範囲'**
  String get documentFormatSupport;

  /// ローカルのテキストリーダーが認識するブロックの種類。
  ///
  /// In ja, this message translates to:
  /// **'ローカルで認識: 見出し、段落、リスト項目、コードブロック。'**
  String get documentFormatSupportHandled;

  /// ローカルのテキストリーダーが保持するものと出力形式。
  ///
  /// In ja, this message translates to:
  /// **'原文のテキストとブロックの正確な範囲は編集可能なまま維持し、出力はプレーンテキストです。'**
  String get documentFormatSupportPreserved;

  /// ローカルのテキストリーダーが変換しないため利用者が確認する項目。
  ///
  /// In ja, this message translates to:
  /// **'インライン装飾、数字、リンク、プレースホルダーは変換しません。手動で確認してください。'**
  String get documentFormatSupportReview;

  /// 構成の項目に表示するローカルの確認案内接頭辞。
  ///
  /// In ja, this message translates to:
  /// **'確認:'**
  String get documentReviewLabel;

  /// 数字を含む原文に対する確認案内。
  ///
  /// In ja, this message translates to:
  /// **'数字'**
  String get documentReviewNumber;

  /// ウェブまたはメールのリンクを含む原文に対する確認案内。
  ///
  /// In ja, this message translates to:
  /// **'リンク'**
  String get documentReviewLink;

  /// プレースホルダーを含む原文に対する確認案内。
  ///
  /// In ja, this message translates to:
  /// **'プレースホルダー'**
  String get documentReviewPlaceholder;

  /// ローカルの確認案内がある構成の項目だけを表示する切り替え。
  ///
  /// In ja, this message translates to:
  /// **'確認が必要な項目のみ'**
  String get documentOutlineReviewOnly;

  /// 確認のみの絞り込みで構成の項目がすべて隠れたときの案内。
  ///
  /// In ja, this message translates to:
  /// **'ローカルで確認が必要な構成の項目はありません。'**
  String get documentOutlineNoReviewMatches;

  /// No description provided for @findReplaceTitle.
  ///
  /// In ja, this message translates to:
  /// **'検索と置換'**
  String get findReplaceTitle;

  /// No description provided for @findReplaceShortcut.
  ///
  /// In ja, this message translates to:
  /// **'Ctrl+F / ⌘+F'**
  String get findReplaceShortcut;

  /// No description provided for @findTarget.
  ///
  /// In ja, this message translates to:
  /// **'検索対象'**
  String get findTarget;

  /// No description provided for @findSourceTarget.
  ///
  /// In ja, this message translates to:
  /// **'原文'**
  String get findSourceTarget;

  /// 検索と置換の対象となる番号付き訳文のラベル。
  ///
  /// In ja, this message translates to:
  /// **'{number}件目の訳文'**
  String findTranslationTarget(int number);

  /// No description provided for @findQuery.
  ///
  /// In ja, this message translates to:
  /// **'検索語'**
  String get findQuery;

  /// No description provided for @findReplacement.
  ///
  /// In ja, this message translates to:
  /// **'置換後の文字列'**
  String get findReplacement;

  /// No description provided for @findLiteralNotice.
  ///
  /// In ja, this message translates to:
  /// **'検索はリテラル一致で大文字と小文字を区別します。下書きはメモリ内に保持されます。'**
  String get findLiteralNotice;

  /// No description provided for @findNextButton.
  ///
  /// In ja, this message translates to:
  /// **'次を検索'**
  String get findNextButton;

  /// No description provided for @replaceButton.
  ///
  /// In ja, this message translates to:
  /// **'置換'**
  String get replaceButton;

  /// No description provided for @replaceAllButton.
  ///
  /// In ja, this message translates to:
  /// **'すべて置換'**
  String get replaceAllButton;

  /// No description provided for @findNoMatch.
  ///
  /// In ja, this message translates to:
  /// **'一致する文字列はありません。'**
  String get findNoMatch;

  /// No description provided for @findSelectionMismatch.
  ///
  /// In ja, this message translates to:
  /// **'置換するには、一致する文字列を選択してください。'**
  String get findSelectionMismatch;

  /// 検索と置換で置換した件数。
  ///
  /// In ja, this message translates to:
  /// **'{count}件を置換しました。'**
  String findReplacedCount(int count);
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
