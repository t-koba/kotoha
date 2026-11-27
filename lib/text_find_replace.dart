import 'package:flutter/widgets.dart'
    show TextEditingController, TextSelection, TextRange;

/// True when [text] contains a UTF-16 surrogate that is not part of a pair.
/// Flutter selections and edits operate on code units, so such text would
/// split a character if it were used as a query or inserted as a replacement.
bool _hasUnpairedSurrogate(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= text.length) return true;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

/// Returns the half-open range of the first literal, case-sensitive [query]
/// at or after [start], or null when [query] is empty, malformed or absent.
TextRange? findLiteralMatch(String text, String query, int start) {
  if (query.isEmpty ||
      _hasUnpairedSurrogate(query) ||
      start < 0 ||
      start > text.length) {
    return null;
  }
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
/// text becomes the selection. Empty or unpaired-surrogate queries and
/// replacements never change the value.
bool replaceSelection(
  TextEditingController controller,
  String query,
  String replacement,
) {
  if (query.isEmpty ||
      _hasUnpairedSurrogate(query) ||
      _hasUnpairedSurrogate(replacement)) {
    return false;
  }
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
/// Returns -1 without changing [controller] when a growing replacement would
/// make the result exceed the caller-supplied [maxOutputLength] UTF-16 code
/// units. Shrinking replacements are allowed even when the source already
/// exceeds that limit. Unpaired-surrogate queries and replacements are
/// rejected without changing the value.
int replaceAll(
  TextEditingController controller,
  String query,
  String replacement, {
  required int maxOutputLength,
}) {
  if (query.isEmpty ||
      _hasUnpairedSurrogate(query) ||
      _hasUnpairedSurrogate(replacement)) {
    return 0;
  }
  final value = controller.value;
  final text = value.text;
  final caret = value.selection.end.clamp(0, text.length);
  var mappedCaret = caret;
  var caretMapped = false;
  var shift = 0;
  var projectedLength = text.length;
  final replaced = StringBuffer();
  var scanFrom = 0;
  var count = 0;
  while (true) {
    final index = text.indexOf(query, scanFrom);
    if (index < 0) break;
    final matchEnd = index + query.length;
    if (!caretMapped) {
      if (caret <= index) {
        mappedCaret = caret + shift;
        caretMapped = true;
      } else if (caret < matchEnd) {
        // A caret inside the replaced text moves to the end of its
        // replacement so it never lands between UTF-16 code units.
        mappedCaret = index + shift + replacement.length;
        caretMapped = true;
      } else {
        shift += replacement.length - query.length;
      }
    }
    final nextLength = projectedLength + replacement.length - query.length;
    // Refuse before writing, so the buffer can never grow past the budget.
    if (replacement.length > query.length && nextLength > maxOutputLength) {
      return -1;
    }
    projectedLength = nextLength;
    replaced.write(text.substring(scanFrom, index));
    replaced.write(replacement);
    count++;
    scanFrom = matchEnd;
  }
  if (count == 0) return 0;
  if (!caretMapped) mappedCaret = caret + shift;
  replaced.write(text.substring(scanFrom));
  final updated = replaced.toString();
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(
      offset: mappedCaret.clamp(0, updated.length),
    ),
    composing: TextRange.empty,
  );
  return count;
}
