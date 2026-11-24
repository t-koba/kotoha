/// In-memory consent records scoped to a purpose, a capability range and the
/// digests of reviewed terms, plus classification of changed conditions.
///
/// These records are not engine authorization and do not verify origin,
/// authenticity, licensing or runtime capability. Nothing is persisted: every
/// record is explicit, revocable, and cleared with the in-memory review state.
/// Change classification is digest/declaration-level decision data for
/// presenting changed conditions (design §7.4); it grants nothing and performs
/// no I/O.
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

// ConsentScope is an open class and covers() is virtual. Rebuild it from the
// declared scalars so a receipt's coverage cannot change after it is granted.
ConsentScope _freezeScope(ConsentScope scope) =>
    ConsentScope(modelId: scope.modelId, capabilityIds: scope.capabilityIds);

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
    required ConsentScope scope,
    DateTime? grantedAt,
    this.revoked = false,
  }) : id = _requireId(id, 'id'),
       manifestDigest = _requireDigest(manifestDigest, 'manifestDigest'),
       termsDigest = _requireDigest(termsDigest, 'termsDigest'),
       scope = _freezeScope(scope),
       grantedAt = _requireGrantedAt(grantedAt);

  final String id;
  final String manifestDigest;
  final String termsDigest;
  final ConsentPurpose purpose;

  /// Plain scope snapshot read once at construction. A caller-owned subclass
  /// cannot later widen or move the coverage of a granted receipt.
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

/// One declared condition bound by a [ConsentReceipt] that can change.
enum ConsentBindingChange { manifest, terms, purpose, model, capability }

/// Decision data from comparing a prior receipt with current declarations.
///
/// This is digest/declaration-level data for presenting affected conditions
/// and deciding whether fresh explicit consent is needed. It grants no
/// consent, authorizes no engine use, verifies no origin or licence, and has no
/// UI, I/O or persistence. Empty [changedBindings] means every compared
/// binding matched; it is not a claim that the model is safe, available or
/// licensed.
class ConsentChangeReport {
  ConsentChangeReport._(Set<ConsentBindingChange> changed)
    : changedBindings = Set<ConsentBindingChange>.unmodifiable(changed);

  /// Each changed binding, reported separately; empty when none changed.
  final Set<ConsentBindingChange> changedBindings;

  bool get manifestChanged =>
      changedBindings.contains(ConsentBindingChange.manifest);

  bool get termsChanged => changedBindings.contains(ConsentBindingChange.terms);

  bool get purposeChanged =>
      changedBindings.contains(ConsentBindingChange.purpose);

  bool get modelChanged => changedBindings.contains(ConsentBindingChange.model);

  /// True when the current capability is outside the prior receipt's scope.
  bool get capabilityChanged =>
      changedBindings.contains(ConsentBindingChange.capability);

  /// Whether changed conditions must be presented and confirmation obtained
  /// before continuing. A single changed binding is enough; an empty report
  /// never extends the receipt to other conditions.
  bool get requiresNewConsent => changedBindings.isNotEmpty;
}

/// Compares [priorReceipt] with the current declared bindings (design §7.4).
///
/// [manifestDigest], [termsDigest], [modelId] and [capabilityId] are the
/// current declared values, [purpose] the declared purpose. Capability change
/// means the current capability is not covered by the prior scope; it says
/// nothing about route support or licensing. Malformed declarations and a
/// revoked [priorReceipt] throw [ArgumentError], which callers must treat as
/// requiring fresh consent: no report that could be read as "no change" is
/// produced. Receipts, stores and engine state are not touched.
ConsentChangeReport classifyConsentChange({
  required ConsentReceipt priorReceipt,
  required String manifestDigest,
  required String termsDigest,
  required ConsentPurpose purpose,
  required String modelId,
  required String capabilityId,
}) {
  if (priorReceipt.revoked) {
    throw ArgumentError.value(
      priorReceipt,
      'priorReceipt',
      'revoked receipt requires new consent',
    );
  }
  final currentManifestDigest = _requireDigest(
    manifestDigest,
    'manifestDigest',
  );
  final currentTermsDigest = _requireDigest(termsDigest, 'termsDigest');
  final currentModelId = _requireId(modelId, 'modelId');
  final currentCapabilityId = _requireId(capabilityId, 'capabilityId');

  final changed = <ConsentBindingChange>{};
  if (priorReceipt.manifestDigest != currentManifestDigest) {
    changed.add(ConsentBindingChange.manifest);
  }
  if (priorReceipt.termsDigest != currentTermsDigest) {
    changed.add(ConsentBindingChange.terms);
  }
  if (priorReceipt.purpose != purpose) {
    changed.add(ConsentBindingChange.purpose);
  }
  if (priorReceipt.scope.modelId != currentModelId) {
    changed.add(ConsentBindingChange.model);
  }
  if (!priorReceipt.scope.covers(currentCapabilityId)) {
    changed.add(ConsentBindingChange.capability);
  }
  return ConsentChangeReport._(changed);
}

/// Purely in-memory consent records with explicit revocation. No I/O, no
/// engine authorization and no persistence: all queries fail closed.
class ConsentStore {
  final Map<String, ConsentReceipt> _records = <String, ConsentReceipt>{};

  /// Stores or replaces by [receipt.id]. Another active receipt with the same
  /// purpose, scope and digests is superseded (marked revoked), so at most one
  /// active record exists for that binding. A revoked [receipt] is rejected:
  /// use [revoke] to withdraw consent instead.
  void grant(ConsentReceipt receipt) {
    if (receipt.revoked) {
      throw ArgumentError.value(
        receipt,
        'receipt',
        'cannot grant an already-revoked receipt',
      );
    }
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
