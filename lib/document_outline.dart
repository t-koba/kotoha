import 'dart:math' show min;

import 'package:flutter/material.dart';

import 'document_blocks.dart';
import 'document_review_flags.dart';
import 'l10n/app_localizations.dart';

/// Longest source prefix parsed for an outline, in UTF-16 code units.
const int maxOutlineSourceLength = 128 * 1024;

/// Most outline entries built for one source value.
const int maxVisibleOutlineBlocks = 200;

/// Extra source inspected only to decide whether a boundary block continues.
const int maxOutlineLookaheadLength = 4 * 1024;

/// Largest source prefix the outline may parse for [sourceLength] code units.
int outlineParseEnd(int sourceLength) =>
    min(sourceLength, maxOutlineSourceLength + maxOutlineLookaheadLength);

/// The normalized label shared by outline display and search matching.
String _outlineLabel(DocumentBlock block) =>
    block.text.replaceAll(RegExp(r'\s+'), ' ').trim();

/// Per-block view data derived once from the source and reused by search,
/// review filtering and display.
typedef _OutlineItem = ({
  DocumentBlock block,
  String label,
  String searchLabel,
  Set<DocumentReviewFlag> flags,
});

class _OutlineData {
  const _OutlineData({
    required this.text,
    required this.items,
    required this.prefixTruncated,
    required this.blocksTruncated,
  });

  final String text;
  final List<_OutlineItem> items;
  final bool prefixTruncated;
  final bool blocksTruncated;
}

_OutlineData _parseOutline(String text) {
  final boundary = min(text.length, maxOutlineSourceLength);
  final prefixTruncated = boundary < text.length;
  var blocks = parseDocumentBlocks(
    text.substring(0, outlineParseEnd(text.length)),
  );
  if (prefixTruncated) {
    // A block is only offered when its whole range is established inside the
    // disclosed prefix. An unclosed fence can end exactly at the boundary, so
    // its closing marker must be strictly inside it.
    blocks = blocks.where((block) {
      if (block.start >= boundary) return false;
      if (block.kind == DocumentBlockKind.codeBlock) {
        return block.end < boundary;
      }
      return block.end <= boundary;
    }).toList();
  }
  final items = blocks
      .map((block) {
        final label = _outlineLabel(block);
        return (
          block: block,
          label: label,
          searchLabel: label.toLowerCase(),
          flags: detectDocumentReviewFlags(block.text),
        );
      })
      .toList(growable: false);
  return _OutlineData(
    text: text,
    items: items,
    prefixTruncated: prefixTruncated,
    blocksTruncated: items.length > maxVisibleOutlineBlocks,
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
  bool _reviewOnly = false;

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
    final matches = <(int, _OutlineItem)>[];
    for (var index = 0; index < data.items.length; index++) {
      final item = data.items[index];
      if (hasQuery && !item.searchLabel.contains(query)) continue;
      if (_reviewOnly && item.flags.isEmpty) continue;
      matches.add((index, item));
    }
    final matchesTruncated =
        (hasQuery || _reviewOnly) && matches.length > maxVisibleOutlineBlocks;

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
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilterChip(
            key: const ValueKey('document-outline-review-only'),
            label: Text(strings.documentOutlineReviewOnly),
            selected: _reviewOnly,
            onSelected: (selected) => setState(() => _reviewOnly = selected),
          ),
        ),
        if (data.prefixTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineTruncated),
          ),
        if (!hasQuery && !_reviewOnly && data.blocksTruncated)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentOutlineEntriesTruncated),
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
                  : _reviewOnly
                  ? strings.documentOutlineNoReviewMatches
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
              final (originalIndex, item) = matches[index];
              return _OutlineEntry(
                block: item.block,
                label: item.label,
                flags: item.flags,
                index: originalIndex,
                controller: widget.controller,
                sourceFocusNode: widget.sourceFocusNode,
                emptyLabel: strings.documentOutlineUntitled,
                strings: strings,
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
    required this.label,
    required this.flags,
    required this.index,
    required this.controller,
    required this.sourceFocusNode,
    required this.emptyLabel,
    required this.strings,
  });

  final DocumentBlock block;
  final String label;
  final Set<DocumentReviewFlag> flags;
  final int index;
  final TextEditingController controller;
  final FocusNode sourceFocusNode;
  final String emptyLabel;
  final AppLocalizations strings;

  @override
  Widget build(BuildContext context) {
    final identifier = 'document-block-$index';
    final review = flags.isEmpty
        ? null
        : '${strings.documentReviewLabel} ${flags.map((flag) => switch (flag) {
            DocumentReviewFlag.number => strings.documentReviewNumber,
            DocumentReviewFlag.link => strings.documentReviewLink,
            DocumentReviewFlag.placeholder => strings.documentReviewPlaceholder,
          }).join(', ')}';
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
        subtitle: review == null
            ? null
            : Text(review, style: Theme.of(context).textTheme.labelSmall),
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
