/// In-memory acquisition authorization decisions for design §4.1 and §18.
///
/// An [AcquisitionBroker] decides whether a purpose-scoped, destination-bound,
/// time-limited acquisition request may proceed. This is a decision only: the
/// module opens no files, performs no transfer, network or engine call, stores
/// nothing and grants no runtime capability. A [AcquisitionPermission] is a
/// volatile record of that decision, never a proof of origin, authenticity,
/// licensing or quality.
library;

import 'package:kotoha/consent_store.dart';
import 'package:kotoha/model_terms_import.dart';

final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final RegExp _digestPattern = RegExp(r'^[a-f0-9]{64}$');

String _requireId(String value, String name) {
  if (!_idPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'invalid lowercase id');
  }
  return value;
}

String _requireDigest(String value, String name) {
  if (!_digestPattern.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'invalid sha-256 digest');
  }
  return value;
}

Set<String> _requireFilePaths(Set<String> value) =>
    Set<String>.unmodifiable(value.toSet());

/// Policy configuration is snapshotted at construction: later mutation of a
/// caller-owned set must never widen the broker's allow-list.
Set<String> _snapshotDestinations(Set<String> value) =>
    Set<String>.unmodifiable(value.toSet());

/// Classification of a refused authorization decision. Deliberately carries
/// no path, destination, purpose, digest, content, engine or provider detail.
enum AcquisitionFailure {
  expired,
  notYetValid,
  invertedLifetime,
  destinationNotAllowed,
  identityMismatch,
  noActiveConsent,
  emptyFileSet,
  undeclaredFile,
}

/// A refused authorization decision. [operation] names only the caller's
/// operation label, never an identity, destination, path or content.
class AcquisitionException implements Exception {
  const AcquisitionException(this.failure, this.operation);

  final AcquisitionFailure failure;
  final String operation;

  @override
  String toString() => 'AcquisitionException(${failure.name}: $operation)';
}

/// Immutable request for a time-limited acquisition decision.
///
/// Identifier and digest formats are checked here; an empty [filePaths] is not
/// rejected until [AcquisitionBroker.authorize], which owns that refusal.
class AcquisitionRequest {
  AcquisitionRequest({
    required String manifestDigest,
    required String termsDigest,
    required this.purpose,
    required String capabilityId,
    required String destinationId,
    required Set<String> filePaths,
    required this.requestedAt,
    required this.expiresAt,
  }) : manifestDigest = _requireDigest(manifestDigest, 'manifestDigest'),
       termsDigest = _requireDigest(termsDigest, 'termsDigest'),
       capabilityId = _requireId(capabilityId, 'capabilityId'),
       destinationId = _requireId(destinationId, 'destinationId'),
       filePaths = _requireFilePaths(filePaths);

  final String manifestDigest;
  final String termsDigest;
  final ConsentPurpose purpose;
  final String capabilityId;
  final String destinationId;
  final Set<String> filePaths;
  final DateTime requestedAt;
  final DateTime expiresAt;
}

/// Immutable record of a successful authorization decision.
class AcquisitionPermission {
  AcquisitionPermission({
    required this.manifestDigest,
    required this.termsDigest,
    required this.purpose,
    required this.capabilityId,
    required this.destinationId,
    required Set<String> filePaths,
    required this.grantedAt,
    required this.expiresAt,
  }) : filePaths = _requireFilePaths(filePaths);

  final String manifestDigest;
  final String termsDigest;
  final ConsentPurpose purpose;
  final String capabilityId;
  final String destinationId;
  final Set<String> filePaths;
  final DateTime grantedAt;
  final DateTime expiresAt;

  /// Active from [grantedAt] (inclusive) up to [expiresAt] (exclusive).
  bool isActiveAt(DateTime now) =>
      !now.isBefore(grantedAt) && now.isBefore(expiresAt);
}

/// Fail-closed authorization decisions for acquisition and transfer (§4.1).
///
/// The allow-list is policy supplied by configuration; the default empty set
/// allows nothing. Its ids are checked before any decision, and consent is
/// verified last, so no permission exists without an active matching receipt.
/// A refusal throws before any permission is created.
class AcquisitionBroker {
  AcquisitionBroker({Set<String> allowedDestinations = const <String>{}})
    : allowedDestinations = _snapshotDestinations(allowedDestinations);

  /// Immutable snapshot of configured destinations this broker may authorize.
  /// Ids must be lowercase ids; invalid entries fail closed rather than
  /// permitting a transfer. Later mutation of a caller-owned set cannot widen
  /// this policy. Not a network address resolution, availability or trust claim.
  final Set<String> allowedDestinations;

  /// Decide whether [request] is permitted at [now].
  ///
  /// No transfer, file access, engine call or state change happens here. Every
  /// refusal is thrown as [AcquisitionException] with operation `authorize`.
  AcquisitionPermission authorize({
    required AcquisitionRequest request,
    required EphemeralModelAuthorization authorization,
    required ConsentStore consents,
    required DateTime now,
  }) {
    // Configuration is checked before any decision: a malformed allow-list
    // cannot silently authorize a destination. This is a developer error,
    // not a request refusal, so it is not an AcquisitionFailure.
    for (final destination in allowedDestinations) {
      _requireId(destination, 'allowedDestinations');
    }
    if (!request.expiresAt.isAfter(request.requestedAt)) {
      throw const AcquisitionException(
        AcquisitionFailure.invertedLifetime,
        'authorize',
      );
    }
    if (!now.isBefore(request.expiresAt)) {
      throw const AcquisitionException(AcquisitionFailure.expired, 'authorize');
    }
    if (now.isBefore(request.requestedAt)) {
      throw const AcquisitionException(
        AcquisitionFailure.notYetValid,
        'authorize',
      );
    }
    if (request.manifestDigest != authorization.manifestDigest ||
        request.termsDigest != authorization.termsDigest) {
      throw const AcquisitionException(
        AcquisitionFailure.identityMismatch,
        'authorize',
      );
    }
    if (!allowedDestinations.contains(request.destinationId)) {
      throw const AcquisitionException(
        AcquisitionFailure.destinationNotAllowed,
        'authorize',
      );
    }
    if (request.filePaths.isEmpty) {
      throw const AcquisitionException(
        AcquisitionFailure.emptyFileSet,
        'authorize',
      );
    }
    final declaredFiles = authorization.declaredFiles
        .map((file) => file.path)
        .toSet();
    if (!declaredFiles.containsAll(request.filePaths)) {
      throw const AcquisitionException(
        AcquisitionFailure.undeclaredFile,
        'authorize',
      );
    }
    final consent = consents.activeFor(
      request.manifestDigest,
      request.termsDigest,
      request.purpose,
      request.capabilityId,
    );
    if (consent == null) {
      throw const AcquisitionException(
        AcquisitionFailure.noActiveConsent,
        'authorize',
      );
    }
    if (consent.grantedAt.isAfter(now)) {
      throw const AcquisitionException(
        AcquisitionFailure.notYetValid,
        'authorize',
      );
    }
    return AcquisitionPermission(
      manifestDigest: request.manifestDigest,
      termsDigest: request.termsDigest,
      purpose: request.purpose,
      capabilityId: request.capabilityId,
      destinationId: request.destinationId,
      filePaths: request.filePaths,
      grantedAt: now,
      expiresAt: request.expiresAt,
    );
  }
}
