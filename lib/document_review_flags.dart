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
final RegExp _emailPattern = RegExp(
  // The local part accepts the RFC 5322 atom punctuation, not just the
  // commonly typed subset, so a valid address is never silently unflagged.
  r"[\p{L}\p{M}\p{N}.!#$%&'*+/=?^_`{|}~-]+@[\p{L}\p{M}\p{N}.-]+"
  r'(?:\.[\p{L}\p{M}\p{N}.-]+)+',
  unicode: true,
  caseSensitive: false,
);
final RegExp _placeholderPattern = RegExp(
  r'\{[^{}]+\}|%[A-Za-z_][A-Za-z0-9_]*%',
);

/// Returns the categories present in [text], in stable display order.
Set<DocumentReviewFlag> detectDocumentReviewFlags(String text) {
  final flags = <DocumentReviewFlag>{};
  if (_numberPattern.hasMatch(text)) flags.add(DocumentReviewFlag.number);
  // The email branch backtracks over its whole candidate span when no address
  // can match, so skip it unless an '@' precedes a dot, its minimum shape.
  final at = text.indexOf('@');
  final dot = text.lastIndexOf('.');
  if (_urlPattern.hasMatch(text) ||
      (at >= 0 && dot > at && _emailPattern.hasMatch(text))) {
    flags.add(DocumentReviewFlag.link);
  }
  if (_placeholderPattern.hasMatch(text)) {
    flags.add(DocumentReviewFlag.placeholder);
  }
  return flags;
}
