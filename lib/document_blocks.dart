/// A dependency-free, line-oriented block parse of flat source text.
///
/// Only the small Markdown subset needed for document outlines is recognized.
/// Blocks keep UTF-16 offsets into the original source so a caller can map an
/// outline entry back to the editor's text without rewriting that text.
library;

/// The kind of a top-level block in a flat text document.
enum DocumentBlockKind { heading, paragraph, listItem, codeBlock }

/// One top-level block of a flat text document.
///
/// [start] and [end] are UTF-16 code-unit offsets into the source passed to
/// [parseDocumentBlocks], with [end] exclusive. The range covers the block's
/// lines, never a line terminator after its last line and never a blank
/// separator line. [level] is 1..6 for headings and 0 for every other kind.
/// [text] is the label text with the marker or fences removed.
class DocumentBlock {
  const DocumentBlock({
    required this.kind,
    required this.start,
    required this.end,
    required this.level,
    required this.text,
  });

  final DocumentBlockKind kind;
  final int start;
  final int end;
  final int level;
  final String text;
}

/// Parses [source] into non-overlapping, source-ordered [DocumentBlock]s.
///
/// LF and CRLF are line terminators; a lone CR stays in the line's content.
/// Blank lines are skipped. A leading U+FEFF is ignored when recognizing any
/// marker but kept in the range. Headings start at the beginning of a line,
/// list items may be indented, and fenced code swallows any marker-looking
/// lines until its closing fence or the end of the input.
List<DocumentBlock> parseDocumentBlocks(String source) {
  final probe = source.startsWith('\uFEFF') ? source.substring(1) : source;
  if (probe.trim().isEmpty) return const <DocumentBlock>[];

  final lines = _splitLines(source);
  final blocks = <DocumentBlock>[];
  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (line.text.trim().isEmpty) {
      i++;
      continue;
    }

    final fence = _openFence(line.text);
    if (fence != null) {
      var close = -1;
      for (var j = i + 1; j < lines.length; j++) {
        if (_isClosingFence(lines[j].text, fence)) {
          close = j;
          break;
        }
      }
      final contentEndLine = close >= 0 ? close : lines.length;
      final rangeEndLine = close >= 0 ? close : lines.length - 1;
      final content = <String>[];
      for (var j = i + 1; j < contentEndLine; j++) {
        content.add(lines[j].text);
      }
      blocks.add(
        DocumentBlock(
          kind: DocumentBlockKind.codeBlock,
          start: line.start,
          end: lines[rangeEndLine].contentEnd,
          level: 0,
          text: content.join('\n'),
        ),
      );
      i = close >= 0 ? close + 1 : lines.length;
      continue;
    }

    final heading = _heading(line.text);
    if (heading != null) {
      blocks.add(
        DocumentBlock(
          kind: DocumentBlockKind.heading,
          start: line.start,
          end: line.contentEnd,
          level: heading.level,
          text: heading.text,
        ),
      );
      i++;
      continue;
    }

    final item = _listItem(line.text);
    if (item != null) {
      blocks.add(
        DocumentBlock(
          kind: DocumentBlockKind.listItem,
          start: line.start,
          end: line.contentEnd,
          level: 0,
          text: item,
        ),
      );
      i++;
      continue;
    }

    var j = i + 1;
    while (j < lines.length &&
        lines[j].text.trim().isNotEmpty &&
        _openFence(lines[j].text) == null &&
        _heading(lines[j].text) == null &&
        _listItem(lines[j].text) == null) {
      j++;
    }
    final content = <String>[];
    for (var k = i; k < j; k++) {
      content.add(lines[k].text);
    }
    blocks.add(
      DocumentBlock(
        kind: DocumentBlockKind.paragraph,
        start: line.start,
        end: lines[j - 1].contentEnd,
        level: 0,
        text: content.join('\n'),
      ),
    );
    i = j;
  }
  return blocks;
}

class _Line {
  const _Line(this.start, this.contentEnd, this.text);

  final int start;
  final int contentEnd;
  final String text;
}

List<_Line> _splitLines(String source) {
  final lines = <_Line>[];
  var start = 0;
  var i = 0;
  while (i < source.length) {
    final unit = source.codeUnitAt(i);
    if (unit == 0x0A) {
      lines.add(_Line(start, i, source.substring(start, i)));
      i += 1;
      start = i;
    } else if (unit == 0x0D &&
        i + 1 < source.length &&
        source.codeUnitAt(i + 1) == 0x0A) {
      lines.add(_Line(start, i, source.substring(start, i)));
      i += 2;
      start = i;
    } else {
      i++;
    }
  }
  if (start < source.length) {
    lines.add(_Line(start, source.length, source.substring(start)));
  }
  return lines;
}

/// Returns the index just past a leading U+FEFF, or zero. The BOM is an
/// encoding mark: it is ignored for marker recognition but stays in the
/// block's exact source range.
int _skipBom(String line) =>
    line.isNotEmpty && line.codeUnitAt(0) == 0xFEFF ? 1 : 0;

int _skipIndent(String line) {
  var i = _skipBom(line);
  while (i < line.length &&
      (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
    i++;
  }
  return i;
}

bool _isMarkerSpace(int unit) => unit == 0x20 || unit == 0x09;

class _Heading {
  const _Heading(this.level, this.text);

  final int level;
  final String text;
}

_Heading? _heading(String line) {
  var i = _skipBom(line);
  var hashes = 0;
  while (i < line.length && line.codeUnitAt(i) == 0x23) {
    hashes++;
    i++;
  }
  if (hashes < 1 || hashes > 6) return null;
  if (i >= line.length || !_isMarkerSpace(line.codeUnitAt(i))) return null;
  return _Heading(hashes, line.substring(i).trim());
}

String? _listItem(String line) {
  var i = _skipIndent(line);
  if (i >= line.length) return null;
  final unit = line.codeUnitAt(i);
  if (unit == 0x2D || unit == 0x2A || unit == 0x2B) {
    if (i + 1 >= line.length || !_isMarkerSpace(line.codeUnitAt(i + 1))) {
      return null;
    }
    return line.substring(i + 2).trim();
  }
  if (unit >= 0x30 && unit <= 0x39) {
    while (i < line.length &&
        line.codeUnitAt(i) >= 0x30 &&
        line.codeUnitAt(i) <= 0x39) {
      i++;
    }
    if (i >= line.length || line.codeUnitAt(i) != 0x2E) return null;
    if (i + 1 >= line.length || !_isMarkerSpace(line.codeUnitAt(i + 1))) {
      return null;
    }
    return line.substring(i + 2).trim();
  }
  return null;
}

class _Fence {
  const _Fence(this.unit, this.length);

  final int unit;
  final int length;
}

_Fence? _openFence(String line) {
  final i = _skipIndent(line);
  if (i >= line.length) return null;
  final unit = line.codeUnitAt(i);
  if (unit != 0x60 && unit != 0x7E) return null;
  var j = i;
  while (j < line.length && line.codeUnitAt(j) == unit) {
    j++;
  }
  if (j - i < 3) return null;
  return _Fence(unit, j - i);
}

/// A closer uses the opening character with at least its run length and no
/// trailing text; an opening info string is not mistaken for a closer.
bool _isClosingFence(String line, _Fence opening) {
  final i = _skipIndent(line);
  if (i >= line.length || line.codeUnitAt(i) != opening.unit) return false;
  var j = i;
  while (j < line.length && line.codeUnitAt(j) == opening.unit) {
    j++;
  }
  return j - i >= opening.length && line.substring(j).trim().isEmpty;
}
