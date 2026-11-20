import 'package:flutter/widgets.dart'
    show TextEditingController, TextSelection, TextRange;

/// Returns the half-open range of the first literal, case-sensitive [query]
/// at or after [start], or null when [query] is empty or absent.
TextRange? findLiteralMatch(String text, String query, int start) {
  if (query.isEmpty || start < 0 || start > text.length) return null;
  final index = text.indexOf(query, start);
  if (index < 0) return null;
  return TextRange(start: index, end: index + query.length);
}

/// Selects the next occurrence after the current selection end, wrapping to
/// the start of the text. Returns false without changing the value when the
/// query is empty or no occurrence exists.
bool findNext(TextEditingController controller, String query) {
  if (query.isEmpty) return false;
  final value = controller.value;
  final text = value.text;
  if (query.length > text.length) return false;
  final start = value.selection.end.clamp(0, text.length);
  // A match at `start` is included in the forward pass; the wrap only runs
  // when nothing remains ahead of the current selection.
  final match =
      findLiteralMatch(text, query, start) ?? findLiteralMatch(text, query, 0);
  if (match == null) return false;
  controller.value = value.copyWith(
    selection: TextSelection(baseOffset: match.start, extentOffset: match.end),
    composing: TextRange.empty,
  );
  return true;
}

/// Replaces the selected text only when it is exactly [query]. The inserted
/// text becomes the selection. An empty query never changes the value.
bool replaceSelection(
  TextEditingController controller,
  String query,
  String replacement,
) {
  if (query.isEmpty) return false;
  final value = controller.value;
  final selection = value.selection;
  if (selection.isCollapsed || selection.textInside(value.text) != query) {
    return false;
  }
  final start = selection.start;
  final updated = value.text.replaceRange(start, selection.end, replacement);
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection(
      baseOffset: start,
      extentOffset: start + replacement.length,
    ),
    composing: TextRange.empty,
  );
  return true;
}

/// Replaces every non-overlapping literal occurrence and returns the count.
/// An empty query is a no-op. New matches created by the replacement are not
/// revisited; the scan advances past the original match in the source text.
int replaceAll(
  TextEditingController controller,
  String query,
  String replacement,
) {
  if (query.isEmpty) return 0;
  final value = controller.value;
  final text = value.text;
  final replaced = StringBuffer();
  var scanFrom = 0;
  var count = 0;
  while (true) {
    final index = text.indexOf(query, scanFrom);
    if (index < 0) break;
    replaced.write(text.substring(scanFrom, index));
    replaced.write(replacement);
    count++;
    scanFrom = index + query.length;
  }
  if (count == 0) return 0;
  replaced.write(text.substring(scanFrom));
  final updated = replaced.toString();
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(
      offset: value.selection.end.clamp(0, updated.length),
    ),
    composing: TextRange.empty,
  );
  return count;
}
