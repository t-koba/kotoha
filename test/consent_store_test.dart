import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/consent_store.dart';
import 'package:kotoha/model_terms_import.dart';

const String _manifestDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _termsDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _otherDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

final DateTime _grantedAt = DateTime.utc(2026, 1, 1);

ConsentScope _scope([Set<String>? capabilityIds]) => ConsentScope(
  modelId: 'synthetic-translation',
  capabilityIds: capabilityIds ?? {'translation.text'},
);

ConsentReceipt _receipt({
  String id = 'receipt-1',
  String manifestDigest = _manifestDigest,
  String termsDigest = _termsDigest,
  ConsentPurpose purpose = ConsentPurpose.translation,
  Set<String>? capabilityIds,
  DateTime? grantedAt,
  bool revoked = false,
}) => ConsentReceipt(
  id: id,
  manifestDigest: manifestDigest,
  termsDigest: termsDigest,
  purpose: purpose,
  scope: _scope(capabilityIds),
  grantedAt: grantedAt ?? _grantedAt,
  revoked: revoked,
);

void main() {
  test(
    'grant exposes a scoped active receipt and authorizes a digest binding',
    () {
      final store = ConsentStore();
      final receipt = _receipt();

      expect(receipt.revoked, isFalse);
      expect(receipt.scope.covers('translation.text'), isTrue);
      expect(receipt.scope.covers('ocr.text'), isFalse);
      expect(receipt.scope.covers('unknown.capability'), isFalse);

      store.grant(receipt);
      expect(store.receipts, [receipt]);
      expect(
        store.activeFor(
          _manifestDigest,
          _termsDigest,
          ConsentPurpose.translation,
          'translation.text',
        ),
        receipt,
      );
      expect(
        store.isAuthorized(
          const EphemeralModelAuthorization(_manifestDigest, _termsDigest),
          ConsentPurpose.translation,
          'translation.text',
        ),
        isTrue,
      );
    },
  );

  test('revocation is explicit and copies never mutate the original', () {
    final receipt = _receipt();
    final revoked = receipt.revoke();

    expect(revoked.revoked, isTrue);
    expect(receipt.revoked, isFalse);
    expect(revoked.id, receipt.id);
    expect(revoked.scope, receipt.scope);
    expect(revoked.grantedAt, receipt.grantedAt);

    final store = ConsentStore()..grant(receipt);
    expect(store.revoke('receipt-1'), isTrue);
    expect(store.revoke('receipt-1'), isFalse);
    expect(store.revoke('unknown-receipt'), isFalse);
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(store.receipts.single.revoked, isTrue);
  });

  test('unmatched digests, purposes, capabilities, or records fail closed', () {
    final store = ConsentStore()
      ..grant(_receipt())
      ..grant(
        _receipt(
          id: 'ocr-receipt',
          purpose: ConsentPurpose.ocr,
          capabilityIds: {'ocr.text'},
        ),
      );

    expect(
      store.activeFor(
        _otherDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(
      store.activeFor(
        _manifestDigest,
        _otherDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.asr,
        'translation.text',
      ),
      isNull,
    );
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'ocr.text',
      ),
      isNull,
    );
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'TRANSLATION.TEXT',
      ),
      isNull,
    );
    expect(
      store.isAuthorized(
        const EphemeralModelAuthorization(_otherDigest, _termsDigest),
        ConsentPurpose.translation,
        'translation.text',
      ),
      isFalse,
    );
    expect(
      store.isAuthorized(
        const EphemeralModelAuthorization(_manifestDigest, _otherDigest),
        ConsentPurpose.translation,
        'translation.text',
      ),
      isFalse,
    );
    expect(
      store.isAuthorized(
        const EphemeralModelAuthorization(_manifestDigest, _termsDigest),
        ConsentPurpose.ocr,
        'translation.text',
      ),
      isFalse,
    );

    expect(store.revoke('receipt-1'), isTrue);
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(
      store.isAuthorized(
        const EphemeralModelAuthorization(_manifestDigest, _termsDigest),
        ConsentPurpose.translation,
        'translation.text',
      ),
      isFalse,
    );
  });

  test('scope is immutable and values compare by value', () {
    final ids = {'translation.text', 'ocr.text'};
    final scope = _scope(ids);
    ids.add('asr.text');

    expect(scope.capabilityIds, {'translation.text', 'ocr.text'});
    expect(
      () => scope.capabilityIds.add('asr.text'),
      throwsA(isA<UnsupportedError>()),
    );
    expect(scope, _scope({'ocr.text', 'translation.text'}));
    expect(scope.hashCode, _scope({'ocr.text', 'translation.text'}).hashCode);
    expect(
      scope ==
          ConsentScope(
            modelId: 'other-model',
            capabilityIds: scope.capabilityIds,
          ),
      isFalse,
    );
    expect(scope == _scope({'translation.text'}), isFalse);

    expect(_receipt(), _receipt());
    expect(_receipt().hashCode, _receipt().hashCode);
    expect(_receipt().revoke() == _receipt(), isFalse);
    expect(_receipt(purpose: ConsentPurpose.ocr) == _receipt(), isFalse);
  });

  test(
    'a second active receipt supersedes the old one for the same binding',
    () {
      final store = ConsentStore()
        ..grant(_receipt(id: 'receipt-1'))
        ..grant(_receipt(id: 'receipt-2'));

      expect(
        store
            .activeFor(
              _manifestDigest,
              _termsDigest,
              ConsentPurpose.translation,
              'translation.text',
            )
            ?.id,
        'receipt-2',
      );
      expect(store.receipts.map((receipt) => receipt.id), [
        'receipt-1',
        'receipt-2',
      ]);
      expect(store.receipts.where((receipt) => !receipt.revoked), hasLength(1));
      expect(store.receipts.first.revoked, isTrue);
      expect(
        () => store.receipts.add(_receipt()),
        throwsA(isA<UnsupportedError>()),
      );

      // Re-granting the same id replaces it instead of duplicating the record.
      store.grant(
        _receipt(id: 'receipt-2', grantedAt: DateTime.utc(2026, 2, 1)),
      );
      expect(store.receipts, hasLength(2));
      expect(
        store
            .activeFor(
              _manifestDigest,
              _termsDigest,
              ConsentPurpose.translation,
              'translation.text',
            )
            ?.grantedAt,
        DateTime.utc(2026, 2, 1),
      );
    },
  );

  test('overlapping active scopes fail closed on ambiguity', () {
    final store = ConsentStore()
      ..grant(_receipt(id: 'narrow'))
      ..grant(
        _receipt(id: 'wide', capabilityIds: {'translation.text', 'ocr.text'}),
      );

    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(
      store
          .activeFor(
            _manifestDigest,
            _termsDigest,
            ConsentPurpose.translation,
            'ocr.text',
          )
          ?.id,
      'wide',
    );
  });

  test('clear drops all records', () {
    final store = ConsentStore()..grant(_receipt());
    expect(store.receipts, isNotEmpty);

    store.clear();

    expect(store.receipts, isEmpty);
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );
    expect(store.revoke('receipt-1'), isFalse);
  });

  test('constructor validation throws ArgumentError on invalid input', () {
    final scope = _scope();
    ConsentReceipt build({
      String id = 'receipt-1',
      String manifestDigest = _manifestDigest,
      String termsDigest = _termsDigest,
      DateTime? grantedAt,
    }) => ConsentReceipt(
      id: id,
      manifestDigest: manifestDigest,
      termsDigest: termsDigest,
      purpose: ConsentPurpose.translation,
      scope: scope,
      grantedAt: grantedAt ?? _grantedAt,
    );

    expect(
      () => ConsentScope(modelId: '', capabilityIds: {'translation.text'}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => ConsentScope(modelId: 'synthetic-translation', capabilityIds: {}),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => ConsentScope(
        modelId: 'synthetic-translation',
        capabilityIds: {'Translation.text'},
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => ConsentScope(
        modelId: 'synthetic-translation',
        capabilityIds: {'1translation'},
      ),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => build(id: 'Receipt-1'), throwsA(isA<ArgumentError>()));
    expect(() => build(id: ''), throwsA(isA<ArgumentError>()));
    expect(
      () => build(manifestDigest: 'A' * 64),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => build(manifestDigest: 'aaaa'), throwsA(isA<ArgumentError>()));
    expect(() => build(termsDigest: 'z' * 64), throwsA(isA<ArgumentError>()));
    expect(
      () => ConsentReceipt(
        id: 'receipt-1',
        manifestDigest: _manifestDigest,
        termsDigest: _termsDigest,
        purpose: ConsentPurpose.translation,
        scope: scope,
        grantedAt: null,
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
