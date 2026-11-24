import 'dart:convert';

/// A translatable string value in a JSON source document.
///
/// [start] and [end] are UTF-16 offsets into the original source and cover
/// only the raw content between the value's double quotes ([end] exclusive).
/// Object keys are never segments; ids follow source order from zero.
class JsonStringSegment {
  const JsonStringSegment({
    required this.id,
    required this.path,
    required this.value,
    required this.start,
    required this.end,
  });

  final int id;
  final String path;
  final String value;
  final int start;
  final int end;
}

/// Source-ordered string values of a JSON document and a raw-range rewriter.
///
/// [values] is a frozen snapshot: every supplied segment is copied into a
/// plain [JsonStringSegment] once at construction.
class JsonStringSegments {
  JsonStringSegments(this.source, List<JsonStringSegment> values)
    : values = List<JsonStringSegment>.unmodifiable(
        values.map(
          (segment) => JsonStringSegment(
            id: segment.id,
            path: segment.path,
            value: segment.value,
            start: segment.start,
            end: segment.end,
          ),
        ),
      );

  final String source;

  /// Frozen, source-ordered copy of the segments supplied at construction.
  final List<JsonStringSegment> values;

  /// Replaces the raw inner content of each segment named by [translations].
  ///
  /// Every other code unit of [source] is preserved verbatim. Unknown ids and
  /// non-string translations are rejected; the rewritten text is validated
  /// with [jsonDecode] before it is returned.
  String apply(Map<int, String> translations) {
    if (translations.isEmpty) return source;

    final edits = <int, String>{};
    for (final entry in translations.entries) {
      final Object id = entry.key;
      final Object replacement = entry.value;
      if (id is! int || id < 0 || id >= values.length) {
        throw ArgumentError.value(id, 'translation id', 'unknown segment id');
      }
      if (replacement is! String) {
        throw ArgumentError.value(
          replacement,
          'translation',
          'must be a String',
        );
      }
      edits[id] = replacement;
    }

    final buffer = StringBuffer();
    var cursor = 0;
    for (final segment in values) {
      final replacement = edits[segment.id];
      if (replacement == null) continue;
      buffer.write(source.substring(cursor, segment.start));
      final encoded = jsonEncode(replacement);
      buffer.write(encoded.substring(1, encoded.length - 1));
      cursor = segment.end;
    }
    buffer.write(source.substring(cursor));

    final result = buffer.toString();
    try {
      jsonDecode(result);
    } on FormatException catch (error) {
      throw StateError('Rewriting produced invalid JSON: ${error.message}');
    }
    return result;
  }
}

/// Validates [source] as JSON, then locates its string values without
/// re-serializing any part of the document.
JsonStringSegments parseJsonStringSegments(String source) {
  jsonDecode(source);
  return JsonStringSegments(source, _JsonScanner(source).scan());
}

final RegExp _simpleKey = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

String _pathComponent(String key) =>
    _simpleKey.hasMatch(key) ? '.$key' : '[${jsonEncode(key)}]';

enum _FrameKind { object, array }

class _Frame {
  _Frame.object() : kind = _FrameKind.object, index = 0;
  _Frame.array() : kind = _FrameKind.array, index = 0;

  final _FrameKind kind;
  int index;
}

/// Iterative traversal over already-validated JSON, tracking raw offsets.
///
/// Containers live on an explicit stack so deeply nested but bounded documents
/// cannot exhaust the Dart call stack. Each path is assembled only when a
/// string value is emitted.
class _JsonScanner {
  _JsonScanner(this.source);

  final String source;
  final List<JsonStringSegment> _segments = <JsonStringSegment>[];
  final List<_Frame> _stack = <_Frame>[];
  final List<String> _path = <String>[];
  int _at = 0;

  List<JsonStringSegment> scan() {
    var expectingValue = true;
    while (true) {
      if (expectingValue) {
        _space();
        if (_at >= source.length) throw _bad('expected value');
        final unit = source.codeUnitAt(_at);
        if (unit == 0x22) {
          _emitString();
          expectingValue = false;
        } else if (unit == 0x7B) {
          _at++;
          _space();
          if (_take(0x7D)) {
            expectingValue = false;
          } else {
            final frame = _Frame.object();
            _stack.add(frame);
            _readObjectKey(frame);
          }
        } else if (unit == 0x5B) {
          _at++;
          _space();
          if (_take(0x5D)) {
            expectingValue = false;
          } else {
            _stack.add(_Frame.array());
            _path.add('[0]');
          }
        } else if (_literal('true') || _literal('false') || _literal('null')) {
          expectingValue = false;
        } else {
          _number();
          expectingValue = false;
        }
        continue;
      }

      if (_stack.isEmpty) break;
      final frame = _stack.last;
      _space();
      if (_take(0x2C)) {
        _path.removeLast();
        if (frame.kind == _FrameKind.object) {
          _readObjectKey(frame);
        } else {
          frame.index++;
          _path.add('[${frame.index}]');
        }
        expectingValue = true;
        continue;
      }
      final closing = frame.kind == _FrameKind.object ? 0x7D : 0x5D;
      if (_take(closing)) {
        _stack.removeLast();
        _path.removeLast();
        continue;
      }
      throw _bad(
        frame.kind == _FrameKind.object
            ? 'expected comma or closing brace'
            : 'expected comma or closing bracket',
      );
    }

    _space();
    if (_at != source.length) throw _bad('trailing content');
    return _segments;
  }

  FormatException _bad(String reason) =>
      FormatException('$reason at offset $_at', source, _at);

  bool _take(int codeUnit) {
    if (_at >= source.length || source.codeUnitAt(_at) != codeUnit) {
      return false;
    }
    _at++;
    return true;
  }

  void _space() {
    while (_at < source.length) {
      final unit = source.codeUnitAt(_at);
      if (unit != 0x20 && unit != 0x09 && unit != 0x0A && unit != 0x0D) break;
      _at++;
    }
  }

  bool _literal(String word) {
    if (!source.startsWith(word, _at)) return false;
    _at += word.length;
    return true;
  }

  void _number() {
    final start = _at;
    while (_at < source.length) {
      final unit = source.codeUnitAt(_at);
      final digit = unit >= 0x30 && unit <= 0x39;
      if (!digit &&
          unit != 0x2D &&
          unit != 0x2B &&
          unit != 0x2E &&
          unit != 0x65 &&
          unit != 0x45) {
        break;
      }
      _at++;
    }
    if (_at == start) throw _bad('expected value');
  }

  /// Returns the raw inner offsets of the quoted string at the cursor.
  (int, int) _quoted() {
    if (!_take(0x22)) throw _bad('expected string');
    final start = _at;
    while (_at < source.length) {
      final unit = source.codeUnitAt(_at);
      if (unit == 0x5C) {
        _at += 2;
      } else if (unit == 0x22) {
        final end = _at;
        _at++;
        return (start, end);
      } else {
        _at++;
      }
    }
    throw _bad('unterminated string');
  }

  String _decoded(int start, int end) =>
      jsonDecode(source.substring(start - 1, end + 1)) as String;

  void _readObjectKey(_Frame frame) {
    _space();
    final (keyStart, keyEnd) = _quoted();
    final key = _decoded(keyStart, keyEnd);
    _space();
    if (!_take(0x3A)) throw _bad('expected colon');
    _path.add(_pathComponent(key));
  }

  void _emitString() {
    final (start, end) = _quoted();
    _segments.add(
      JsonStringSegment(
        id: _segments.length,
        path: '\$${_path.join()}',
        value: _decoded(start, end),
        start: start,
        end: end,
      ),
    );
  }
}
