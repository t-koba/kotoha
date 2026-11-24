import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/acquisition_broker.dart';
import 'package:kotoha/consent_store.dart';
import 'package:kotoha/model_terms_import.dart';

const String _manifestDigest =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String _termsDigest =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String _otherDigest =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
const String _redactedDigest =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
const String _capabilityId = 'translation.text';
const String _destinationId = 'cloud.example';
const String _filePath = 'model/weights.bin';

final DateTime _requestedAt = DateTime.utc(2026, 1, 1);
final DateTime _expiresAt = _requestedAt.add(const Duration(minutes: 5));
final DateTime _now = _requestedAt.add(const Duration(seconds: 1));

DeclaredModelFile _declaredFile([String path = _filePath]) => DeclaredModelFile(
  path: path,
  role: 'weights',
  sizeBytes: 128,
  sha256: _manifestDigest,
);

EphemeralModelAuthorization _authorization({
  String manifestDigest = _manifestDigest,
  String termsDigest = _termsDigest,
  List<DeclaredModelFile>? declaredFiles,
}) => EphemeralModelAuthorization(
  manifestDigest,
  termsDigest,
  declaredFiles ?? <DeclaredModelFile>[_declaredFile()],
);

AcquisitionRequest _request({
  String manifestDigest = _manifestDigest,
  String termsDigest = _termsDigest,
  ConsentPurpose purpose = ConsentPurpose.translation,
  String capabilityId = _capabilityId,
  String destinationId = _destinationId,
  Set<String>? filePaths,
  DateTime? requestedAt,
  DateTime? expiresAt,
}) => AcquisitionRequest(
  manifestDigest: manifestDigest,
  termsDigest: termsDigest,
  purpose: purpose,
  capabilityId: capabilityId,
  destinationId: destinationId,
  filePaths: filePaths ?? <String>{_filePath},
  requestedAt: requestedAt ?? _requestedAt,
  expiresAt: expiresAt ?? _expiresAt,
);

ConsentScope _scope([Set<String>? capabilityIds]) => ConsentScope(
  modelId: 'synthetic-model',
  capabilityIds: capabilityIds ?? <String>{_capabilityId},
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
  grantedAt: grantedAt ?? _requestedAt,
  revoked: revoked,
);

AcquisitionBroker _broker() =>
    AcquisitionBroker(allowedDestinations: <String>{_destinationId});

ConsentStore _consented() => ConsentStore()..grant(_receipt());

void expectRefusal(
  AcquisitionFailure failure, {
  AcquisitionBroker? broker,
  required AcquisitionRequest request,
  required EphemeralModelAuthorization authorization,
  required ConsentStore consents,
  required DateTime now,
}) {
  expect(
    () => (broker ?? _broker()).authorize(
      request: request,
      authorization: authorization,
      consents: consents,
      now: now,
    ),
    throwsA(
      isA<AcquisitionException>()
          .having((e) => e.failure, 'failure', failure)
          .having((e) => e.operation, 'operation', 'authorize'),
    ),
  );
}

