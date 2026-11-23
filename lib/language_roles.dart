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

/// A canonical, immutable BCP-47-like language tag.
///
/// Parsing is fail-closed and follows the same shape as the product's spec
/// schemas (`^(?:[A-Za-z]{2,8}(?:-[A-Za-z0-9]{1,8})*|[xX](?:-[A-Za-z0-9]{1,8})+)$`):
/// a two-to-eight letter primary (or the `x` private-use marker) followed by
/// one-to-eight alphanumeric subtags. Every subtag is retained, including
/// script, region, variants and extensions, so a tag such as
/// `sr-Latn-RS-u-nu-latn` is preserved rather than discarded. A `dart:ui`
/// Locale cannot carry extensions, so this parser deliberately does not reuse
/// `parseContentLocale`; content_locale.dart is left untouched.
class LanguageTag {
  LanguageTag._(this._subtags, this.script, this.region)
    : language = _subtags.first,
      canonical = _subtags.join('-');

  static final RegExp _primary = RegExp(r'^[A-Za-z]{2,8}$');
  static final RegExp _privatePrimary = RegExp(r'^[xX]$');
  static final RegExp _subtag = RegExp(r'^[A-Za-z0-9]{1,8}$');
  static final RegExp _letters = RegExp(r'^[A-Za-z]+$');
  static final RegExp _digits = RegExp(r'^[0-9]+$');

  /// Parses [entry] fail-closed; returns null when it is not a well-formed
  /// language tag. The input is trimmed; canonical form lowercases the primary
  /// and any trailing subtags, title-cases a four-letter script immediately
  /// after the primary, and uppercases a following two-letter region.
  static LanguageTag? parse(String entry) {
    final tag = entry.trim();
    if (tag.isEmpty) return null;
    final parts = tag.split('-');
    final primary = parts.first;
    final privatePrimary = _privatePrimary.hasMatch(primary);
    if (!privatePrimary && !_primary.hasMatch(primary)) return null;
    for (final part in parts.skip(1)) {
      if (!_subtag.hasMatch(part)) return null;
    }
    if (privatePrimary && parts.length < 2) return null;

    final canonical = <String>[primary.toLowerCase()];
    var index = 1;
    String? script;
    String? region;
    if (index < parts.length && _isScript(parts[index])) {
      script = _titleCase(parts[index]);
      canonical.add(script);
      index++;
    }
    if (index < parts.length && _isRegion(parts[index])) {
      region = _digits.hasMatch(parts[index])
          ? parts[index]
          : parts[index].toUpperCase();
      canonical.add(region);
      index++;
    }
    for (; index < parts.length; index++) {
      canonical.add(parts[index].toLowerCase());
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

  /// All canonical subtags in order, including extensions and variants;
  /// unmodifiable.
  List<String> get subtags => _subtags;

  static bool _isScript(String part) =>
      part.length == 4 && _letters.hasMatch(part);

  static bool _isRegion(String part) =>
      (part.length == 2 && _letters.hasMatch(part)) ||
      (part.length == 3 && _digits.hasMatch(part));

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
