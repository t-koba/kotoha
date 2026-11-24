import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/json_translation_segments.dart';

void main() {
  test('nested object and array paths use source-order ids', () {
    final source =
        '{"title":"Hello","items":[{"title":"First","tags":["one","two"]},"loose"],"note":null}';
    final parts = parseJsonStringSegments(source);

    expect(parts.source, source);
    expect(parts.values.map((s) => s.path).toList(), <String>[
      r'$.title',
      r'$.items[0].title',
      r'$.items[0].tags[0]',
      r'$.items[0].tags[1]',
      r'$.items[1]',
    ]);
    expect(parts.values.map((s) => s.value).toList(), <String>[
      'Hello',
      'First',
      'one',
      'two',
      'loose',
    ]);
    expect(parts.values.map((s) => s.id).toList(), <int>[0, 1, 2, 3, 4]);
    for (final segment in parts.values) {
      expect(source.substring(segment.start, segment.end), segment.value);
      expect(source.codeUnitAt(segment.start - 1), 0x22);
      expect(source.codeUnitAt(segment.end), 0x22);
    }
  });

  test('keys, numbers, booleans and null are not segments', () {
    final source = '{ "count": 12, "ok": true, "none": null, "text": "yes" }';
    final parts = parseJsonStringSegments(source);
    expect(parts.values, hasLength(1));
    expect(parts.values.single.path, r'$.text');
    expect(parts.values.single.value, 'yes');

    final result = parts.apply({0: 'no'});
    expect(result, '{ "count": 12, "ok": true, "none": null, "text": "no" }');
    final decoded = jsonDecode(result) as Map<String, dynamic>;
    expect(decoded['count'], 12);
    expect(decoded['ok'], isTrue);
    expect(decoded['none'], isNull);
  });

  test('whitespace, CRLF and raw escapes of untranslated values are kept', () {
    final source =
        '{\r\n  "keep" : "\\u00E9 \\/ ok",\r\n  "target" :  "before"\r\n}\r\n';
    final parts = parseJsonStringSegments(source);
    expect(parts.values.map((s) => s.value).toList(), <String>[
      'é / ok',
      'before',
    ]);

    final result = parts.apply({1: 'after'});
    expect(
      result,
      '{\r\n  "keep" : "\\u00E9 \\/ ok",\r\n  "target" :  "after"\r\n}\r\n',
    );
    expect((jsonDecode(result) as Map<String, dynamic>)['keep'], 'é / ok');
  });

  test(
    'translations with quotes, backslashes, controls and emoji are escaped',
    () {
      final source = '{"a":"x","b":"y"}';
      final parts = parseJsonStringSegments(source);
      const translation = 'say "hi" \\ path\nnext\ttab \u{1F600} é';
      final encoded = jsonEncode(translation);
      final inner = encoded.substring(1, encoded.length - 1);

      final result = parts.apply({1: translation});
      expect(result, '{"a":"x","b":$encoded}');
      expect(result, contains(r'\"hi\"'));
      expect(result, contains(r'\\'));
      expect(result, contains(r'\n'));
      expect(result, contains(r'\t'));
      expect((jsonDecode(result) as Map<String, dynamic>)['b'], translation);

      final reparsed = parseJsonStringSegments(result);
      expect(reparsed.values[0].start, parts.values[0].start);
      expect(reparsed.values[1].start, parts.values[1].start);
      expect(
        reparsed.values[1].end,
        parts.values[1].end + inner.length - parts.values[1].value.length,
      );
      expect(reparsed.values[1].value, translation);
    },
  );

  test('empty string values can be read and translated', () {
    final source = '{"empty":"","after":"z"}';
    final parts = parseJsonStringSegments(source);
    expect(parts.values.first.value, '');
    expect(parts.values.first.start, parts.values.first.end);
    expect(parts.apply({0: 'filled'}), '{"empty":"filled","after":"z"}');

    final root = parseJsonStringSegments('""');
    expect(root.values.single.path, r'$');
    expect(root.values.single.value, '');
    expect(root.values.single.start, 1);
    expect(root.values.single.end, 1);
    expect(root.apply({0: 'x'}), '"x"');
  });

  test('duplicate keys get distinct ids even when paths collide', () {
    final source = '{"k":"a","k":"b","g":[{"k":"c"},{"k":"d"}]}';
    final parts = parseJsonStringSegments(source);
    expect(parts.values.map((s) => s.id).toList(), <int>[0, 1, 2, 3]);
    expect(parts.values.map((s) => s.path).toList(), <String>[
      r'$.k',
      r'$.k',
      r'$.g[0].k',
      r'$.g[1].k',
    ]);
    expect(
      parts.apply({0: 'A', 3: 'D'}),
      '{"k":"A","k":"b","g":[{"k":"c"},{"k":"D"}]}',
    );
  });

  test('UTF-16 offsets account for surrogate pairs in earlier text', () {
    final source = '{"\u{1F600}":"ok","tail":"é"}';
    final parts = parseJsonStringSegments(source);
    expect(parts.values.map((s) => s.path).toList(), <String>[
      '\$["\u{1F600}"]',
      r'$.tail',
    ]);
    expect(parts.values[0].start, source.indexOf('ok'));
    expect(parts.values[1].start, source.indexOf('é'));
    expect(parts.apply({0: 'hi'}), '{"\u{1F600}":"hi","tail":"é"}');
  });

  test('invalid JSON throws FormatException', () {
    for (final source in <String>[
      '',
      '{',
      '{"a":}',
      '[1,]',
      '{"a":1} trailing',
      r'{"a":"\q"}',
    ]) {
      expect(
        () => parseJsonStringSegments(source),
        throwsA(isA<FormatException>()),
        reason: source,
      );
    }
  });

  test('unknown ids and non-string translations are rejected', () {
    final parts = parseJsonStringSegments('{"a":"x"}');
    expect(() => parts.apply({1: 'y'}), throwsA(isA<ArgumentError>()));
    expect(() => parts.apply({-1: 'y'}), throwsA(isA<ArgumentError>()));
    // Dart rejects a wrongly typed map at the call boundary; either way it
    // never applies a non-string value.
    final dynamic badValue = <int, Object>{0: 7};
    expect(() => parts.apply(badValue), throwsA(anything));
    final dynamic badKey = <Object, String>{'0': 'y'};
    expect(() => parts.apply(badKey), throwsA(anything));
  });

  test(
    'empty translation map returns the identical source and values are fixed',
    () {
      final source = '  [ "a" , "b" ]  ';
      final parts = parseJsonStringSegments(source);
      expect(parts.apply(const <int, String>{}), same(source));
      expect(parts.values, hasLength(2));
      expect(
        () => parts.values.add(parts.values.first),
        throwsA(isA<UnsupportedError>()),
      );
    },
  );
  test('constructor freezes supplied segments into plain snapshots', () {
    const source = '{"a":"b"}';
    final supplied = _MutableSegment(
      id: 0,
      path: r'$.a',
      value: 'b',
      start: 6,
      end: 7,
    );
    final parts = JsonStringSegments(source, <JsonStringSegment>[supplied]);

    void expectFrozenSnapshot() {
      final segment = parts.values.single;
      expect(segment.runtimeType, same(JsonStringSegment));
      expect(segment.id, 0);
      expect(segment.path, r'$.a');
      expect(segment.value, 'b');
      expect(segment.start, 6);
      expect(segment.end, 7);
      expect(parts.apply(const <int, String>{0: 'X'}), '{"a":"X"}');
    }

    expectFrozenSnapshot();
    supplied.mutate(
      id: 1,
      path: r'$.other',
      value: 'changed',
      start: 0,
      end: 1,
    );
    expect(supplied.id, 1);
    expect(supplied.value, 'changed');
    expectFrozenSnapshot();
  });

  test(
    'deeply nested JSON within panel limits does not overflow the scanner',
    () {
      const depth = 10000;
      final source = '${'[' * depth}"deep"${']' * depth}';
      final parts = parseJsonStringSegments(source);

      expect(parts.source, source);
      expect(parts.values, hasLength(1));
      expect(parts.values.single.value, 'deep');
      expect(parts.values.single.path, r'$' + '[0]' * depth);
      final rewritten = parts.apply({0: 'changed'});
      expect(jsonDecode(rewritten), isNotNull);
      expect(rewritten, '${'[' * depth}"changed"${']' * depth}');
    },
  );

  test('invalid JSON rejection never echoes the rejected document', () {
    const secret = 'private-draft-secret';
    String? rendered;
    try {
      parseJsonStringSegments('{"note":"$secret",}');
    } on FormatException catch (error) {
      rendered = error.toString();
    }

    expect(rendered, contains('Invalid JSON source.'));
    expect(rendered, isNot(contains(secret)));
  });

  test('unknown segment id rejection never echoes the caller value', () {
    final parts = parseJsonStringSegments('{"a":"x"}');

    String? rendered;
    try {
      parts.apply(const {42: 'y'});
    } on ArgumentError catch (error) {
      rendered = error.toString();
    }

    expect(rendered, contains('unknown segment id'));
    expect(rendered, contains('<rejected>'));
    expect(rendered, isNot(contains('42')));
  });
}

class _MutableSegment extends JsonStringSegment {
  _MutableSegment({
    required super.id,
    required super.path,
    required super.value,
    required super.start,
    required super.end,
  }) : _id = id,
       _path = path,
       _value = value,
       _start = start,
       _end = end;

  int _id;
  String _path;
  String _value;
  int _start;
  int _end;

  @override
  int get id => _id;

  @override
  String get path => _path;

  @override
  String get value => _value;

  @override
  int get start => _start;

  @override
  int get end => _end;

  void mutate({
    required int id,
    required String path,
    required String value,
    required int start,
    required int end,
  }) {
    _id = id;
    _path = path;
    _value = value;
    _start = start;
    _end = end;
  }
}
