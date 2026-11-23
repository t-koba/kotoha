/// Distinct language roles and canonical language tags for design §2.1.
///
/// This library holds only value objects. A [LanguageTag] is DATA used to tag
/// content; it is not a claim that any model, engine or OS function supports,
/// can process, or can produce that language. Nothing here performs lookup,
/// inference, I/O or platform access.
library;

import 'content_locale.dart' show parseContentLocale;

/// The separate language fields design §2.1 requires be kept distinct.
///
/// Keeping these as distinct enum values prevents, for example, the UI display
/// language from silently standing in for the input or output language.
enum LanguageRole {
  /// Language used for UI messages.
  uiDisplay,

  /// Language of the source content being processed.
  input,

  /// Language estimated for a specific segment.
  segmentEstimated,

  /// Language of the produced output.
  outputDestination,

  /// Language a participant wants to read.
  participantReading,

  /// Language used when reading content aloud.
  voice,
}

/// A canonical, immutable BCP-47-like language tag.
///
/// Parsing is delegated to the existing fail-closed [parseContentLocale], so a
/// well-formed primary language with an optional script and region is accepted
/// and anything else (variants, extensions, wrong subtag order, arbitrary
/// names) is rejected. Canonical form is lowercase language, title-case script
/// and uppercase region, so tags compare by identity regardless of input case.
class LanguageTag {
  LanguageTag._(this.language, this.script, this.region)
    : _canonical = _compose(language, script, region);

  /// Lowercase primary language subtag.
  final String language;

  /// Title-case script subtag, or null when absent.
  final String? script;

  /// Uppercase region subtag, or null when absent.
  final String? region;

  final String _canonical;

  /// Parses [entry] fail-closed; returns null when it is not a well-formed
  /// language (plus optional script and region) tag.
  static LanguageTag? parse(String entry) {
    final locale = parseContentLocale(entry);
    if (locale == null) return null;
    final language = locale.languageCode.toLowerCase();
    final scriptCode = locale.scriptCode;
    final countryCode = locale.countryCode;
    final script = (scriptCode == null || scriptCode.isEmpty)
        ? null
        : scriptCode;
    final region = (countryCode == null || countryCode.isEmpty)
        ? null
        : countryCode;
    return LanguageTag._(language, script, region);
  }

  /// Canonical tag string, e.g. `en-Latn-US`.
  String get canonical => _canonical;

  static String _compose(String language, String? script, String? region) {
    final buffer = StringBuffer(language);
    if (script != null) buffer.write('-$script');
    if (region != null) buffer.write('-$region');
    return buffer.toString();
  }

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LanguageTag && other._canonical == _canonical);

  @override
  int get hashCode => _canonical.hashCode;
}

/// Immutable bindings of tags to the distinct language roles.
///
/// Each role is independent: binding or correcting one never changes another.
/// A user correction is simply a new binding for that role.
class LanguageProfile {
  const LanguageProfile([this._bindings = const <LanguageRole, LanguageTag>{}]);

  final Map<LanguageRole, LanguageTag> _bindings;

  /// The tag bound to [role], or null when that role is unset.
  LanguageTag? tag(LanguageRole role) => _bindings[role];

  /// Roles currently bound; unmodifiable.
  Iterable<LanguageRole> get boundRoles => _bindings.keys;

  /// Returns a new profile with [role] bound to [tag]; all other roles keep
  /// their existing bindings. Passing null clears just that role's binding.
  LanguageProfile withTag(LanguageRole role, LanguageTag? tag) {
    final next = <LanguageRole, LanguageTag>{..._bindings};
    if (tag == null) {
      next.remove(role);
    } else {
      next[role] = tag;
    }
    return LanguageProfile(Map<LanguageRole, LanguageTag>.unmodifiable(next));
  }
}

/// A language estimate for content: ordered candidates plus caller-supplied
/// evidence provenance.
///
/// Design §2.1 requires treating an estimate as undetermined until there is
/// enough evidence. This value object does not decide sufficiency: the caller
/// supplies [confirmed]. The [resolved] tag is available only when the caller
/// has confirmed the evidence and exactly one candidate remains.
class LanguageEstimate {
  const LanguageEstimate(
    this.candidates, {
    this.evidenceRef,
    this.confirmed = false,
  });

  /// Candidate tags in the caller's order.
  final List<LanguageTag> candidates;

  /// Caller-supplied evidence provenance, when present.
  final String? evidenceRef;

  /// Whether the caller has judged the evidence sufficient.
  final bool confirmed;

  /// True only when evidence is confirmed and exactly one candidate remains.
  bool get isDetermined => confirmed && candidates.length == 1;

  /// The single determined tag, or null while the estimate is undetermined.
  LanguageTag? get resolved => isDetermined ? candidates.single : null;
}
