/// Developer-facing mirror of the synthetic HTML acceptance-matrix check in
/// design/specs/validate_specs.py.
///
/// Pure in-memory string logic: the caller supplies the matrix text and HTML
/// text. This library performs no file I/O and does not approve, reject or
/// modify the actual acceptance matrix or design document.
library;

const String _crossCuttingMarker = '## 横断する受入項目';

// Python's `str.isspace()` / regex `\s` membership, matching the canonical
// validator's `str.strip()`. Dart's ECMAScript `\s` differs in both directions.
bool _isWhitespace(int rune) =>
    (rune >= 0x09 && rune <= 0x0D) ||
    (rune >= 0x1C && rune <= 0x20) ||
    rune == 0x85 ||
    rune == 0xA0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    (rune >= 0x2028 && rune <= 0x2029) ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000;

bool _isLineBreak(int rune) =>
    (rune >= 0x0A && rune <= 0x0D) ||
    (rune >= 0x1C && rune <= 0x1E) ||
    rune == 0x85 ||
    rune == 0x2028 ||
    rune == 0x2029;

List<String> _splitLines(String text) {
  final lines = <String>[];
  final buffer = StringBuffer();
  final runes = text.runes.toList();
  var breaks = 0;
  for (var i = 0; i < runes.length; i++) {
    final rune = runes[i];
    if (_isLineBreak(rune)) {
      lines.add(buffer.toString());
      buffer.clear();
      breaks++;
      if (rune == 0x0D && i + 1 < runes.length && runes[i + 1] == 0x0A) i++;
      continue;
    }
    buffer.writeCharCode(rune);
  }
  if (buffer.isNotEmpty || breaks == 0) lines.add(buffer.toString());
  return lines;
}

String _stripWhitespace(String text) {
  final runes = text.runes.toList();
  var start = 0;
  var end = runes.length;
  while (start < end && _isWhitespace(runes[start])) {
    start++;
  }
  while (end > start && _isWhitespace(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

String _stripBars(String text) {
  final runes = text.runes.toList();
  var start = 0;
  var end = runes.length;
  while (start < end && runes[start] == 0x7C) {
    start++;
  }
  while (end > start && runes[end - 1] == 0x7C) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

// Decimal-digit ranges accepted by Python's `re.fullmatch(r"F\d{2}", ...)` in
// the validator's runtime. Dart's Unicode tables include newer Nd code points
// that this validator does not accept, so the ranges are pinned explicitly.
const List<List<int>> _pythonDigits = <List<int>>[
  [0x30, 0x39],
  [0x660, 0x669],
  [0x6f0, 0x6f9],
  [0x7c0, 0x7c9],
  [0x966, 0x96f],
  [0x9e6, 0x9ef],
  [0xa66, 0xa6f],
  [0xae6, 0xaef],
  [0xb66, 0xb6f],
  [0xbe6, 0xbef],
  [0xc66, 0xc6f],
  [0xce6, 0xcef],
  [0xd66, 0xd6f],
  [0xde6, 0xdef],
  [0xe50, 0xe59],
  [0xed0, 0xed9],
  [0xf20, 0xf29],
  [0x1040, 0x1049],
  [0x1090, 0x1099],
  [0x17e0, 0x17e9],
  [0x1810, 0x1819],
  [0x1946, 0x194f],
  [0x19d0, 0x19d9],
  [0x1a80, 0x1a89],
  [0x1a90, 0x1a99],
  [0x1b50, 0x1b59],
  [0x1bb0, 0x1bb9],
  [0x1c40, 0x1c49],
  [0x1c50, 0x1c59],
  [0xa620, 0xa629],
  [0xa8d0, 0xa8d9],
  [0xa900, 0xa909],
  [0xa9d0, 0xa9d9],
  [0xa9f0, 0xa9f9],
  [0xaa50, 0xaa59],
  [0xabf0, 0xabf9],
  [0xff10, 0xff19],
  [0x104a0, 0x104a9],
  [0x10d30, 0x10d39],
  [0x11066, 0x1106f],
  [0x110f0, 0x110f9],
  [0x11136, 0x1113f],
  [0x111d0, 0x111d9],
  [0x112f0, 0x112f9],
  [0x11450, 0x11459],
  [0x114d0, 0x114d9],
  [0x11650, 0x11659],
  [0x116c0, 0x116c9],
  [0x11730, 0x11739],
  [0x118e0, 0x118e9],
  [0x11950, 0x11959],
  [0x11c50, 0x11c59],
  [0x11d50, 0x11d59],
  [0x11da0, 0x11da9],
  [0x11f50, 0x11f59],
  [0x16a60, 0x16a69],
  [0x16ac0, 0x16ac9],
  [0x16b50, 0x16b59],
  [0x1d7ce, 0x1d7ff],
  [0x1e140, 0x1e149],
  [0x1e2f0, 0x1e2f9],
  [0x1e4f0, 0x1e4f9],
  [0x1e950, 0x1e959],
  [0x1fbf0, 0x1fbf9],
];

bool _isPythonDigit(int rune) {
  for (final range in _pythonDigits) {
    if (rune >= range[0] && rune <= range[1]) return true;
  }
  return false;
}

bool _isAcceptanceId(String cell) {
  final runes = cell.runes.toList();
  return runes.length == 3 &&
      runes[0] == 0x46 &&
      _isPythonDigit(runes[1]) &&
      _isPythonDigit(runes[2]);
}

/// Reports whether every canonical acceptance row's cells appear in [html].
/// Returns `false` when the cross-cutting section marker is absent.
bool htmlAcceptanceMirrorComplete(String acceptance, String html) {
  final markerIndex = acceptance.indexOf(_crossCuttingMarker);
  if (markerIndex < 0) return false;
  final crossSection = acceptance.substring(
    markerIndex + _crossCuttingMarker.length,
  );
  final crossLines = _splitLines(crossSection).toSet();

  for (final line in _splitLines(acceptance)) {
    if (!line.startsWith('| ')) continue;
    final cells = _stripBars(_stripWhitespace(line))
        .split('|')
        .map(_stripWhitespace)
        .toList();
    if (cells.isEmpty) continue;
    if (!_isAcceptanceId(cells[0]) && !crossLines.contains(line)) continue;
    if (cells[0] == '項目') continue;
    for (final cell in cells) {
      if (!html.contains(cell)) return false;
    }
  }
  return true;
}
