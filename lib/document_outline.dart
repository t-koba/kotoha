import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'document_blocks.dart';
import 'l10n/app_localizations.dart';

/// Longest source prefix parsed for an outline, in UTF-16 code units.
const int maxOutlineSourceLength = 128 * 1024;

/// Most outline entries built for one source value.
const int maxVisibleOutlineBlocks = 200;

/// The normalized label shared by outline display and search matching.
String _outlineLabel(DocumentBlock block) =>
    block.text.replaceAll(RegExp(r'\s+'), ' ').trim();

class _OutlineData {
  const _OutlineData({
    required this.text,
    required this.blocks,
    required this.prefixTruncated,
    required this.blocksTruncated,
  });

  final String text;
  final List<DocumentBlock> blocks;
  final bool prefixTruncated;
  final bool blocksTruncated;
}

/// Ends the scan at a line boundary inside [budget], never mid-character or
/// mid-line. A boundary is either immediately before a line terminator or
/// immediately after one.
int _boundedScanEnd(String text, int budget) {
  if (text.length <= budget) return text.length;
  for (var i = budget; i > 0; i--) {
    final at = text.codeUnitAt(i);
    final before = text.codeUnitAt(i - 1);
    if (at == 0x0A && before != 0x0D) return i;
    if (at == 0x0D && i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
      return i;
    }
    if (before == 0x0A) return i;
  }
  return 0;
}

_OutlineData _parseOutline(String text) {
  final scanEnd = _boundedScanEnd(text, maxOutlineSourceLength);
  final prefixTruncated = scanEnd < text.length;
  var blocks = parseDocumentBlocks(text.substring(0, scanEnd));
  // At an artificial EOF the parser cannot know that a paragraph or code
  // fence continues. Never offer that last block as an exact selection.
  if (prefixTruncated && blocks.isNotEmpty && blocks.last.end == scanEnd) {
    blocks = blocks.sublist(0, blocks.length - 1);
  }
  return _OutlineData(
    text: text,
    blocks: blocks,
    prefixTruncated: prefixTruncated,
    blocksTruncated: blocks.length > maxVisibleOutlineBlocks,
  );
}

/// A compact outline of the beginning of the flat source text's blocks.
///
/// The controller's value is the only source of blocks: the outline reparses a
/// bounded prefix only when the text changes and holds no copy of the
/// document. Block ranges remain exact offsets into the full source. The local
/// search filters cached labels without changing the source or its offsets.
/// Activating an entry only moves the editor's selection to that block's exact
/// source range.
class DocumentOutline extends StatefulWidget {
  const DocumentOutline({
    super.key,
    required this.controller,
    required this.sourceFocusNode,
    required this.enableIMEPersonalizedLearning,
  });

  final TextEditingController controller;
  final FocusNode sourceFocusNode;
  final bool enableIMEPersonalizedLearning;

  @override
  State<DocumentOutline> createState() => _DocumentOutlineState();
}

class _DocumentOutlineState extends State<DocumentOutline> {
  final TextEditingController _searchController = TextEditingController();

  late _OutlineData _data;

  @override
  void initState() {
    super.initState();
    _data = _parseOutline(widget.controller.text);
    widget.controller.addListener(_handleControllerChanged);
    _searchController.addListener(_handleSearchChanged);
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
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    final text = widget.controller.text;
    if (identical(text, _data.text) || text == _data.text) return;
    setState(() => _data = _parseOutline(text));
  }

  void _handleSearchChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final data = _data;
    final query = _searchController.text.trim().toLowerCase();
    final hasQuery = query.isNotEmpty;
    final matches = <(int, DocumentBlock)>[];
    for (var index = 0; index < data.blocks.length; index++) {
      final block = data.blocks[index];
      if (hasQuery && !_outlineLabel(block).toLowerCase().contains(query)) {
        continue;
      }
      matches.add((index, block));
    }
    final matchesTruncated =
        hasQuery && matches.length > maxVisibleOutlineBlocks;

    return Column(
      key: const ValueKey('document-outline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.documentOutline,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Semantics(
            identifier: 'document-outline-search',
            child: TextField(
              key: const ValueKey('document-outline-search'),
              controller: _searchController,
              enableIMEPersonalizedLearning:
                  widget.enableIMEPersonalizedLearning,
              decoration: InputDecoration(
                labelText: strings.documentOutlineSearch,
                hintText: strings.documentOutlineSearchHint,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        if (data.prefixTruncated || (!hasQuery && data.blocksTruncated))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineTruncated),
          ),
        if (matchesTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineMatchesTruncated),
          ),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              hasQuery
                  ? strings.documentOutlineNoMatches
                  : strings.documentOutlineEmpty,
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: min(matches.length, maxVisibleOutlineBlocks),
            itemBuilder: (context, index) {
              final (originalIndex, block) = matches[index];
              return _OutlineEntry(
                block: block,
                index: originalIndex,
                controller: widget.controller,
                sourceFocusNode: widget.sourceFocusNode,
                emptyLabel: strings.documentOutlineUntitled,
              );
            },
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
    final label = _outlineLabel(block);
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
