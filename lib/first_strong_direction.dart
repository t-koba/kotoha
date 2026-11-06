import 'dart:ui' show TextDirection;

import 'unicode_bidi_data.dart';

/// UAX #9 P2/P3: first strong type outside isolates in the first paragraph.
/// A TextField accepts only one base direction, so later paragraphs share it;
/// this is not per-paragraph automatic direction or a bidi layout engine.
TextDirection firstStrongDirection(String text) {
  var isolateDepth = 0;
  for (final scalar in text.runes) {
    final bidiClass = _bidiClass(scalar);
    if (bidiClass == 2) break; // B ends the paragraph, even inside an isolate.
    if (bidiClass == 3) {
      isolateDepth++;
    } else if (bidiClass == 4) {
      if (isolateDepth > 0) isolateDepth--;
    } else if (isolateDepth == 0) {
      if (bidiClass == 1) return TextDirection.rtl; // R or AL
      if (bidiClass == 0) return TextDirection.ltr; // L
    }
  }
  return TextDirection.ltr;
}

int _bidiClass(int scalar) {
  var low = 0;
  var high = unicodeBidiClassRanges.length ~/ 3;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    final offset = middle * 3;
    if (scalar < unicodeBidiClassRanges[offset]) {
      high = middle;
    } else if (scalar > unicodeBidiClassRanges[offset + 1]) {
      low = middle + 1;
    } else {
      return unicodeBidiClassRanges[offset + 2];
    }
  }
  return 0; // Unlisted scalars have projected class L.
}
