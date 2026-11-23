/// In-memory consent records scoped to a purpose, a capability range and the
/// digests of reviewed terms.
///
/// These records are not engine authorization and do not verify origin,
/// authenticity, licensing or runtime capability. Nothing is persisted: every
/// record is explicit, revocable, and cleared with the in-memory review state.
library;

import 'package:kotoha/model_terms_import.dart';

/// The purpose a receipt is scoped to; switching purpose requires a new
/// explicit receipt.
enum ConsentPurpose { translation, ocr, asr, tts }

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

DateTime _requireGrantedAt(DateTime? value) {
  if (value == null) throw ArgumentError('grantedAt is required');
  return value;
}

Set<String> _requireCapabilities(Set<String> value) {
  if (value.isEmpty) {
    throw ArgumentError('capabilityIds must not be empty');
  }
  for (final id in value) {
    _requireId(id, 'capabilityId');
  }
  return Set<String>.unmodifiable(value.toSet());
}

/// Immutable range of capabilities a receipt covers for one model.
class ConsentScope {
  ConsentScope({required String modelId, required Set<String> capabilityIds})
    : modelId = _requireId(modelId, 'modelId'),
      capabilityIds = _requireCapabilities(capabilityIds);

  final String modelId;
  final Set<String> capabilityIds;

  /// Exact id match only; an unknown or differently cased id is not covered.
  bool covers(String capabilityId) => capabilityIds.contains(capabilityId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsentScope &&
          other.modelId == modelId &&
          other.capabilityIds.length == capabilityIds.length &&
          other.capabilityIds.containsAll(capabilityIds));

  @override
  int get hashCode {
    final ids = capabilityIds.toList()..sort();
    return Object.hash(modelId, Object.hashAll(ids));
  }
}

/// An explicit consent record. Equality covers every field, including
/// [revoked]; [revoke] returns a copy and never mutates an existing record.
class ConsentReceipt {
  ConsentReceipt({
    required String id,
    required String manifestDigest,
    required String termsDigest,
    required this.purpose,
    required this.scope,
    DateTime? grantedAt,
    this.revoked = false,
  }) : id = _requireId(id, 'id'),
       manifestDigest = _requireDigest(manifestDigest, 'manifestDigest'),
       termsDigest = _requireDigest(termsDigest, 'termsDigest'),
       grantedAt = _requireGrantedAt(grantedAt);

  final String id;
  final String manifestDigest;
  final String termsDigest;
  final ConsentPurpose purpose;
  final ConsentScope scope;
  final DateTime grantedAt;
  final bool revoked;

  ConsentReceipt revoke() => ConsentReceipt(
    id: id,
    manifestDigest: manifestDigest,
    termsDigest: termsDigest,
    purpose: purpose,
    scope: scope,
    grantedAt: grantedAt,
    revoked: true,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConsentReceipt &&
          other.id == id &&
          other.manifestDigest == manifestDigest &&
          other.termsDigest == termsDigest &&
          other.purpose == purpose &&
          other.scope == scope &&
          other.grantedAt == grantedAt &&
          other.revoked == revoked);

  @override
  int get hashCode => Object.hash(
    id,
    manifestDigest,
    termsDigest,
    purpose,
    scope,
    grantedAt,
    revoked,
  );
}

/// Purely in-memory consent records with explicit revocation. No I/O, no
/// engine authorization and no persistence: all queries fail closed.
class ConsentStore {
  final Map<String, ConsentReceipt> _records = <String, ConsentReceipt>{};

  /// Stores or replaces by [receipt.id]. Another active receipt with the same
  /// purpose, scope and digests is superseded (marked revoked), so at most one
  /// active record exists for that binding.
  void grant(ConsentReceipt receipt) {
    final superseded = _records.entries
        .where(
          (entry) =>
              entry.key != receipt.id &&
              !entry.value.revoked &&
              _sameBinding(entry.value, receipt),
        )
        .map((entry) => entry.key)
        .toList();
    for (final id in superseded) {
      _records[id] = _records[id]!.revoke();
    }
    _records[receipt.id] = receipt;
  }

  /// Marks a stored active receipt revoked; false if unknown or already
  /// revoked.
  bool revoke(String receiptId) {
    final receipt = _records[receiptId];
    if (receipt == null || receipt.revoked) return false;
    _records[receiptId] = receipt.revoke();
    return true;
  }

  /// The unique active receipt for an exact digest and purpose match whose
  /// scope covers [capabilityId], else null. Ambiguity fails closed.
  ConsentReceipt? activeFor(
    String manifestDigest,
    String termsDigest,
    ConsentPurpose purpose,
    String capabilityId,
  ) {
    ConsentReceipt? match;
    for (final receipt in _records.values) {
      if (receipt.revoked ||
          receipt.manifestDigest != manifestDigest ||
          receipt.termsDigest != termsDigest ||
          receipt.purpose != purpose ||
          !receipt.scope.covers(capabilityId)) {
        continue;
      }
      if (match != null) return null;
      match = receipt;
    }
    return match;
  }

  /// Consent-record query only: the authorization is a digest binding, not a
  /// permission to open files or invoke an engine.
  bool isAuthorized(
    EphemeralModelAuthorization authorization,
    ConsentPurpose purpose,
    String capabilityId,
  ) =>
      activeFor(
        authorization.manifestDigest,
        authorization.termsDigest,
        purpose,
        capabilityId,
      ) !=
      null;

  /// Unmodifiable snapshot of all records, active and revoked.
  List<ConsentReceipt> get receipts =>
      List<ConsentReceipt>.unmodifiable(_records.values);

  /// Drops every record (e.g. when a review is declined or fails).
  void clear() => _records.clear();

  static bool _sameBinding(ConsentReceipt a, ConsentReceipt b) =>
      a.manifestDigest == b.manifestDigest &&
      a.termsDigest == b.termsDigest &&
      a.purpose == b.purpose &&
      a.scope == b.scope;
}
