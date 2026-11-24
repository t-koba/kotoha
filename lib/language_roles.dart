/// Distinct language roles and canonical language tags for design §2.1.
///
/// This library holds only value objects. A [LanguageTag] is DATA used to tag
/// content; it is not a claim that any model, engine or OS function supports,
/// can process, or can produce that language. Nothing here performs lookup,
/// inference, I/O or platform access.
library;

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

/// An immutable language tag parsed as an RFC 5646 structural subset.
///
/// [LanguageTag.parse] accepts the well-formed `langtag` structure of RFC 5646
/// §2.1: a language (optionally with extended language subtags), followed by
/// an optional script, region, variants, extensions and private use, or a
/// private-use tag beginning with `x`. It also enforces RFC 5646 §2.2.5 rule 5
/// (no repeated variant subtags, compared case-insensitively) and §2.2.6
/// rule 3 (no repeated extension singletons, compared case-insensitively).
/// Repeating a singleton inside private use is not an extension repeat.
///
/// This is structure only: no registry lookup, no subtag membership or prefix
/// checks, and no full canonicalization claim. The canonical form is a
/// deterministic case normalization: lowercase the primary, extended language,
/// variants, extensions and private use; title-case a four-letter script;
/// uppercase a two-letter region (numeric regions are unchanged). Every
/// subtag is retained, including extensions, so a tag such as
/// `sr-Latn-RS-u-nu-latn` is preserved rather than discarded. A `dart:ui`
/// Locale cannot carry extensions, so this parser deliberately does not reuse
/// `parseContentLocale`; content_locale.dart is left untouched.
class LanguageTag {
  LanguageTag._(this._subtags, this.script, this.region)
    : language = _subtags.first,
      canonical = _subtags.join('-');

  static final RegExp _primary = RegExp(r'^[A-Za-z]{2,8}$');
  static final RegExp _privatePrimary = RegExp(r'^[xX]$');
  static final RegExp _extlang = RegExp(r'^[A-Za-z]{3}$');
  static final RegExp _script = RegExp(r'^[A-Za-z]{4}$');
  static final RegExp _regionAlpha = RegExp(r'^[A-Za-z]{2}$');
  static final RegExp _regionDigit = RegExp(r'^[0-9]{3}$');
  static final RegExp _variantLong = RegExp(r'^[A-Za-z0-9]{5,8}$');
  static final RegExp _variantNumeric = RegExp(r'^[0-9][A-Za-z0-9]{3}$');
  static final RegExp _singleton = RegExp(r'^[0-9A-WY-Za-wy-z]$');
  static final RegExp _extensionValue = RegExp(r'^[A-Za-z0-9]{2,8}$');
  static final RegExp _privateValue = RegExp(r'^[A-Za-z0-9]{1,8}$');

