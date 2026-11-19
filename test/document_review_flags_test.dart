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

    test('leaves ordinary text unflagged', () {
      expect(detectDocumentReviewFlags('plain words only'), isEmpty);
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
