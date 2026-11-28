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

  test(
    'Android backup rules exclude every documented domain from transfer',
    () {
      final manifest = File('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync();
      final application = RegExp(r'<application\b[^>]*>').firstMatch(manifest);
      expect(application, isNotNull);
      expect(
        application!.group(0),
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
      expect(
        application.group(0),
        contains('android:fullBackupContent="false"'),
      );

      final domains = [
        'file',
        'database',
        'sharedpref',
        'external',
        'root',
        'device_file',
        'device_database',
        'device_sharedpref',
        'device_root',
      ];
      final rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final match = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules);
        expect(match, isNotNull, reason: 'missing $section rules');
        final body = match!.group(1)!;
        expect(
          body,
          isNot(contains('<include')),
          reason: '$section includes data',
        );
        for (final domain in domains) {
          expect(
            body,
            contains('<exclude domain="$domain" path="." />'),
            reason: '$section must exclude all of $domain',
          );
        }
      }
      expect(
        File('android/app/src/main/res/xml/backup_rules.xml').existsSync(),
        isFalse,
      );
    },
  );
}
