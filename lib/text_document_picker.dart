import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _mobileImport = MethodChannel('org.kotoha/text_import');

class TextDocument {
  const TextDocument(this.name, this.readAsBytes);

  final String name;
  final Future<Uint8List> Function() readAsBytes;
}

Future<TextDocument?> pickTextDocument() async {
  if (defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS) {
    final reply = await _mobileImport.invokeMethod<Object?>('open');
    if (reply == null) return null;
    if (reply is! Map ||
        reply['name'] is! String ||
        (reply['name'] as String).isEmpty ||
        reply['bytes'] is! Uint8List) {
      throw const FormatException('Invalid document response.');
    }
    final bytes = reply['bytes'] as Uint8List;
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
  return file == null ? null : TextDocument(file.name, file.readAsBytes);
}
