// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'ことは | Kotoha';

  @override
  String get workspaceTitle => 'テキスト作業';

  @override
  String get manualEditingNotice => '原文と手入力した訳文を並べて作業できます。自動翻訳は行いません。';

  @override
  String get temporaryDraftNotice => 'この下書きは一時的なものです。このアプリには保存されません。';

  @override
  String get inactiveDraftNotice => '下書きはメモリ内にのみ保持され、Kotohaが非アクティブの間は非表示です。';

  @override
  String get androidImePersonalizedLearning => 'Androidキーボードの個人学習を許可';

  @override
  String get androidImePersonalizedLearningDescription =>
      '各セッションの初期設定では無効です。設定変更は次にテキスト欄へフォーカスしたときに反映されます。有効にすると、Androidの入力方法に入力履歴やユーザー辞書などの個人データの更新を許可します。実際の動作はキーボード側で管理されます。';

  @override
  String get externalKeyboardPrivacyNotice =>
      'このプラットフォームでは、ことはからキーボードの学習を制御できません。入力方法のプライバシー設定をご確認ください。';

  @override
  String get sourceLanguage => '原文の言語';

  @override
  String get sourceLanguageHint => '例: ja';

  @override
  String get sourceText => '原文';

  @override
  String get translations => '訳文';

  @override
  String get clipboardNotice =>
      'コピーした訳文はOSのクリップボードに渡され、OSやクリップボード機能によって参照・保持・共有される場合があります。';

  @override
  String get exportTranslationNotice =>
      '書き出しでは、選択した訳文だけを選んだファイルに保存します。作業内容全体や他の下書きは保存されません。';

  @override
  String get addTranslation => '訳先を追加';

  @override
  String get targetLanguage => '訳先の言語';

  @override
  String get targetLanguageHint => '例: en';

  @override
  String targetLanguageNumber(int number) {
    return '$number件目の訳先の言語';
  }

  @override
  String copyTranslationNumber(int number) {
    return '$number件目の訳文をコピー';
  }

  @override
  String exportTranslationNumber(int number) {
    return '$number件目の訳文を書き出す';
  }

  @override
  String removeTranslationNumber(int number) {
    return '$number件目の訳先を削除';
  }

  @override
  String get removeTranslationTitle => '訳文を削除しますか？';

  @override
  String get removeTranslationQuestion => 'この訳文の言語とテキストは破棄されます。元に戻せません。';

  @override
  String get removeTranslationConfirm => '削除';

  @override
  String get removeTranslationCancel => '保持する';

  @override
  String get manualTranslation => '手入力した訳文';

  @override
  String manualTranslationNumber(int number) {
    return '$number件目の手入力した訳文';
  }

  @override
  String get emptyTranslationNotice => 'コピーする訳文を入力してください';

  @override
  String get clipboardFailureNotice => 'クリップボードにコピーできませんでした';

  @override
  String get clipboardNulNotice =>
      'WindowsのクリップボードではNUL文字を貼り付けできません。訳文を書き出してください。';

  @override
  String get copiedTranslationNotice => '訳文をコピーしました';

  @override
  String get emptyTranslationExportNotice => '書き出す訳文を入力してください';

  @override
  String get exportFailureNotice => '訳文を書き出せませんでした';

  @override
  String get exportedTranslationNotice => '訳文を書き出しました';

  @override
  String get workspaceExportFailureNotice => '作業内容を書き出せませんでした';

  @override
  String get copyWorkspace => '作業内容をコピー';

  @override
  String get copyWorkspaceNotice =>
      'コピーすると原文とすべての訳文がOSのクリップボードに渡されます。作業内容は一時的なままです。';

  @override
  String get emptyWorkspaceCopyNotice => 'コピーする原文または訳文を入力してください。';

  @override
  String get copiedWorkspaceNotice => '作業内容をコピーしました。';

  @override
  String get restoreWorkspace => '作業内容を復元';

  @override
  String get restoreWorkspaceNotice =>
      '復元するとKotoha v2の作業ファイルを読み込み、現在の原文と訳文を置き換えます。';

  @override
  String get restoreWorkspaceTitle => '現在の作業内容を置き換えますか？';

  @override
  String get restoreWorkspaceQuestion =>
      '復元するとこのセッションの原文の言語、原文、すべての訳文が置き換わります。続けますか？';

  @override
  String get restoreWorkspaceReplace => '作業内容を置き換える';

  @override
  String get restoredWorkspaceNotice => '作業内容を復元しました。';

  @override
  String get restoreWorkspaceFailureNotice => '作業内容を復元できませんでした。';

  @override
  String get restoreWorkspaceUnsupportedNotice =>
      'このファイルはKotoha v2の作業エクスポートではありません。';

  @override
  String get restoreWorkspaceTooLargeNotice =>
      'このファイルは大きすぎて復元できません。小さい作業エクスポートを選んでください。';

  @override
  String get restoreWorkspaceUnsupportedTypeNotice =>
      '復元するには.txt、.md、.markdownファイルを選んでください。';

  @override
  String get restoreWorkspaceChangedNotice =>
      '復元中に作業内容が変更されました。編集内容は保持されています。もう一度「作業内容を復元」を選んで再試行してください。';

  @override
  String get restoreWorkspaceSurrogatesTitle => 'エクスポート内の孤立したサロゲート';

  @override
  String get restoreWorkspaceSurrogatesQuestion =>
      'このエクスポートには対になっていないUTF-16サロゲートが含まれています。編集前にU+FFFDへ置き換えます。エクスポートしたファイルは変更されません。続けますか？';

  @override
  String get exportWorkspace => '作業内容を書き出す';

  @override
  String get exportWorkspaceNotice =>
      '書き出しでは、原文とすべての訳文を選んだ一つのファイルに保存します。作業内容は一時的なままです。';

  @override
  String get emptyWorkspaceExportNotice => '書き出す原文または訳文を入力してください。';

  @override
  String get exportedWorkspaceNotice => '作業内容を書き出しました。';

  @override
  String get workspaceExportTooLargeTitle => '復元できないファイルを保存しますか？';

  @override
  String get workspaceExportTooLargeQuestion =>
      'この作業内容はKotohaで復元できるサイズを超えています。UTF-8テキストとしては保存できますが、復元では読み込めません。続けますか？';

  @override
  String get workspaceExportTooLargeContinue => 'それでも保存';

  @override
  String get exportedWorkspaceTooLargeNotice =>
      'テキストとして保存しましたが、Kotohaでは復元できません。';

  @override
  String get exportFileButton => '書き出す';

  @override
  String get licenses => 'ライセンス';

  @override
  String get uiLanguage => '表示言語';

  @override
  String get japanese => '日本語';

  @override
  String get english => 'English';

  @override
  String get importSource => 'テキスト・Markdownを読み込む';

  @override
  String get replaceSourceTitle => '原文を置き換えますか？';

  @override
  String get replaceSourceQuestion => '現在の原文を読み込んだテキストで置き換えます。訳文は変更されません。';

  @override
  String get cancelImport => 'キャンセル';

  @override
  String get replaceSource => '置き換える';

  @override
  String get importFailureNotice =>
      '読み込めませんでした。UTF-8の.txt、.md、.markdownファイルを選択してください。';

  @override
  String get importSourceTooLargeNotice =>
      'このファイルは大きすぎて読み込めません。小さいUTF-8テキストドキュメントを選んでください。';

  @override
  String get importSourceChangedNotice =>
      '読み込み中に原文が変更されました。編集内容は保持されています。再度読み込んでください。';

  @override
  String get reviewModelTerms => 'モデルパッケージの利用条件を確認';

  @override
  String modelTermsTitle(Object name) {
    return '$name の利用条件';
  }

  @override
  String get modelRuntimeDisabled =>
      '利用条件の確認・同意はモデルのインストールや実行を有効にしません。マニフェストと宣言された利用条件のみを読み込みます。';

  @override
  String get modelUsageRequirements => '利用要件';

  @override
  String get modelAttributions => '必要な帰属表示';

  @override
  String get modelAccept => 'このセッションで同意';

  @override
  String get modelDecline => '同意しない';

  @override
  String get modelTermsDeclined => '利用条件に同意しませんでした。承認は記録されていません。';

  @override
  String get modelConsentSessionOnly => 'このセッションのみ利用条件に同意しました。実行機能は有効ではありません。';

  @override
  String get modelPackageFailure => 'パッケージを安全に検証できませんでした。';

  @override
  String get modelIntegrityOnly =>
      'SHA-256ハッシュは読み込んだファイルがマニフェストと一致することのみを確認します。出所・真正性・ライセンス承認を証明するものではありません。';

  @override
  String modelPackageId(String id) {
    return 'パッケージID: $id';
  }

  @override
  String modelDeclaredPublisher(String publisher) {
    return '申告された発行者（未検証）: $publisher';
  }

  @override
  String modelAllTermsVerified(int count) {
    return '宣言された利用条件ファイル$count件すべてを検証してから表示しています。';
  }

  @override
  String get modelSessionActive =>
      'セッションの同意を記録しました（ダイジェストのみ）。モデルはインストールされず、実行機能は有効ではありません。';

  @override
  String get documentOutline => '原文の構成';

  @override
  String get documentOutlineTruncated => '構成は原文の先頭のみを表示します。全文は引き続き編集できます。';

  @override
  String get documentOutlineEmpty => '原文にはまだブロックがありません。';

  @override
  String get documentOutlineUntitled => '（空のブロック）';

  @override
  String get documentOutlineSearch => '構成を検索';

  @override
  String get documentOutlineSearchHint => '構成の項目を絞り込む';

  @override
  String get documentOutlineNoMatches => '検索に一致する構成の項目はありません。';

  @override
  String get documentOutlineMatchesTruncated => '一致する構成の項目は最初の200件のみ表示します。';

  @override
  String get documentOutlineEntriesTruncated =>
      '構成の項目は最初の200件のみ表示します。全文は引き続き編集できます。';

  @override
  String get documentFormatSupport => 'テキスト形式の対応範囲';

  @override
  String get documentFormatSupportHandled => 'ローカルで認識: 見出し、段落、リスト項目、コードブロック。';

  @override
  String get documentFormatSupportPreserved =>
      '原文のテキストとブロックの正確な範囲は編集可能なまま維持し、出力はプレーンテキストです。';

  @override
  String get documentFormatSupportReview =>
      'インライン装飾、数字、リンク、プレースホルダーは変換しません。手動で確認してください。';

  @override
  String get documentReviewLabel => '確認:';

  @override
  String get documentReviewNumber => '数字';

  @override
  String get documentReviewLink => 'リンク';

  @override
  String get documentReviewPlaceholder => 'プレースホルダー';

  @override
  String get documentOutlineReviewOnly => '確認が必要な項目のみ';

  @override
  String get documentOutlineNoReviewMatches => 'ローカルで確認が必要な構成の項目はありません。';

  @override
  String get findReplaceTitle => '検索と置換';

  @override
  String get findReplaceShortcut => 'Ctrl+F / ⌘+F';

  @override
  String get findTarget => '検索対象';

  @override
  String get findSourceTarget => '原文';

  @override
  String findTranslationTarget(int number) {
    return '$number件目の訳文';
  }

  @override
  String get findQuery => '検索語';

  @override
  String get findReplacement => '置換後の文字列';

  @override
  String get findLiteralNotice => '検索はリテラル一致で大文字と小文字を区別します。下書きはメモリ内に保持されます。';

  @override
  String get findNextButton => '次を検索';

  @override
  String get replaceButton => '置換';

  @override
  String get replaceAllButton => 'すべて置換';

  @override
  String get findMatchFound => '一致する文字列が見つかりました。';

  @override
  String get findNoMatch => '一致する文字列はありません。';

  @override
  String get findSelectionMismatch => '置換するには、一致する文字列を選択してください。';

  @override
  String findReplacedCount(int count) {
    return '$count件を置換しました。';
  }

  @override
  String get findLimitExceeded =>
      '置換後のテキストがエディターの上限を超えるため、置換しませんでした。テキストは変更されていません。';
}
