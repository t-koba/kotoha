import 'package:flutter/material.dart';

import 'json_translation_segments.dart';
import 'l10n/app_localizations.dart';

/// A collapsed-by-default panel for editing string values in JSON source text.
///
/// The panel never re-serializes the source: it uses [parseJsonStringSegments]
/// to locate raw value ranges and writes the rewritten text back to the
/// supplied source [controller]. Empty translation fields leave values alone.
class StructuredJsonPanel extends StatefulWidget {
  const StructuredJsonPanel({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<StructuredJsonPanel> createState() => _StructuredJsonPanelState();
}

enum _PanelState { valid, invalid, tooLarge, tooMany }

class _StructuredJsonPanelState extends State<StructuredJsonPanel> {
  static const int sourceLimit = 128 * 1024;
  static const int rowLimit = 200;

  String? _source;
  JsonStringSegments? _segments;
  _PanelState _panelState = _PanelState.invalid;
  final List<TextEditingController> _fields = <TextEditingController>[];
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
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onSourceChanged);
      widget.controller.addListener(_onSourceChanged);
      _source = null;
      _recompute();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSourceChanged);
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final field in _fields) {
      field.dispose();
    }
    _fields.clear();
  }

  void _onSourceChanged() {
    if (widget.controller.text == _source) return;
    // An apply writes through this controller: refresh its fields but keep the
    // applied status visible until the source changes again.
    setState(() => _recompute(clearStatus: !_writing));
  }

  /// Parses only when the source text differs from the cached text.
  void _recompute({bool clearStatus = true}) {
    final source = widget.controller.text;
    _source = source;
    _disposeFields();
    _segments = null;
    if (clearStatus) _applied = false;

    if (source.length > sourceLimit) {
      _panelState = _PanelState.tooLarge;
      return;
    }
    try {
      final parsed = parseJsonStringSegments(source);
      if (parsed.values.length > rowLimit) {
        _panelState = _PanelState.tooMany;
        return;
      }
      _segments = parsed;
      _panelState = _PanelState.valid;
      for (var index = 0; index < parsed.values.length; index++) {
        _fields.add(TextEditingController());
      }
    } on FormatException {
      _panelState = _PanelState.invalid;
    }
  }

  void _apply() {
    final segments = _segments;
    if (segments == null) return;

    final translations = <int, String>{};
    for (final segment in segments.values) {
      final translation = _fields[segment.id].text;
      if (translation.isEmpty || translation == segment.value) continue;
      translations[segment.id] = translation;
    }
    final rewritten = segments.apply(translations);
    final selection = widget.controller.selection;
    final base = _clamp(selection.baseOffset, rewritten.length);
    final extent = _clamp(selection.extentOffset, rewritten.length);

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

  int _clamp(int offset, int length) =>
      offset < 0 ? 0 : (offset > length ? length : offset);

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
