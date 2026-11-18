import 'dart:typed_data' show BytesBuilder;

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _mobileImport = MethodChannel('org.kotoha/text_import');

// 8 MiB is generous for text/Markdown translation and below the 16 MiB size
// at which the CI editor profile does not complete.
const maxTextImportBytes = 8 * 1024 * 1024;

class TextDocument {
  const TextDocument(this.name, this.readAsBytes);

  final String name;
  final Future<Uint8List> Function() readAsBytes;
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
      throw const FormatException('Document exceeds size limit.');
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
  if (await file.length() > maxTextImportBytes) {
    throw const FormatException('Document exceeds size limit.');
  }
  return TextDocument(file.name, () async {
    // The file may grow between the length check and the deferred read.
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (chunk.length > maxTextImportBytes - bytes.length) {
        throw const FormatException('Document exceeds size limit.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  });
}
