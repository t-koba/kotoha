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
  String get addTranslation => '訳先を追加';

  @override
  String get targetLanguage => '訳先の言語';

  @override
  String get targetLanguageHint => '例: en';

  @override
  String copyTranslationNumber(int number) {
    return '$number件目の訳文をコピー';
  }

  @override
  String removeTranslationNumber(int number) {
    return '$number件目の訳先を削除';
  }

  @override
  String get manualTranslation => '手入力した訳文';

  @override
  String get emptyTranslationNotice => 'コピーする訳文を入力してください';

  @override
  String get clipboardFailureNotice => 'クリップボードにコピーできませんでした';

  @override
  String get copiedTranslationNotice => '訳文をコピーしました';

  @override
  String get licenses => 'ライセンス';

  @override
  String get uiLanguage => '表示言語';

  @override
  String get japanese => '日本語';

  @override
  String get english => 'English';
}
