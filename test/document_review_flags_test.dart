import 'dart:async';
import 'dart:isolate';

import 'package:kotoha/document_review_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void _detectFlagsInIsolate(List<Object> args) {
  final text = args[0] as String;
  final reply = args[1] as SendPort;
  reply.send(detectDocumentReviewFlags(text).toList());
}

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

    test('flags addresses with valid local-part punctuation', () {
      expect(detectDocumentReviewFlags('Contact ops!@example.com'), {
        DocumentReviewFlag.link,
      });
      expect(detectDocumentReviewFlags("o'connor+tag@example.com"), {
        DocumentReviewFlag.link,
      });
    });

    test('an address-like token without a domain dot stays responsive', () {
      final flags = detectDocumentReviewFlags('a@${'b-' * 20000}b!');
      expect(flags, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 3)));

    test('long text without an address stays responsive', () {
      final flags = detectDocumentReviewFlags('${'b-' * 20000}b!');
      expect(flags, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 3)));

    test(
      'a long failing local run with a dot-terminated domain stays responsive',
      () async {
        // A synchronous test body cannot be interrupted by `timeout`, so the
        // call runs in a killable isolate with a hard reply deadline.
        final replies = ReceivePort();
        Isolate? isolate;
        try {
          isolate = await Isolate.spawn(_detectFlagsInIsolate, <Object>[
            '!' * 20000 + '@b-.',
            replies.sendPort,
          ]);
          final flags = await replies.first.timeout(
            const Duration(seconds: 3),
            onTimeout: () => throw TimeoutException(
              'email hint detection did not finish within 3 seconds',
              const Duration(seconds: 3),
            ),
          );
          expect(flags, isEmpty);
        } finally {
          replies.close();
          isolate?.kill(priority: Isolate.immediate);
        }
      },
      timeout: const Timeout(Duration(seconds: 8)),
    );

    test('a mention followed by unrelated prose stays unflagged', () async {
      // A synchronous test body cannot be interrupted by `timeout`, so the
      // call runs in a killable isolate with a hard reply deadline.
      final replies = ReceivePort();
      Isolate? isolate;
      try {
        isolate = await Isolate.spawn(_detectFlagsInIsolate, <Object>[
          '${'word-' * 3000} @team See the notes.',
          replies.sendPort,
        ]);
        final flags = await replies.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw TimeoutException(
            'email hint detection did not finish within 3 seconds',
            const Duration(seconds: 3),
          ),
        );
        expect(flags, isEmpty);
      } finally {
        replies.close();
        isolate?.kill(priority: Isolate.immediate);
      }
    }, timeout: const Timeout(Duration(seconds: 8)));

    test('long text without a marker stays responsive in an isolate', () async {
      // No '@' is present, so the hint scan never starts a domain or
      // local run; the isolate still bounds the wall-clock cost.
      final replies = ReceivePort();
      Isolate? isolate;
      try {
        isolate = await Isolate.spawn(_detectFlagsInIsolate, <Object>[
          '${'b-' * 20000}b!',
          replies.sendPort,
        ]);
        final flags = await replies.first.timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw TimeoutException(
            'email hint detection did not finish within 3 seconds',
            const Duration(seconds: 3),
          ),
        );
        expect(flags, isEmpty);
      } finally {
        replies.close();
        isolate?.kill(priority: Isolate.immediate);
      }
    }, timeout: const Timeout(Duration(seconds: 8)));

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
