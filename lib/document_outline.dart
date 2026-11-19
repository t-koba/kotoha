import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'document_blocks.dart';
import 'l10n/app_localizations.dart';

/// Longest source prefix parsed for an outline, in UTF-16 code units.
const int maxOutlineSourceLength = 128 * 1024;

/// Most outline entries built for one source value.
const int maxVisibleOutlineBlocks = 200;

class _OutlineData {
  const _OutlineData({
    required this.text,
    required this.blocks,
    required this.visibleCount,
    required this.truncated,
  });

  final String text;
  final List<DocumentBlock> blocks;
  final int visibleCount;
  final bool truncated;
}

_OutlineData _parseOutline(String text) {
  final prefixLength = min(text.length, maxOutlineSourceLength);
  final blocks = parseDocumentBlocks(text.substring(0, prefixLength));
  return _OutlineData(
    text: text,
    blocks: blocks,
    visibleCount: min(blocks.length, maxVisibleOutlineBlocks),
    truncated:
        prefixLength < text.length || blocks.length > maxVisibleOutlineBlocks,
  );
}

/// A compact outline of the beginning of the flat source text's blocks.
///
/// The controller's value is the only source of blocks: the outline reparses a
/// bounded prefix only when the text changes and holds no copy of the
/// document. Block ranges remain exact offsets into the full source. Activating
/// an entry only moves the editor's selection to that block's exact source
/// range.
class DocumentOutline extends StatefulWidget {
  const DocumentOutline({
    super.key,
    required this.controller,
    required this.sourceFocusNode,
  });

  final TextEditingController controller;
  final FocusNode sourceFocusNode;

  @override
  State<DocumentOutline> createState() => _DocumentOutlineState();
}

class _DocumentOutlineState extends State<DocumentOutline> {
  late _OutlineData _data;

  @override
  void initState() {
    super.initState();
    _data = _parseOutline(widget.controller.text);
    widget.controller.addListener(_handleControllerChanged);
  }

  @override
  void didUpdateWidget(covariant DocumentOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == oldWidget.controller) return;
    oldWidget.controller.removeListener(_handleControllerChanged);
    widget.controller.addListener(_handleControllerChanged);
    final text = widget.controller.text;
    if (!identical(text, _data.text) && text != _data.text) {
      _data = _parseOutline(text);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    final text = widget.controller.text;
    if (identical(text, _data.text) || text == _data.text) return;
    setState(() => _data = _parseOutline(text));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final data = _data;
    return Column(
      key: const ValueKey('document-outline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.documentOutline,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (data.truncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineTruncated),
          ),
        if (data.blocks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineEmpty),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.visibleCount,
            itemBuilder: (context, index) => _OutlineEntry(
              block: data.blocks[index],
              index: index,
              controller: widget.controller,
              sourceFocusNode: widget.sourceFocusNode,
              emptyLabel: strings.documentOutlineUntitled,
            ),
          ),
      ],
    );
  }
}

class _OutlineEntry extends StatelessWidget {
  const _OutlineEntry({
    required this.block,
    required this.index,
    required this.controller,
    required this.sourceFocusNode,
    required this.emptyLabel,
  });

  final DocumentBlock block;
  final int index;
  final TextEditingController controller;
  final FocusNode sourceFocusNode;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final identifier = 'document-block-$index';
    final label = block.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Semantics(
      identifier: identifier,
      child: ListTile(
        key: ValueKey(identifier),
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.zero,
        title: Text(
          label.isEmpty ? emptyLabel : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        onTap: () {
          controller.selection = TextSelection(
            baseOffset: block.start,
            extentOffset: block.end,
          );
          sourceFocusNode.requestFocus();
        },
      ),
    );
  }
}