  /// Parses [entry] fail-closed; returns null when it is not a well-formed
  /// tag in the supported RFC 5646 structural subset. The input is trimmed;
  /// canonical casing is applied per subtag as described on [LanguageTag].
  static LanguageTag? parse(String entry) {
    final parts = entry.trim().split('-');
    final primary = parts.first;
    final privatePrimary = _privatePrimary.hasMatch(primary);
    if (!privatePrimary && !_primary.hasMatch(primary)) return null;
    for (final part in parts) {
      if (part.isEmpty) return null;
    }

    final canonical = <String>[primary.toLowerCase()];
    var index = 1;
    String? script;
    String? region;
    if (privatePrimary) {
      if (index == parts.length) return null;
      for (; index < parts.length; index++) {
        if (!_privateValue.hasMatch(parts[index])) return null;
        canonical.add(parts[index].toLowerCase());
      }
      return LanguageTag._(List<String>.unmodifiable(canonical), null, null);
    }

    // language = 2*3ALPHA ["-" extlang] / 4ALPHA / 5*8ALPHA
    // extlang = 3ALPHA *2("-" 3ALPHA)
    if (primary.length <= 3) {
      for (
        var seen = 0;
        seen < 3 && index < parts.length && _extlang.hasMatch(parts[index]);
        seen++, index++
      ) {
        canonical.add(parts[index].toLowerCase());
      }
    }
    if (index < parts.length && _isScript(parts[index])) {
      script = _titleCase(parts[index]);
      canonical.add(script);
      index++;
    }
    if (index < parts.length && _isRegion(parts[index])) {
      region = _regionDigit.hasMatch(parts[index])
          ? parts[index]
          : parts[index].toUpperCase();
      canonical.add(region);
      index++;
    }

    // variant = 5*8alphanum / (DIGIT 3alphanum), with no case-insensitive
    // repeats (RFC 5646 §2.2.5 rule 5).
    final variants = <String>{};
    for (; index < parts.length && _isVariant(parts[index]); index++) {
      final variant = parts[index].toLowerCase();
      if (!variants.add(variant)) return null;
      canonical.add(variant);
    }

    // extension = singleton 1*("-" 2*8alphanum), with no case-insensitive
    // repeated singleton (RFC 5646 §2.2.6 rule 3).
    final singletons = <String>{};
    while (index < parts.length && !_privatePrimary.hasMatch(parts[index])) {
      final singleton = parts[index].toLowerCase();
      if (!_singleton.hasMatch(singleton)) return null;
      if (!singletons.add(singleton)) return null;
      canonical.add(singleton);
      index++;
      var values = 0;
      while (index < parts.length && _extensionValue.hasMatch(parts[index])) {
        canonical.add(parts[index].toLowerCase());
        index++;
        values++;
      }
      if (values == 0) return null;
    }

    // privateuse = "x" 1*("-" 1*8alphanum)
    if (index < parts.length) {
      canonical.add('x');
      index++;
      if (index == parts.length) return null;
      for (; index < parts.length; index++) {
        if (!_privateValue.hasMatch(parts[index])) return null;
        canonical.add(parts[index].toLowerCase());
      }
    }
    return LanguageTag._(List<String>.unmodifiable(canonical), script, region);
  }

  /// Lowercase primary language subtag (or the private-use `x` marker).
  final String language;

  /// Canonical four-letter script subtag, or null when absent.
  final String? script;

  /// Canonical region subtag (two letters or three digits), or null.
  final String? region;

  /// Canonical tag string, e.g. `sr-Latn-RS-u-nu-latn`.
  final String canonical;

  final List<String> _subtags;

  /// All canonical subtags in order, including extended language, variants,
  /// extensions and private use; unmodifiable.
  List<String> get subtags => _subtags;

  static bool _isScript(String part) => _script.hasMatch(part);

  static bool _isRegion(String part) =>
      _regionAlpha.hasMatch(part) || _regionDigit.hasMatch(part);

  static bool _isVariant(String part) =>
      _variantLong.hasMatch(part) || _variantNumeric.hasMatch(part);

  static String _titleCase(String part) =>
      part[0].toUpperCase() + part.substring(1).toLowerCase();

  @override
  String toString() => canonical;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LanguageTag && other.canonical == canonical);

  @override
  int get hashCode => canonical.hashCode;
}

/// Immutable bindings of tags to the distinct language roles.
///
/// Each role is independent: binding or correcting one never changes another.
/// A user correction is simply a new binding for that role. Every construction
/// path defensively copies its source map, so later caller mutations cannot
/// alter a profile's bindings.
class LanguageProfile {
  /// An empty profile.
  const LanguageProfile() : _bindings = const <LanguageRole, LanguageTag>{};

  /// Builds a profile from [bindings], copying them so the caller retains no
  /// mutable reference into this profile.
  factory LanguageProfile.from(Map<LanguageRole, LanguageTag> bindings) =>
      LanguageProfile._(Map<LanguageRole, LanguageTag>.unmodifiable(bindings));

  LanguageProfile._(this._bindings);

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
    return LanguageProfile.from(next);
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
