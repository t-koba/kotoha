import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Source-level invariant: the documented default is declared in the manifest
  // source, and this check stays limited to that declaration.
  test('Android manifest application tag declares allowBackup=false', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest);
    expect(application, isNotNull);
    expect(application!.group(0), contains('android:allowBackup="false"'));
  });
}
