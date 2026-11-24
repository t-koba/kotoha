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

class _FlipScope extends ConsentScope {
  _FlipScope()
    : super(
        modelId: 'synthetic-translation',
        capabilityIds: const {'translation.text'},
      );

  bool widened = false;

  @override
  bool covers(String capabilityId) => widened || super.covers(capabilityId);
}

class _FlipReceipt extends ConsentReceipt {
  _FlipReceipt()
    : super(
        id: 'receipt-1',
        manifestDigest: _manifestDigest,
        termsDigest: _termsDigest,
        purpose: ConsentPurpose.translation,
        scope: _scope(),
        grantedAt: _grantedAt,
      );

  bool flipped = false;

  @override
  String get manifestDigest => flipped ? _otherDigest : super.manifestDigest;

  @override
  String get termsDigest => flipped ? _otherDigest : super.termsDigest;

  @override
  ConsentPurpose get purpose => flipped ? ConsentPurpose.ocr : super.purpose;

  @override
  ConsentScope get scope => flipped ? _scope({'ocr.text'}) : super.scope;

  @override
  DateTime get grantedAt =>
      flipped ? DateTime.utc(2030, 1, 1) : super.grantedAt;
}

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

ConsentChangeReport _classify({
  ConsentReceipt? priorReceipt,
  String? manifestDigest,
  String? termsDigest,
  ConsentPurpose? purpose,
  String? modelId,
  String? capabilityId,
}) {
  final prior = priorReceipt ?? _receipt();
  return classifyConsentChange(
    priorReceipt: prior,
    manifestDigest: manifestDigest ?? prior.manifestDigest,
    termsDigest: termsDigest ?? prior.termsDigest,
    purpose: purpose ?? prior.purpose,
    modelId: modelId ?? prior.scope.modelId,
    capabilityId: capabilityId ?? prior.scope.capabilityIds.first,
  );
}

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

  test(
    'grant rejects an already-revoked receipt without losing active consent',
    () {
      final store = ConsentStore()..grant(_receipt(id: 'receipt-1'));

      expect(
        () => store.grant(_receipt(id: 'receipt-2', revoked: true)),
        throwsA(isA<ArgumentError>()),
      );

      // The existing active receipt is untouched: no silent revocation and no
      // new record stored.
      expect(
        store
            .activeFor(
              _manifestDigest,
              _termsDigest,
              ConsentPurpose.translation,
              'translation.text',
            )
            ?.id,
        'receipt-1',
      );
      expect(store.receipts, hasLength(1));
      expect(store.receipts.single.revoked, isFalse);
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

  test('unchanged conditions require no new consent', () {
    final unchanged = _classify();

    expect(unchanged.changedBindings, isEmpty);
    expect(unchanged.requiresNewConsent, isFalse);
    expect(unchanged.manifestChanged, isFalse);
    expect(unchanged.termsChanged, isFalse);
    expect(unchanged.purposeChanged, isFalse);
    expect(unchanged.modelChanged, isFalse);
    expect(unchanged.capabilityChanged, isFalse);

    // A wider prior scope still covers either of its declared capabilities.
    final wide = _receipt(capabilityIds: {'translation.text', 'ocr.text'});
    for (final capability in wide.scope.capabilityIds) {
      final report = _classify(priorReceipt: wide, capabilityId: capability);
      expect(report.changedBindings, isEmpty);
      expect(report.requiresNewConsent, isFalse);
    }
  });

  test(
    'each changed binding is reported separately and requires new consent',
    () {
      final cases = <(String, ConsentBindingChange, ConsentChangeReport)>[
        (
          'manifest',
          ConsentBindingChange.manifest,
          _classify(manifestDigest: _otherDigest),
        ),
        (
          'terms',
          ConsentBindingChange.terms,
          _classify(termsDigest: _otherDigest),
        ),
        (
          'purpose',
          ConsentBindingChange.purpose,
          _classify(purpose: ConsentPurpose.ocr),
        ),
        (
          'model',
          ConsentBindingChange.model,
          _classify(modelId: 'other-model'),
        ),
        (
          'capability',
          ConsentBindingChange.capability,
          _classify(capabilityId: 'ocr.text'),
        ),
      ];
      final getters =
          <ConsentBindingChange, bool Function(ConsentChangeReport)>{
            ConsentBindingChange.manifest: (report) => report.manifestChanged,
            ConsentBindingChange.terms: (report) => report.termsChanged,
            ConsentBindingChange.purpose: (report) => report.purposeChanged,
            ConsentBindingChange.model: (report) => report.modelChanged,
            ConsentBindingChange.capability: (report) =>
                report.capabilityChanged,
          };

      for (final (label, expected, report) in cases) {
        expect(report.changedBindings, {expected}, reason: label);
        expect(report.requiresNewConsent, isTrue, reason: label);
        for (final entry in getters.entries) {
          expect(
            entry.value(report),
            entry.key == expected,
            reason: '$label / ${entry.key.name}',
          );
        }
      }
    },
  );

  test('multiple simultaneous changes are all reported', () {
    final report = _classify(
      manifestDigest: _otherDigest,
      termsDigest: _otherDigest,
      purpose: ConsentPurpose.asr,
      modelId: 'other-model',
      capabilityId: 'ocr.text',
    );

    expect(report.changedBindings, ConsentBindingChange.values.toSet());
    expect(report.requiresNewConsent, isTrue);
  });

  test('a revoked prior receipt fails closed', () {
    final prior = _receipt().revoke();

    expect(() => _classify(priorReceipt: prior), throwsA(isA<ArgumentError>()));
    expect(
      () => _classify(priorReceipt: prior, manifestDigest: _otherDigest),
      throwsA(isA<ArgumentError>()),
    );
    expect(prior.revoked, isTrue);
  });

  test('malformed current declarations fail closed', () {
    expect(
      () => _classify(manifestDigest: 'A' * 64),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => _classify(manifestDigest: 'aaaa'),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => _classify(termsDigest: 'z' * 64),
      throwsA(isA<ArgumentError>()),
    );
    expect(
      () => _classify(modelId: 'Synthetic-Translation'),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => _classify(modelId: '1model'), throwsA(isA<ArgumentError>()));
    expect(
      () => _classify(capabilityId: 'Translation.text'),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => _classify(capabilityId: ''), throwsA(isA<ArgumentError>()));
  });

  test('classification grants nothing and changes no consent state', () {
    final receipt = _receipt();
    final store = ConsentStore()..grant(receipt);
    final changed = _classify(manifestDigest: _otherDigest);

    expect(changed.requiresNewConsent, isTrue);
    expect(
      () => changed.changedBindings.add(ConsentBindingChange.terms),
      throwsA(isA<UnsupportedError>()),
    );
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
      store.activeFor(
        _otherDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNull,
    );

    expect(store.revoke('receipt-1'), isTrue);
    expect(
      () => _classify(priorReceipt: store.receipts.single),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a receipt freezes its scope against later caller mutation', () {
    final scope = _FlipScope();
    final receipt = ConsentReceipt(
      id: 'receipt-1',
      manifestDigest: _manifestDigest,
      termsDigest: _termsDigest,
      purpose: ConsentPurpose.translation,
      scope: scope,
      grantedAt: _grantedAt,
    );
    final store = ConsentStore()..grant(receipt);

    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'ocr.text',
      ),
      isNull,
    );

    scope.widened = true;
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'ocr.text',
      ),
      isNull,
    );
    expect(receipt.scope, isA<ConsentScope>());
    expect(receipt.scope.runtimeType, ConsentScope);
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      receipt,
    );
    expect(receipt.revoke().scope, receipt.scope);
  });

  test('grant snapshots the receipt against later caller mutation', () {
    final receipt = _FlipReceipt();
    final store = ConsentStore()..grant(receipt);

    bool active(String manifest, ConsentPurpose purpose, String capability) =>
        store.activeFor(manifest, _termsDigest, purpose, capability) != null;

    expect(
      active(_manifestDigest, ConsentPurpose.translation, 'translation.text'),
      isTrue,
    );
    expect(active(_otherDigest, ConsentPurpose.ocr, 'ocr.text'), isFalse);

    receipt.flipped = true;
    expect(store.receipts.single.termsDigest, _termsDigest);
    expect(store.receipts.single.grantedAt, _grantedAt);
    expect(store.receipts.single.runtimeType, ConsentReceipt);
    expect(
      active(_manifestDigest, ConsentPurpose.translation, 'translation.text'),
      isTrue,
    );
    expect(active(_otherDigest, ConsentPurpose.ocr, 'ocr.text'), isFalse);
    expect(
      store.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        'translation.text',
      ),
      isNotNull,
    );
  });
}
