import 'dart:convert';
import 'dart:io';

/// Writes one explicitly exported translation as UTF-8 to the selected path.
Future<void> exportTextDocument(String path, String text) =>
    File(path).writeAsBytes(utf8.encode(text));
