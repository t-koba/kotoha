/// Developer-facing mirror of the synthetic license-expression fixture check
/// in design/specs/validate_specs.py.
///
/// Pure in-memory string logic: identifiers, classifications and policy
/// categories are supplied by the caller. This library performs no file I/O,
/// network access, dependency resolution or license approval, and a result
/// here is not evidence about any real dependency's terms.
library;

/// Token kinds used by the bounded recursive-descent parser.
enum _NodeKind { license, conjunction, disjunction }

/// A parsed expression node.
class _Node {
  const _Node.term(this.term)
    : kind = _NodeKind.license,
      left = null,
      right = null;

  const _Node.binary(this.kind, this.left, this.right) : term = null;

  final _NodeKind kind;
  final String? term;
  final _Node? left;
  final _Node? right;
}

bool _isWhitespace(String character) =>
    RegExp(r'^\s$', unicode: true).hasMatch(character);

bool _isIdentifierCharacter(int unit) =>
    (unit >= 0x41 && unit <= 0x5A) ||
    (unit >= 0x61 && unit <= 0x7A) ||
    (unit >= 0x30 && unit <= 0x39) ||
    unit == 0x2E ||
    unit == 0x2B ||
    unit == 0x2D;

/// Tokenizes the bounded syntax `(`, `)`, identifiers and whitespace.
/// Returns `null` when any non-whitespace character is outside that syntax.
List<String>? _tokenize(String expression) {
  final tokens = <String>[];
  final buffer = StringBuffer();
  void flush() {
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
      buffer.clear();
    }
  }

  for (var i = 0; i < expression.length; i++) {
    final character = expression[i];
    if (_isWhitespace(character)) {
      flush();
      continue;
    }
    if (character == '(' || character == ')') {
      flush();
      tokens.add(character);
      continue;
    }
    if (_isIdentifierCharacter(expression.codeUnitAt(i))) {
      buffer.write(character);
      continue;
    }
    return null;
  }
  flush();

  final compacted = expression.replaceAll(RegExp(r'\s+', unicode: true), '');
  if (tokens.join() != compacted) return null;
  return tokens;
}

class _Parser {
  _Parser(this._tokens);

  final List<String> _tokens;
  int _position = 0;

  static const Set<String> _reserved = <String>{'AND', 'OR', 'WITH', ')'};

  _Node? atom() {
    if (_position >= _tokens.length) return null;
    final token = _tokens[_position++];
    if (token == '(') {
      final value = disjunction();
      if (value == null ||
          _position >= _tokens.length ||
          _tokens[_position] != ')') {
        return null;
      }
      _position++;
      return value;
    }
    if (_reserved.contains(token)) return null;
    if (_position < _tokens.length && _tokens[_position] == 'WITH') {
      _position++;
      if (_position >= _tokens.length ||
          _reserved.contains(_tokens[_position]) ||
          _tokens[_position] == '(') {
        return null;
      }
      final combined = '$token WITH ${_tokens[_position]}';
      _position++;
      return _Node.term(combined);
    }
    return _Node.term(token);
  }

  _Node? conjunction() {
    var value = atom();
    if (value == null) return null;
    while (_position < _tokens.length && _tokens[_position] == 'AND') {
      _position++;
      final right = atom();
      if (right == null) return null;
      value = _Node.binary(_NodeKind.conjunction, value, right);
    }
    return value;
  }

  _Node? disjunction() {
    var value = conjunction();
    if (value == null) return null;
    while (_position < _tokens.length && _tokens[_position] == 'OR') {
      _position++;
      final right = conjunction();
      if (right == null) return null;
      value = _Node.binary(_NodeKind.disjunction, value, right);
    }
    return value;
  }

  _Node? parse() {
    final value = disjunction();
    if (value == null || _position != _tokens.length) return null;
    return value;
  }
}

Set<String>? _evaluate(
  _Node? node,
  Map<String, String> classifications,
  Set<String> acceptable,
  Set<String> excluded,
) {
  if (node == null) return null;
  if (node.kind == _NodeKind.license) {
    final term = node.term!;
    final category = classifications[term];
    if (category == null ||
        !acceptable.contains(category) ||
        excluded.contains(category)) {
      return null;
    }
    return <String>{term};
  }
  final left = _evaluate(node.left, classifications, acceptable, excluded);
  final right = _evaluate(node.right, classifications, acceptable, excluded);
  if (node.kind == _NodeKind.conjunction) {
    if (left == null || right == null) return null;
    return <String>{...left, ...right};
  }
  return left ?? right;
}

/// Selects one complete acceptable OR branch, or returns `null` when the
/// expression is malformed or no complete branch satisfies caller policy.
Set<String>? selectedLicenseTerms(
  String expression,
  Map<String, String> classifications, {
  required Set<String> acceptableCategories,
  required Set<String> excludedCategories,
}) {
  final tokens = _tokenize(expression);
  if (tokens == null) return null;
  return _evaluate(
    _Parser(tokens).parse(),
    classifications,
    acceptableCategories,
    excludedCategories,
  );
}
