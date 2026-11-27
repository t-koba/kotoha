import 'dart:convert';

import 'package:flutter/material.dart';

import 'json_translation_segments.dart';
import 'l10n/app_localizations.dart';

/// A collapsed-by-default panel for editing string values in JSON source text.
///
/// The panel never re-serializes the source: it uses [parseJsonStringSegments]
/// to locate raw value ranges and writes the rewritten text back to the
/// supplied source [controller]. Empty translation fields leave values alone.
/// A changed [sourceRevision] means a different source document was loaded in
/// the same controller, so pending fields and status are discarded. Formatting
/// edits to the same document leave pending fields intact.
class StructuredJsonPanel extends StatefulWidget {
  const StructuredJsonPanel({
    super.key,
    required this.controller,
    this.sourceRevision = 0,
    this.enableIMEPersonalizedLearning = false,
  });

  final TextEditingController controller;
  final int sourceRevision;
  final bool enableIMEPersonalizedLearning;

  @override
  State<StructuredJsonPanel> createState() => _StructuredJsonPanelState();
}

enum _PanelState { valid, invalid, tooLarge, tooMany }

/// Maps an old UTF-16 selection offset through source-ordered [edits].
///
/// An offset strictly inside a replaced raw range maps by relative clamped
/// position; an offset exactly at a range end is a boundary and shifts by
/// the cumulative delta to the new end, consistently for longer and shorter
/// replacements.
int _mapOffset(
  int offset,
  List<({int start, int end, int newLength})> edits,
  int rewrittenLength,
) {
  var shift = 0;
  for (final edit in edits) {
    if (offset < edit.start) break;
    if (offset < edit.end) {
      final inner = offset - edit.start;
      return _clamp(
        edit.start + shift + (inner < edit.newLength ? inner : edit.newLength),
        rewrittenLength,
      );
    }
    shift += edit.newLength - (edit.end - edit.start);
  }
  return _clamp(offset + shift, rewrittenLength);
}

int _clamp(int offset, int length) =>
    offset < 0 ? 0 : (offset > length ? length : offset);

class _StructuredJsonPanelState extends State<StructuredJsonPanel> {
  static const int sourceLimit = 128 * 1024;
  static const int rowLimit = 200;

