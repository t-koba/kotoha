import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _mobileImport = MethodChannel('org.kotoha/text_import');

// Bound raw import I/O so oversized input is rejected before decode and the
// draft stays intact. This is not a measured editor-safe size: the full widget
// path can use far more memory than the decoded bytes, and the 16 MiB profile
// failure cause is unconfirmed (see design/text_import_audit.md).
const maxTextImportBytes = 8 * 1024 * 1024;

class TextDocument {
  const TextDocument(this.name, this.readAsBytes);

  final String name;
  final Future<Uint8List> Function() readAsBytes;
}

// A size refusal is not a malformed document. Subclassing FormatException
// keeps existing import callers fail-closed while restore reports it distinctly.
class TextDocumentTooLarge extends FormatException {
  const TextDocumentTooLarge() : super('Document exceeds size limit.');
}

// The OS file filter is advisory. Callers reject unsupported names themselves;
// this type lets restore distinguish a wrong file type from a bad v2 document.
class UnsupportedTextDocument extends FormatException {
  const UnsupportedTextDocument() : super('Unsupported text document.');
}

Future<TextDocument?> pickTextDocument() async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    final reply = await _mobileImport.invokeMethod<Object?>('open', {
      'maxBytes': maxTextImportBytes,
    });
    if (reply == null) return null;
    if (reply is! Map ||
        reply['name'] is! String ||
        (reply['name'] as String).isEmpty ||
        reply['bytes'] is! Uint8List) {
      throw const FormatException('Invalid document response.');
    }
    final bytes = reply['bytes'] as Uint8List;
    if (bytes.length > maxTextImportBytes) {
      throw const TextDocumentTooLarge();
    }
    return TextDocument(reply['name'] as String, () async => bytes);
  }
  final file = await FileSelectorPlatform.instance.openFile(
    acceptedTypeGroups: const [
      XTypeGroup(
        extensions: ['txt', 'md', 'markdown'],
        uniformTypeIdentifiers: [
          'public.utf8-plain-text',
          'net.daringfireball.markdown',
        ],
      ),
    ],
  );
  if (file == null) return null;
  return TextDocument(file.name, () async {
    // The name is validated by the caller before this closure runs. Checking
    // the size here keeps an unsupported file from being reported as too large.
    if (await file.length() > maxTextImportBytes) {
      throw const TextDocumentTooLarge();
    }
    // The file may grow between the length check and the deferred read.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (chunk.length > maxTextImportBytes - bytes.length) {
        throw const TextDocumentTooLarge();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  });
}
