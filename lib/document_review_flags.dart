/// A local, explainable hint that source text may need manual checking.
///
/// These flags never rewrite text and make no claim about translation quality.
enum DocumentReviewFlag { number, link, placeholder }

// Decimal digits in every script, so localized numerals (full-width,
// Arabic-Indic, ...) are flagged for review just like ASCII 0-9.
final RegExp _numberPattern = RegExp(r'\p{Nd}', unicode: true);
// A review hint, not an email validator: internationalized local parts and
// domains are flagged just like ASCII ones, with no normalization or rewriting.
final RegExp _urlPattern = RegExp(
  r'https?://|www\.',
  unicode: true,
  caseSensitive: false,
);
// Single-rune classes for the linear email-hint scan (same characters as
// the old local-part and domain runs).
final RegExp _localRunePattern = RegExp(
  r"[\p{L}\p{M}\p{N}.!#$%&'*+/=?^_`{|}~-]",
  unicode: true,
);
final RegExp _domainRunePattern = RegExp(r'[\p{L}\p{M}\p{N}.-]', unicode: true);

bool _isLocalRune(int rune) =>
    _localRunePattern.hasMatch(String.fromCharCode(rune));

bool _isDomainRune(int rune) =>
    _domainRunePattern.hasMatch(String.fromCharCode(rune));

final RegExp _placeholderPattern = RegExp(
  r'\{[^{}]+\}|%[A-Za-z_][A-Za-z0-9_]*%',
);

/// Returns the categories present in [text], in stable display order.
Set<DocumentReviewFlag> detectDocumentReviewFlags(String text) {
  final flags = <DocumentReviewFlag>{};
  if (_numberPattern.hasMatch(text)) flags.add(DocumentReviewFlag.number);
  if (_urlPattern.hasMatch(text) || _hasEmailHint(text)) {
    flags.add(DocumentReviewFlag.link);
  }
  if (_placeholderPattern.hasMatch(text)) {
    flags.add(DocumentReviewFlag.placeholder);
  }
  return flags;
}

/// A review hint, not an address validator: one dot with text on both sides
/// is enough. Malformed dot atoms stay flagged.
// '@' is in neither char class, so forward domain scans from successive
// markers and backward local scans to preceding markers do not overlap;
// each rune is inspected a bounded number of times, giving O(n) total work.
bool _hasEmailHint(String text) {
  final runes = text.runes.toList();
  for (var i = 0; i < runes.length; i++) {
    if (runes[i] != 0x40) {
      continue;
    }
    var end = i + 1;
    while (end < runes.length && _isDomainRune(runes[end])) {
      end++;
    }
    var hasInnerDot = false;
    for (var dot = i + 2; dot < end - 1; dot++) {
      if (runes[dot] == 0x2E) {
        hasInnerDot = true;
        break;
      }
    }
    if (!hasInnerDot) {
      continue;
    }
    var start = i - 1;
    while (start >= 0 && _isLocalRune(runes[start])) {
      start--;
    }
    if (start < i - 1) {
      return true;
    }
  }
  return false;
}
