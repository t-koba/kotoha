import 'package:flutter/widgets.dart' show Locale;

/// A conservative, fail-closed parse of a free-form language entry into the
/// [Locale] used only to tag the voice for that entry's content.
///
/// Language fields are user-editable strings, so an arbitrary name must never
/// be guessed into a locale. Only simple, well-formed BCP-47-like tags are
/// accepted: a two- or three-letter primary language subtag followed by at
/// most a script and a region. Anything else returns `null` and the content is
/// left voiced by the platform default, as before.
Locale? parseContentLocale(String entry) {
  final tag = entry.trim();
  if (tag.isEmpty) return null;

  final parts = tag.split('-');
  if (parts.isEmpty || parts.length > 3) return null;

  final language = parts.first.toLowerCase();
  if (!_asciiLetters.hasMatch(language) ||
      language.length < 2 ||
      language.length > 3) {
    return null;
  }

  String? script;
  String? region;
  for (final part in parts.skip(1)) {
    if (_script.hasMatch(part)) {
      // BCP-47 requires the script subtag before the region. A script after a
      // region is malformed; accepting it would let Locale.fromSubtags silently
      // reorder the entry into a valid-looking locale, so fail closed instead.
      if (script != null || region != null) return null;
      script = part[0].toUpperCase() + part.substring(1).toLowerCase();
    } else if (_regionLetters.hasMatch(part)) {
      if (region != null) return null;
      region = part.toUpperCase();
    } else if (_regionDigits.hasMatch(part)) {
      if (region != null) return null;
      region = part;
    } else {
      return null;
    }
  }

  return Locale.fromSubtags(
    languageCode: language,
    scriptCode: script,
    countryCode: region,
  );
}

final RegExp _asciiLetters = RegExp(r'^[A-Za-z]+$');
final RegExp _script = RegExp(r'^[A-Za-z]{4}$');
final RegExp _regionLetters = RegExp(r'^[A-Za-z]{2}$');
final RegExp _regionDigits = RegExp(r'^[0-9]{3}$');
