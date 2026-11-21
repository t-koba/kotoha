/// A local, explainable hint that source text may need manual checking.
///
/// These flags never rewrite text and make no claim about translation quality.
enum DocumentReviewFlag { number, link, placeholder }

// Decimal digits in every script, so localized numerals (full-width,
// Arabic-Indic, ...) are flagged for review just like ASCII 0-9.
final RegExp _numberPattern = RegExp(r'\p{Nd}', unicode: true);
// A review hint, not an email validator: internationalized local parts and
// domains are flagged just like ASCII ones, with no normalization or rewriting.
final RegExp _linkPattern = RegExp(
  r'https?://|www\.|['
  r'\p{L}\p{M}\p{N}._%+-]+@[\p{L}\p{M}\p{N}-]+'
  r'(?:\.[\p{L}\p{M}\p{N}-]+)+',
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
  if (_linkPattern.hasMatch(text)) flags.add(DocumentReviewFlag.link);
  if (_placeholderPattern.hasMatch(text)) {
    flags.add(DocumentReviewFlag.placeholder);
  }
  return flags;
}
