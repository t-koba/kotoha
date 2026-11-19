import './workspace.dart';

/// Header of the reversible plain-text workspace format.
const String workspaceExportHeader = 'Kotoha workspace export v2';

// Every field is escaped onto one line, so no field can mimic a structural
// line. This is what makes the format reversible: unlike v1, a verbatim text
// body cannot split into extra fields when parsed.
String _escape(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll('\r', '\\r')
    .replaceAll('\n', '\\n');

String _unescape(String value) {
  final buffer = StringBuffer();
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    if (character != '\\') {
      buffer.write(character);
      continue;
    }
    if (index + 1 >= value.length) {
      throw const FormatException('Incomplete escape in workspace export.');
    }
    final escaped = value[++index];
    switch (escaped) {
      case '\\':
        buffer.write('\\');
      case 'r':
        buffer.write('\r');
      case 'n':
        buffer.write('\n');
      default:
        throw const FormatException('Unknown escape in workspace export.');
    }
  }
  return buffer.toString();
}

String _field(String line, String prefix) {
  if (!line.startsWith(prefix)) {
    throw const FormatException('Unexpected field in workspace export.');
  }
  return _unescape(line.substring(prefix.length));
}

/// Renders the whole in-memory workspace as one portable, reversible document.
String formatWorkspaceExport(TextWorkspaceDraft draft) {
  final lines = <String>[
    workspaceExportHeader,
    'Source language: ${_escape(draft.sourceLanguage)}',
    'Source text: ${_escape(draft.sourceText)}',
  ];
  for (var index = 0; index < draft.translations.length; index++) {
    lines
      ..add(
        'Translation ${index + 1} language: '
        '${_escape(draft.translations[index].targetLanguage)}',
      )
      ..add('Translation text: ${_escape(draft.translations[index].text)}');
  }
  return '${lines.join('\n')}\n';
}

/// Parses a document produced by [formatWorkspaceExport].
///
/// Rejects any other version, shape or escape with a [FormatException] rather
/// than guessing field boundaries.
TextWorkspaceDraft parseWorkspaceExport(String text) {
  // Field content always escapes CR/LF, so raw CRLF can only be a structural
  // line ending (for example, a Windows text editor re-saving the export).
  // Normalize that transport artifact; a remaining raw CR is malformed.
  text = text.replaceAll('\r\n', '\n');
  if (text.contains('\r')) {
    throw const FormatException(
      'Unexpected carriage return in workspace export.',
    );
  }
  if (!text.endsWith('\n')) {
    throw const FormatException('Workspace export must end with a newline.');
  }
  final lines = text.substring(0, text.length - 1).split('\n');
  if (lines.isEmpty || lines.first != workspaceExportHeader) {
    throw const FormatException('Unsupported workspace export version.');
  }
  final pairs = lines.length - 3;
  if (pairs < 2 || pairs.isOdd) {
    throw const FormatException('Incomplete workspace export.');
  }

  final translations = <ManualTranslationDraft>[];
  for (var index = 0; index < pairs ~/ 2; index++) {
    translations.add(
      ManualTranslationDraft(
        targetLanguage: _field(
          lines[3 + 2 * index],
          'Translation ${index + 1} language: ',
        ),
        text: _field(lines[4 + 2 * index], 'Translation text: '),
      ),
    );
  }
  return TextWorkspaceDraft(
    sourceLanguage: _field(lines[1], 'Source language: '),
    sourceText: _field(lines[2], 'Source text: '),
    translations: translations,
  );
}
