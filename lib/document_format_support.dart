import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';

/// A static capability note for the local TXT/Markdown reader.
///
/// It describes what the local outline understands and what it deliberately
/// leaves in the flat source; it does not parse the document again.
class DocumentFormatSupport extends StatelessWidget {
  const DocumentFormatSupport({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final style = Theme.of(context).textTheme.bodySmall;
    return Padding(
      key: const ValueKey('document-format-support'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.documentFormatSupport,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentFormatSupportHandled, style: style),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentFormatSupportPreserved, style: style),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(strings.documentFormatSupportReview, style: style),
          ),
        ],
      ),
    );
  }
}
