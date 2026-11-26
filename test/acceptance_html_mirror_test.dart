import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/acceptance_html_mirror.dart';

const String _marker = '## 横断する受入項目';

const String _baseAcceptance =
    '''
| 項目 | 判定 |
| --- | --- |
| F01 | 翻訳 |
| F02 | 保存 |

$_marker
| 共通 | 机で確認 |
''';

const String _baseHtml =
    '<p>F01</p><p>翻訳</p><p>F02</p><p>保存</p><p>共通</p><p>机で確認</p>';

void main() {
  group('htmlAcceptanceMirrorComplete', () {
    test('passes when every checked cell is present in HTML', () {
      expect(htmlAcceptanceMirrorComplete(_baseAcceptance, _baseHtml), isTrue);
    });

    test('rejects a missing mirrored cell', () {
      expect(
        htmlAcceptanceMirrorComplete(
          _baseAcceptance,
          '<p>F01</p><p>翻訳</p><p>F02</p>',
        ),
        isFalse,
      );
    });

    test('rejects a missing cross-cutting cell with all F rows mirrored', () {
      expect(
        htmlAcceptanceMirrorComplete(
          _baseAcceptance,
          '<p>F01</p><p>翻訳</p><p>F02</p><p>保存</p><p>共通</p>',
        ),
        isFalse,
      );
    });

    test('skips a header row inside the cross-cutting section', () {
      const acceptance = '| F01 | 翻訳 |\n$_marker\n| 項目 | 判定 |\n';
      expect(
        htmlAcceptanceMirrorComplete(acceptance, '<p>F01</p><p>翻訳</p>'),
        isTrue,
      );
    });

    test('fails closed when the cross-cutting marker is absent', () {
      expect(
        htmlAcceptanceMirrorComplete(
          _baseAcceptance.replaceFirst(_marker, '## other'),
          _baseHtml,
        ),
        isFalse,
      );
    });

    test('reproduces Python line breaks and whitespace stripping', () {
      const acceptance = '| F01 | 翻訳 |\r\n$_marker\u2028| 共通 | 机で確認 |\u001c';
      expect(htmlAcceptanceMirrorComplete(acceptance, _baseHtml), isTrue);

      const padded = '\u00A0| F01 | 翻訳 |\u001c\n$_marker\n';
      expect(htmlAcceptanceMirrorComplete(padded, _baseHtml), isTrue);
    });

    test('uses the validator digit set, not newer Dart Nd code points', () {
      const newDigitRow = '| F\u{10D40}\u{10D41} | 未 Mirror |\n$_marker\n';
      expect(htmlAcceptanceMirrorComplete(newDigitRow, ''), isTrue);
    });
  });
}