  String? _source;
  JsonStringSegments? _segments;
  _PanelState _panelState = _PanelState.invalid;
  final List<TextEditingController> _fields = <TextEditingController>[];
  List<({String path, String value})>? _identities;
  bool _applied = false;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSourceChanged);
    _recompute();
  }

  @override
  void didUpdateWidget(covariant StructuredJsonPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = !identical(
      oldWidget.controller,
      widget.controller,
    );
    final sourceReplaced = oldWidget.sourceRevision != widget.sourceRevision;
    if (!controllerChanged && !sourceReplaced) return;
    if (controllerChanged) {
      oldWidget.controller.removeListener(_onSourceChanged);
      widget.controller.addListener(_onSourceChanged);
    }
    // Identical controller text and identical parsed identities are not
    // evidence of the same document: loading another file can produce the
    // same bytes. Discard fields, identities and status before reparsing, so a
    // pending edit never survives into the replacement document.
    _clearFields();
    _recompute();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSourceChanged);
    _clearFields();
    super.dispose();
  }

  void _clearFields() {
    for (final field in _fields) {
      field.dispose();
    }
    _fields.clear();
    _identities = null;
  }

  void _onSourceChanged() {
    if (widget.controller.text == _source) return;
    // An apply writes through this controller: refresh its fields but keep the
    // applied status visible until the source changes again.
    setState(() => _recompute(clearStatus: !_writing));
  }

  /// Keeps translation fields only when every parsed path and decoded source
  /// value still appears in the same order; any other change starts fresh.
  void _recompute({bool clearStatus = true}) {
    final source = widget.controller.text;
    _source = source;
    _segments = null;
    if (clearStatus) _applied = false;

    if (source.length > sourceLimit) {
      _clearFields();
      _panelState = _PanelState.tooLarge;
      return;
    }
    late final JsonStringSegments parsed;
    try {
      parsed = parseJsonStringSegments(source);
    } on FormatException {
      _clearFields();
      _panelState = _PanelState.invalid;
      return;
    }
    if (parsed.values.length > rowLimit) {
      _clearFields();
      _panelState = _PanelState.tooMany;
      return;
    }

    final identities = [
      for (final segment in parsed.values)
        (path: segment.path, value: segment.value),
    ];
    final previous = _identities;
    final reuse = previous != null && _sameIdentities(previous, identities);
    if (!reuse) {
      _clearFields();
      for (var index = 0; index < identities.length; index++) {
        _fields.add(TextEditingController());
      }
    }
    _identities = identities;
    _segments = parsed;
    _panelState = _PanelState.valid;
  }

  bool _sameIdentities(
    List<({String path, String value})> previous,
    List<({String path, String value})> current,
  ) {
    if (previous.length != current.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (previous[index] != current[index]) return false;
    }
    return true;
  }

  void _apply() {
    final segments = _segments;
    if (segments == null) return;

    final translations = <int, String>{};
    final edits = <({int start, int end, int newLength})>[];
    for (final segment in segments.values) {
      final translation = _fields[segment.id].text;
      if (translation.isEmpty || translation == segment.value) continue;
      translations[segment.id] = translation;
      final encoded = jsonEncode(translation);
      edits.add((
        start: segment.start,
        end: segment.end,
        newLength: encoded.length - 2,
      ));
    }
    if (translations.isEmpty) return;
    final rewritten = segments.apply(translations);
    final selection = widget.controller.selection;
    final base = _mapOffset(selection.baseOffset, edits, rewritten.length);
    final extent = _mapOffset(selection.extentOffset, edits, rewritten.length);

    _writing = true;
    try {
      widget.controller.value = widget.controller.value.copyWith(
        text: rewritten,
        selection: TextSelection(
          baseOffset: base,
          extentOffset: extent,
          affinity: selection.affinity,
          isDirectional: selection.isDirectional,
        ),
        composing: TextRange.empty,
      );
    } finally {
      _writing = false;
    }
    setState(() => _applied = true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodySmall;
    // The collapsed header stays in normal keyboard traversal so it can be
    // reached and activated without a pointer. ExpansionTile only builds its
    // body while open, so no additional focus exclusion is needed.
    return ExpansionTile(
      key: const ValueKey('structured-json-panel'),
      initiallyExpanded: false,
      // A compact header keeps existing short-viewport geometry and focus
      // order intact while the panel stays visible and tappable.
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 0,
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      title: Text(
        strings.structuredJsonTitle,
        style: Theme.of(context).textTheme.labelSmall,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: switch (_panelState) {
              _PanelState.tooLarge => [
                Text(strings.structuredJsonTooLarge, style: style),
              ],
              _PanelState.tooMany => [
                Text(strings.structuredJsonTooMany, style: style),
              ],
              _PanelState.invalid => [
                Text(strings.structuredJsonInvalid, style: style),
              ],
              _PanelState.valid => _validChildren(strings),
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _validChildren(AppLocalizations strings) => [
    Text(strings.structuredJsonAvailable(_segments!.values.length)),
    const SizedBox(height: 8),
    for (final segment in _segments!.values)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(segment.path, style: Theme.of(context).textTheme.labelMedium),
            Text(segment.value, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            TextField(
              key: ValueKey<String>('structured-json-field-${segment.id}'),
              controller: _fields[segment.id],
              enableIMEPersonalizedLearning:
                  widget.enableIMEPersonalizedLearning,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: strings.structuredJsonEmptyHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        key: const ValueKey('structured-json-apply'),
        onPressed: _apply,
        icon: const Icon(Icons.check),
        label: Text(strings.structuredJsonApply),
      ),
    ),
    if (_applied)
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(strings.structuredJsonApplied),
      ),
  ];
}
