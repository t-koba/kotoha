import 'package:flutter/material.dart';

import 'document_blocks.dart';
import 'l10n/app_localizations.dart';

/// A compact outline of the flat source text's top-level blocks.
///
/// The controller's value is the only source of blocks: the outline reparses
/// it on every value change and holds no copy of the document. Activating an
/// entry only moves the editor's selection to that block's exact source range.
class DocumentOutline extends StatelessWidget {
  const DocumentOutline({
    super.key,
    required this.controller,
    required this.sourceFocusNode,
  });

  final TextEditingController controller;
  final FocusNode sourceFocusNode;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final blocks = parseDocumentBlocks(value.text);
        return Column(
          key: const ValueKey('document-outline'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.documentOutline,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (blocks.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(strings.documentOutlineEmpty),
              )
            else
              for (var index = 0; index < blocks.length; index++)
                _OutlineEntry(
                  block: blocks[index],
                  index: index,
                  controller: controller,
                  sourceFocusNode: sourceFocusNode,
                  emptyLabel: strings.documentOutlineUntitled,
                ),
          ],
        );
      },
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
