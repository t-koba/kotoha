import 'package:kotoha/document_review_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('local review flags', () {
    test('flags all three review categories in stable order', () {
      final flags = detectDocumentReviewFlags(
        'Version 2 for {name}: https://example.com',
      );
      expect(flags.toList(), [
        DocumentReviewFlag.number,
        DocumentReviewFlag.link,
        DocumentReviewFlag.placeholder,
      ]);
    });

    test('flags decimal digits from non-ASCII scripts too', () {
      expect(detectDocumentReviewFlags('バージョン２'), {DocumentReviewFlag.number});
      expect(detectDocumentReviewFlags('النسخة ٣'), {
        DocumentReviewFlag.number,
      });
      expect(detectDocumentReviewFlags('１２３ and ٤٥٦'), {
        DocumentReviewFlag.number,
      });
      expect(detectDocumentReviewFlags('no digits here'), isEmpty);
    });

    test('leaves ordinary text unflagged', () {
      expect(detectDocumentReviewFlags('plain words only'), isEmpty);
    });

    test('flags an email with an internationalized domain', () {
      expect(detectDocumentReviewFlags('連絡先: editor@例え.テスト'), {
        DocumentReviewFlag.link,
      });
    });

    test('keeps flagging malformed dot-atom email hints', () {
      expect(detectDocumentReviewFlags('user@example..com'), {
        DocumentReviewFlag.link,
      });
      expect(detectDocumentReviewFlags('user@exa..mple.com'), {
        DocumentReviewFlag.link,
      });
    });

    test('recognizes email links and percent placeholders', () {
      expect(detectDocumentReviewFlags('mail user@example.com'), {
        DocumentReviewFlag.link,
      });
      expect(detectDocumentReviewFlags('count %COUNT%'), {
        DocumentReviewFlag.placeholder,
      });
    });
  });
}
