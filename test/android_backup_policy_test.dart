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
    'Android backup rules exclude every domain from cloud and D2D transfer',
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
        contains('android:fullBackupContent="@xml/backup_rules"'),
      );

      final domains = ['root', 'database', 'sharedpref', 'external'];
      final rules = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      ).readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final match = RegExp(
          '<$section>(.*?)</$section>',
          dotAll: true,
        ).firstMatch(rules);
        expect(match, isNotNull, reason: 'missing $section rules');
        for (final domain in domains) {
          expect(
            match!.group(1),
            contains('<exclude domain="$domain"'),
            reason: '$section must exclude $domain',
          );
        }
      }

      final legacy = File('android/app/src/main/res/xml/backup_rules.xml')
          .readAsStringSync();
      for (final domain in domains) {
        expect(
          legacy,
          contains('<exclude domain="$domain"'),
          reason: 'API 30 rules must exclude $domain',
        );
      }
    },
  );
}
