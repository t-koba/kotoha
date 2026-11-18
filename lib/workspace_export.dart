import './workspace.dart';

/// Renders the whole in-memory workspace as one portable plain-text export.
///
/// Language labels are escaped so each stays on a single line. Text bodies are
/// copied verbatim, including Unicode, bidi marks and line breaks.
String formatWorkspaceExport(TextWorkspaceDraft draft) {
  String escapeLanguage(String language) => language
      .replaceAll('\\', '\\\\')
      .replaceAll('\r', '\\r')
      .replaceAll('\n', '\\n');

  final blocks = <String>[
    'Source language: ${escapeLanguage(draft.sourceLanguage)}\n'
        'Source text:\n'
        '${draft.sourceText}',
    for (var index = 0; index < draft.translations.length; index++)
      'Translation ${index + 1} language: '
          '${escapeLanguage(draft.translations[index].targetLanguage)}\n'
          'Translation text:\n'
          '${draft.translations[index].text}',
  ];
  return 'Kotoha workspace export v1\n\n${blocks.join('\n\n')}\n';
}