// That this module performs no transfer, network, I/O or engine call cannot be
// probed in pure Dart; it is enforced structurally: lib/acquisition_broker.dart
// imports only the consent and model-terms contracts. These tests exercise the
// authorization decision and its fail-closed ordering (design §4.1, §18).
void main() {
  test(
    'allowed request returns a time-limited permission echoing the request',
    () {
      final permission = _broker().authorize(
        request: _request(),
        authorization: _authorization(),
        consents: _consented(),
        now: _now,
      );

      expect(permission.manifestDigest, _manifestDigest);
      expect(permission.termsDigest, _termsDigest);
      expect(permission.purpose, ConsentPurpose.translation);
      expect(permission.capabilityId, _capabilityId);
      expect(permission.destinationId, _destinationId);
      expect(permission.filePaths, <String>{_filePath});
      expect(permission.grantedAt, _now);
      expect(permission.expiresAt, _expiresAt);
      expect(permission.isActiveAt(_now), isTrue);
      expect(permission.isActiveAt(_expiresAt), isFalse);
      expect(
        permission.isActiveAt(_now.subtract(const Duration(seconds: 1))),
        isFalse,
      );
      expect(
        () => permission.filePaths.add('model/extra.bin'),
        throwsUnsupportedError,
      );
    },
  );

  test('expired at and after the deadline', () {
    for (final now in <DateTime>[
      _expiresAt,
      _expiresAt.add(const Duration(milliseconds: 1)),
    ]) {
      expectRefusal(
        AcquisitionFailure.expired,
        request: _request(),
        authorization: _authorization(),
        consents: _consented(),
        now: now,
      );
    }
  });

  test('a request dated after now is refused with no permission', () {
    AcquisitionPermission? permission;
    try {
      permission = _broker().authorize(
        request: _request(requestedAt: _now.add(const Duration(minutes: 1))),
        authorization: _authorization(),
        consents: _consented(),
        now: _now,
      );
      fail('expected a refusal');
    } on AcquisitionException catch (e) {
      expect(e.failure, AcquisitionFailure.notYetValid);
      expect(e.operation, 'authorize');
      expect(e.toString(), 'AcquisitionException(notYetValid: authorize)');
    }
    expect(permission, isNull);
  });

  test('a consent granted after now is refused with no permission', () {
    final consents = ConsentStore()
      ..grant(_receipt(grantedAt: _now.add(const Duration(minutes: 1))));
    AcquisitionPermission? permission;
    try {
      permission = _broker().authorize(
        request: _request(),
        authorization: _authorization(),
        consents: consents,
        now: _now,
      );
      fail('expected a refusal');
    } on AcquisitionException catch (e) {
      expect(e.failure, AcquisitionFailure.notYetValid);
      expect(e.operation, 'authorize');
      expect(e.toString(), 'AcquisitionException(notYetValid: authorize)');
    }
    expect(permission, isNull);
  });

  test('requestedAt and grantedAt equal to now remain valid', () {
    final permission = _broker().authorize(
      request: _request(requestedAt: _now),
      authorization: _authorization(),
      consents: ConsentStore()..grant(_receipt(grantedAt: _now)),
      now: _now,
    );

    expect(permission.grantedAt, _now);
    expect(permission.expiresAt, _expiresAt);
    expect(permission.isActiveAt(_now), isTrue);
    expect(
      permission.isActiveAt(_now.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
  });

  test('inverted lifetime is refused before expiry or identity checks', () {
    for (final expiresAt in <DateTime>[
      _requestedAt,
      _requestedAt.subtract(const Duration(seconds: 1)),
    ]) {
      expectRefusal(
        AcquisitionFailure.invertedLifetime,
        request: _request(expiresAt: expiresAt),
        authorization: _authorization(),
        consents: _consented(),
        now: _now,
      );
    }
  });

  test('either mismatched digest is refused', () {
    expectRefusal(
      AcquisitionFailure.identityMismatch,
      request: _request(manifestDigest: _otherDigest),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
    expectRefusal(
      AcquisitionFailure.identityMismatch,
      request: _request(termsDigest: _otherDigest),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('destination outside the configured allow-list is refused', () {
    expectRefusal(
      AcquisitionFailure.destinationNotAllowed,
      request: _request(destinationId: 'other.example'),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('empty file set is refused at authorization, not construction', () {
    final request = _request(filePaths: <String>{});
    expect(request.filePaths, isEmpty);
    expectRefusal(
      AcquisitionFailure.emptyFileSet,
      request: request,
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('a file outside the declared set is refused', () {
    expectRefusal(
      AcquisitionFailure.undeclaredFile,
      request: _request(filePaths: <String>{_filePath, 'model/extra.bin'}),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('no receipt, wrong purpose and wrong capability have no consent', () {
    expectRefusal(
      AcquisitionFailure.noActiveConsent,
      request: _request(),
      authorization: _authorization(),
      consents: ConsentStore(),
      now: _now,
    );
    expectRefusal(
      AcquisitionFailure.noActiveConsent,
      request: _request(purpose: ConsentPurpose.ocr),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
    expectRefusal(
      AcquisitionFailure.noActiveConsent,
      request: _request(capabilityId: 'ocr.text'),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('a granted then revoked receipt no longer authorizes', () {
    final consents = ConsentStore()..grant(_receipt());
    expect(consents.revoke('receipt-1'), isTrue);
    expectRefusal(
      AcquisitionFailure.noActiveConsent,
      request: _request(),
      authorization: _authorization(),
      consents: consents,
      now: _now,
    );
  });

  test('two active receipts matching one binding fail closed', () {
    final consents = ConsentStore()
      ..grant(_receipt())
      // Distinct scopes avoid superseding: both still cover translation.text.
      ..grant(
        _receipt(
          id: 'receipt-2',
          capabilityIds: <String>{_capabilityId, 'translation.extra'},
        ),
      );
    expect(
      consents.activeFor(
        _manifestDigest,
        _termsDigest,
        ConsentPurpose.translation,
        _capabilityId,
      ),
      isNull,
    );
    expectRefusal(
      AcquisitionFailure.noActiveConsent,
      request: _request(),
      authorization: _authorization(),
      consents: consents,
      now: _now,
    );
  });

  test('default broker with an empty allow-list refuses every request', () {
    expectRefusal(
      AcquisitionFailure.destinationNotAllowed,
      broker: const AcquisitionBroker(),
      request: _request(),
      authorization: _authorization(),
      consents: _consented(),
      now: _now,
    );
  });

  test('exception names only the failure and operation labels', () {
    const sentinelDestination = 'sentinel-destination';
    const sentinelCapability = 'sentinel.capability';
    const sentinelPath = 'sentinel/secret/path.bin';
    try {
      _broker().authorize(
        request: _request(
          manifestDigest: _redactedDigest,
          destinationId: sentinelDestination,
          capabilityId: sentinelCapability,
          filePaths: <String>{sentinelPath},
        ),
        authorization: _authorization(manifestDigest: _redactedDigest),
        consents: ConsentStore(),
        now: _now,
      );
      fail('expected a refusal');
    } on AcquisitionException catch (e) {
      expect(e.failure, AcquisitionFailure.destinationNotAllowed);
      expect(e.operation, 'authorize');
      expect(
        e.toString(),
        'AcquisitionException(destinationNotAllowed: authorize)',
      );
      for (final sentinel in <String>[
        _redactedDigest,
        sentinelDestination,
        sentinelCapability,
        sentinelPath,
        ConsentPurpose.translation.name,
      ]) {
        expect(e.toString(), isNot(contains(sentinel)));
        expect(e.failure.name, isNot(contains(sentinel)));
        expect(e.operation, isNot(contains(sentinel)));
      }
    }
  });

  test('request construction validates ids and digests', () {
    expect(
      () => _request(capabilityId: 'Translation.text'),
      throwsArgumentError,
    );
    expect(() => _request(capabilityId: '-translation'), throwsArgumentError);
    expect(() => _request(destinationId: 'Cloud.example'), throwsArgumentError);
    expect(() => _request(destinationId: ''), throwsArgumentError);
    expect(() => _request(manifestDigest: 'abc'), throwsArgumentError);
    expect(
      () => _request(termsDigest: _termsDigest.toUpperCase()),
      throwsArgumentError,
    );
  });

  test('a malformed allow-list fails closed instead of authorizing', () {
    final broker = AcquisitionBroker(
      allowedDestinations: <String>{'Cloud.example'},
    );
    expect(
      () => broker.authorize(
        request: _request(),
        authorization: _authorization(),
        consents: _consented(),
        now: _now,
      ),
      throwsArgumentError,
    );
  });
}
