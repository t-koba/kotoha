import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/document_blocks.dart';

void main() {
  test('empty and whitespace-only input yields no blocks', () {
    for (final source in <String>[
      '',
      '   ',
      '\n\t\n',
      '\r\n \r\n',
      '\uFEFF\n',
    ]) {
      expect(parseDocumentBlocks(source), isEmpty, reason: source);
    }
  });

  test('ATX headings recognize 1..6 hashes followed by space or tab', () {
    for (var level = 1; level <= 6; level++) {
      final source = '${'#' * level}   Title $level  ';
      final blocks = parseDocumentBlocks(source);
      expect(blocks, hasLength(1), reason: source);
      expect(blocks.single.kind, DocumentBlockKind.heading);
      expect(blocks.single.level, level);
      expect(blocks.single.text, 'Title $level');
      expect(blocks.single.start, 0);
      expect(blocks.single.end, source.length);
      expect(source.substring(blocks.single.start, blocks.single.end), source);
    }

    final tabbed = parseDocumentBlocks('##\tTabbed');
    expect(tabbed, hasLength(1));
    expect(tabbed.single.kind, DocumentBlockKind.heading);
    expect(tabbed.single.text, 'Tabbed');
  });

  test('invalid heading markers stay paragraph text', () {
    for (final source in <String>[
      '#Title',
      '####### Seven',
      '#',
      '##NoSpace',
      '#\u00A0Nbsp',
      '  # Indented',
    ]) {
      final blocks = parseDocumentBlocks(source);
      expect(blocks, hasLength(1), reason: source);
      expect(blocks.single.kind, DocumentBlockKind.paragraph, reason: source);
      expect(blocks.single.level, 0, reason: source);
      expect(blocks.single.text, source, reason: source);
    }
  });

  test('paragraphs span consecutive lines and stop at blanks or markers', () {
    final source = 'First line\nsecond line\n\nThird\n- item\nlast line';
    final blocks = parseDocumentBlocks(source);
    expect(blocks.map((b) => b.kind).toList(), <DocumentBlockKind>[
      DocumentBlockKind.paragraph,
      DocumentBlockKind.paragraph,
      DocumentBlockKind.listItem,
      DocumentBlockKind.paragraph,
    ]);
    expect(blocks[0].start, 0);
    expect(blocks[0].end, source.indexOf('\n\n'));
    expect(blocks[0].text, 'First line\nsecond line');
    expect(blocks[1].text, 'Third');
    expect(blocks[2].text, 'item');
    expect(blocks[3].text, 'last line');
    expect(blocks[3].end, source.length);
  });

  test('a lone CR is ordinary text, not a line break', () {
    final blocks = parseDocumentBlocks('a\rb\nc');
    expect(blocks, hasLength(1));
    expect(blocks.single.kind, DocumentBlockKind.paragraph);
    expect(blocks.single.text, 'a\rb\nc');
    expect(blocks.single.start, 0);
    expect(blocks.single.end, 5);
  });

  test('list items accept indentation and unordered or ordered markers', () {
    final source = '- alpha\n  * beta\n\t+ gamma\n12. delta\n1.item\n-again';
    final blocks = parseDocumentBlocks(source);
    expect(blocks, hasLength(5));
    expect(
      blocks.take(4).map((b) => b.kind).toList(),
      List<DocumentBlockKind>.filled(4, DocumentBlockKind.listItem),
    );
    expect(blocks.take(4).map((b) => b.text).toList(), <String>[
      'alpha',
      'beta',
      'gamma',
      'delta',
    ]);
    expect(blocks.take(4).every((b) => b.level == 0), isTrue);
    expect(blocks.last.kind, DocumentBlockKind.paragraph);
    expect(blocks.last.text, '1.item\n-again');

    final tabMarker = parseDocumentBlocks('-\tTabbed');
    expect(tabMarker.single.kind, DocumentBlockKind.listItem);
    expect(tabMarker.single.text, 'Tabbed');
    expect(tabMarker.single.end, 8);
  });

  test('fenced code keeps CRLF content normalized and excludes its fences', () {
    final source = '```dart\r\nline 1\r\nline 2\r\n```\r\nAfter';
    final blocks = parseDocumentBlocks(source);
    expect(blocks, hasLength(2));
    expect(blocks[0].kind, DocumentBlockKind.codeBlock);
    expect(blocks[0].start, 0);
    expect(blocks[0].end, source.indexOf('\r\nAfter'));
    expect(
      source.substring(blocks[0].start, blocks[0].end),
      '```dart\r\nline 1\r\nline 2\r\n```',
    );
    expect(blocks[0].text, 'line 1\nline 2');
    expect(blocks[0].level, 0);
    expect(blocks[1].kind, DocumentBlockKind.paragraph);
    expect(blocks[1].text, 'After');
  });

  test('unclosed fence consumes marker-looking lines through end of input', () {
    final source = '```\n# not a heading\n- not an item\n';
    final blocks = parseDocumentBlocks(source);
    expect(blocks, hasLength(1));
    expect(blocks.single.kind, DocumentBlockKind.codeBlock);
    expect(blocks.single.start, 0);
    expect(blocks.single.end, source.length - 1);
    expect(
      source.substring(blocks.single.start, blocks.single.end),
      '```\n# not a heading\n- not an item',
    );
    expect(blocks.single.text, '# not a heading\n- not an item');
  });

  test(
    'closed fence accepts a longer fence and ignores marker lines inside',
    () {
      final source = '~~~\n# Heading\n- item\n~~~\nTail';
      final blocks = parseDocumentBlocks(source);
      expect(blocks, hasLength(2));
      expect(blocks[0].kind, DocumentBlockKind.codeBlock);
      expect(blocks[0].text, '# Heading\n- item');
      expect(blocks[1].kind, DocumentBlockKind.paragraph);
      expect(blocks[1].text, 'Tail');

      final longerSource = '~~~~\ncode\n~~~~~\n';
      final longerCloser = parseDocumentBlocks(longerSource);
      expect(longerCloser, hasLength(1));
      expect(longerCloser.single.text, 'code');
      expect(
        longerSource.substring(0, longerCloser.single.end),
        '~~~~\ncode\n~~~~~',
      );
    },
  );

  test('an opening info string is not mistaken for a closing fence', () {
    final blocks = parseDocumentBlocks('```dart\nlet x = 1;\n```js\n```\n');
    expect(blocks, hasLength(1));
    expect(blocks.single.kind, DocumentBlockKind.codeBlock);
    expect(blocks.single.text, 'let x = 1;\n```js');
  });

  test(
    'a leading BOM is ignored for heading recognition, kept in the range',
    () {
      final source = '\uFEFF##  Bombed  \nNext';
      final blocks = parseDocumentBlocks(source);
      expect(blocks, hasLength(2));
      expect(blocks[0].kind, DocumentBlockKind.heading);
      expect(blocks[0].level, 2);
      expect(blocks[0].text, 'Bombed');
      expect(blocks[0].start, 0);
      expect(
        source.substring(blocks[0].start, blocks[0].end),
        '\uFEFF##  Bombed  ',
      );
      expect(blocks[1].text, 'Next');
    },
  );

  test('a leading BOM is ignored for fence, list and heading markers', () {
    final source = '\uFEFF```\ncode\n```\n\uFEFF- one\n\uFEFF## Title';
    final blocks = parseDocumentBlocks(source);
    expect(blocks.map((block) => block.kind).toList(), [
      DocumentBlockKind.codeBlock,
      DocumentBlockKind.listItem,
      DocumentBlockKind.heading,
    ]);
    expect(blocks[0].text, 'code');
    expect(
      source.substring(blocks[0].start, blocks[0].end),
      '\uFEFF```\ncode\n```',
    );
    expect(blocks[1].text, 'one');
    expect(source.substring(blocks[1].start, blocks[1].end), '\uFEFF- one');
    expect(blocks[2].text, 'Title');
    expect(source.substring(blocks[2].start, blocks[2].end), '\uFEFF## Title');

    final indented = parseDocumentBlocks('\uFEFF  ```\ncode\n  ```');
    expect(indented.single.kind, DocumentBlockKind.codeBlock);
    expect(indented.single.text, 'code');
  });

  test('mixed document ranges reconstruct exactly and never overlap', () {
    final source = <String>[
      '# Title',
      'Intro one',
      'Intro two',
      '',
      '- first',
      '  * second',
      '12. third',
      '',
      '```dart',
      '# not a heading',
      'const x = 1;',
      '```',
      '',
      '## End',
    ].join('\r\n');
    final slices = <String>[
      '# Title',
      'Intro one\r\nIntro two',
      '- first',
      '  * second',
      '12. third',
      '```dart\r\n# not a heading\r\nconst x = 1;\r\n```',
      '## End',
    ];
    final labels = <String>[
      'Title',
      'Intro one\nIntro two',
      'first',
      'second',
      'third',
      '# not a heading\nconst x = 1;',
      'End',
    ];
    final kinds = <DocumentBlockKind>[
      DocumentBlockKind.heading,
      DocumentBlockKind.paragraph,
      DocumentBlockKind.listItem,
      DocumentBlockKind.listItem,
      DocumentBlockKind.listItem,
      DocumentBlockKind.codeBlock,
      DocumentBlockKind.heading,
    ];

    final blocks = parseDocumentBlocks(source);
    expect(blocks, hasLength(slices.length));
    var previousEnd = 0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      expect(block.kind, kinds[i], reason: 'block $i');
      expect(block.text, labels[i], reason: 'block $i');
      expect(
        block.start,
        greaterThanOrEqualTo(previousEnd),
        reason: 'block $i',
      );
      expect(block.end, greaterThan(block.start), reason: 'block $i');
      expect(block.end, lessThanOrEqualTo(source.length), reason: 'block $i');
      expect(
        source.substring(block.start, block.end),
        slices[i],
        reason: 'block $i',
      );
      expect(
        block.start == 0 || source.codeUnitAt(block.start - 1) == 0x0A,
        isTrue,
        reason: 'block $i starts at a line start',
      );
      previousEnd = block.end;
    }
  });
}
