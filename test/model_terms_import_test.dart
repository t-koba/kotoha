import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kotoha/model_terms_import.dart';

class MemoryReader implements PackageReader {
  MemoryReader(this.files);
  final Map<String, Uint8List> files;
  final requests = <String>[];
  final requestLimits = <int>[];
  @override
  Future<Uint8List?> readDirectoryFile(String path, int maxBytes) async {
    requests.add(path);
    requestLimits.add(maxBytes);
    return files[path];
  }
}

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

Map<String, Object?> fullManifest(
  String terms, {
  String path = 'license/terms.txt',
  int? size,
  String? hash,
  List<Map<String, Object?>>? extraTermsFiles,
  List<Map<String, Object?>>? termsEntries,
  Map<String, Object?> Function(Map<String, Object?>)? mutate,
}) {
  final h = sha256.convert(bytes(terms)).toString();
  final termsBytes = bytes(terms).length;
  final termsSize = size ?? termsBytes;
  final total = 8 + termsSize;
  final files = <Map<String, Object?>>[
    {
      'path': 'weights.bin',
      'role': 'weights',
      'sha256': 'a' * 64,
      'size_bytes': 8,
    },
    {
      'path': path,
      'role': 'terms',
      'sha256': hash ?? h,
      'size_bytes': termsSize,
    },
    ...?extraTermsFiles,
  ];
  var computedTotal = total;
  for (final extra in extraTermsFiles ?? const []) {
    computedTotal += (extra['size_bytes'] as int);
  }
  final manifest = <String, Object?>{
    'id': 'test-model',
    'display_name': 'Test model',
    'publisher': 'fixture',
    'files': files,
    'executor': {
      'engine_id': 'local.engine',
      'adapter_id': 'local.adapter',
      'required_capabilities': ['translation.text'],
    },
    'tasks': [
      {
        'capability': 'translation.text',
        'input_types': ['text'],
        'output_types': ['translations'],
        'languages': {
          'source': ['de'],
          'target': ['ar'],
          'routes': [
            {'source': 'de', 'target': 'ar', 'evidence': 'user'},
          ],
          'scripts': ['Latn'],
        },
      },
    ],
    'resources': {
      'storage_bytes': computedTotal,
      'peak_host_bytes': 0,
      'peak_accelerator_bytes': 0,
      'basis': 'declared',
      'conditions': 'fixture',
    },
    'terms':
        termsEntries ??
        [
          {
            'id': 'test-license',
            'text_file': path,
            'text_sha256': hash ?? h,
            'consent': 'explicit',
            'usage_requirements': ['Use locally'],
            'required_attributions': ['Attribution X'],
            'covered_files': ['weights.bin', path],
          },
        ],
  };
  if (mutate != null) return mutate(manifest);
  return manifest;
}

MemoryReader reader(Map<String, Object?> m, Map<String, String> termsByPath) {
  final files = <String, Uint8List>{
    'model_manifest.json': bytes(jsonEncode(m)),
  };
  for (final entry in termsByPath.entries) {
    files[entry.key] = bytes(entry.value);
  }
  return MemoryReader(files);
}

void main() {
  test(
    'review only after verified manifest and terms; approval is digest-bound',
    () async {
      const terms = 'Synthetic license';
      final r = reader(fullManifest(terms), {'license/terms.txt': terms});
      VerifiedTerms? seen;
      final a = await const ModelTermsImport().run(r, (v) async {
        seen = v;
        return true;
      });
      expect(r.requests, ['model_manifest.json', 'license/terms.txt']);
      expect(r.requestLimits, [1024 * 1024, bytes(terms).length]);
      // No weight path is ever requested.
      expect(r.requests.contains('weights.bin'), isFalse);
      expect(seen!.documents.single.text, terms);
      expect(seen!.documents.single.usageRequirements, ['Use locally']);
      expect(seen!.modelId, 'test-model');
      expect(seen!.publisher, 'fixture');
      expect(seen!.verifiedTermsFileCount, 1);
      expect(
        a!.manifestDigest,
        sha256.convert(r.files['model_manifest.json']!).toString(),
      );
      expect(a.termsDigest, isNotEmpty);
    },
  );
  test(
    'reviewer runs only after every declared terms file is verified',
    () async {
      const first = 'First terms';
      const second = 'Second terms';
      final h1 = sha256.convert(bytes(first)).toString();
      final h2 = sha256.convert(bytes(second)).toString();
      final manifest = fullManifest(
        first,
        extraTermsFiles: [
          {
            'path': 'license/more.txt',
            'role': 'terms',
            'sha256': h2,
            'size_bytes': bytes(second).length,
          },
        ],
        termsEntries: [
          {
            'id': 'first-terms',
            'text_file': 'license/terms.txt',
            'text_sha256': h1,
            'consent': 'explicit',
            'usage_requirements': ['Use locally'],
            'required_attributions': [],
            'covered_files': ['weights.bin', 'license/terms.txt'],
          },
          {
            'id': 'second-terms',
            'text_file': 'license/more.txt',
            'text_sha256': h2,
            'consent': 'explicit',
            'usage_requirements': [],
            'required_attributions': ['Attribution Y'],
            'covered_files': ['license/more.txt', 'weights.bin'],
          },
        ],
      );
      // Fix the storage total for the two-terms fixture.
      (manifest['resources'] as Map)['storage_bytes'] =
          8 + bytes(first).length + bytes(second).length;
      // The aggregate bound rejects before reading any terms bytes.
      final limitedReader = reader(manifest, {
        'license/terms.txt': first,
        'license/more.txt': second,
      });
      await expectLater(
        const ModelTermsImport(maxTotalTermsBytes: 5)
            .run(limitedReader, (_) async => true),
        throwsA(isA<FormatException>()),
      );
      expect(limitedReader.requests, ['model_manifest.json']);
      // covered_files must cover every file; union here covers all three.
      final r = reader(manifest, {
        'license/terms.txt': first,
        'license/more.txt': second,
      });
      final seenRequestsAtReview = <List<String>>[];
      VerifiedTerms? seen;
      final a = await const ModelTermsImport().run(r, (v) async {
        seen = v;
        seenRequestsAtReview.add(List.of(r.requests));
        return true;
      });
      expect(seen!.documents, hasLength(2));
      // Reviewer saw both verified documents.
      expect(seen!.documents.map((d) => d.text), [first, second]);
      // Both terms files were read before the reviewer ran.
      expect(seenRequestsAtReview.single, [
        'model_manifest.json',
        'license/terms.txt',
        'license/more.txt',
      ]);
      expect(seen!.verifiedTermsFileCount, 2);
      expect(r.requests.contains('weights.bin'), isFalse);
      expect(a, isNotNull);
    },
  );
  test('multiple term records may share one verified terms file', () async {
    const terms = 'Shared synthetic terms';
    final digest = sha256.convert(bytes(terms)).toString();
    final manifest = fullManifest(
      terms,
      termsEntries: [
        {
          'id': 'license-a',
          'text_file': 'license/terms.txt',
          'text_sha256': digest,
          'consent': 'explicit',
          'usage_requirements': ['Use locally'],
          'required_attributions': [],
          'covered_files': ['weights.bin', 'license/terms.txt'],
        },
        {
          'id': 'license-b',
          'text_file': 'license/terms.txt',
          'text_sha256': digest,
          'consent': 'explicit',
          'usage_requirements': [],
          'required_attributions': ['Attribution B'],
          'covered_files': ['license/terms.txt', 'weights.bin'],
        },
      ],
    );
    final r = reader(manifest, {'license/terms.txt': terms});
    VerifiedTerms? review;
    final authorization = await const ModelTermsImport().run(r, (value) async {
      review = value;
      return true;
    });

    expect(authorization, isNotNull);
    expect(r.requests, ['model_manifest.json', 'license/terms.txt']);
    expect(review!.documents, hasLength(2));
    expect(review!.documents.map((document) => document.id), [
      'license-a',
      'license-b',
    ]);
    expect(review!.verifiedTermsFileCount, 1);
  });
  test('storage size aggregation rejects integer overflow', () async {
    const terms = 'terms';
    final manifest = fullManifest(
      terms,
      mutate: (value) {
        (value['files'] as List).first['size_bytes'] = 0x7fffffffffffffff;
        (value['resources'] as Map)['storage_bytes'] = 0x7fffffffffffffff;
        return value;
      },
    );
    final r = reader(manifest, {'license/terms.txt': terms});
    var called = false;
    await expectLater(
      const ModelTermsImport().run(r, (_) async {
        called = true;
        return true;
      }),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
    expect(r.requests, ['model_manifest.json']);
  });
  test('missing manifest is a verification failure, not a decline', () async {
    var called = false;
    await expectLater(
      const ModelTermsImport().run(MemoryReader({}), (_) async {
        called = true;
        return true;
      }),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });
  test('malformed manifest never invokes reviewer', () async {
    final r = MemoryReader({'model_manifest.json': bytes('{')});
    var called = false;
    await expectLater(
      const ModelTermsImport().run(r, (_) async {
        called = true;
        return true;
      }),
      throwsA(anything),
    );
    expect(called, isFalse);
  });
  test('strict schema failures never invoke reviewer', () async {
    const terms = 'terms';
    final h = sha256.convert(bytes(terms)).toString();
    final cases = <Map<String, Object?>>[
      // Missing mandatory executor/tasks/resources.
      {
        'id': 'test-model',
        'display_name': 'Test model',
        'publisher': 'fixture',
        'files': [
          {
            'path': 'weights.bin',
            'role': 'weights',
            'sha256': 'a' * 64,
            'size_bytes': 8,
          },
        ],
        'terms': [],
      },
      // Unexpected top-level property.
      fullManifest(terms, mutate: (m) => {...m, 'extra': 1}),
      // Bad manifest id pattern.
      fullManifest(terms, mutate: (m) => {...m, 'id': 'Bad ID'}),
      // Duplicate file path.
      fullManifest(
        terms,
        mutate: (m) {
          final files = List.of(m['files'] as List);
          files.add((files.first as Map).map((k, v) => MapEntry(k, v)));
          return {...m, 'files': files};
        },
      ),
      // Storage total mismatch.
      fullManifest(
        terms,
        mutate: (m) => {
          ...m,
          'resources': {
            'storage_bytes': 999,
            'peak_host_bytes': 0,
            'peak_accelerator_bytes': 0,
            'basis': 'declared',
            'conditions': 'fixture',
          },
        },
      ),
      // Duplicate terms id.
      fullManifest(
        terms,
        extraTermsFiles: [
          {
            'path': 'license/more.txt',
            'role': 'terms',
            'sha256': h,
            'size_bytes': bytes(terms).length,
          },
        ],
        termsEntries: [
          {
            'id': 'dup',
            'text_file': 'license/terms.txt',
            'text_sha256': h,
            'consent': 'explicit',
            'usage_requirements': [],
            'required_attributions': [],
            'covered_files': ['weights.bin', 'license/terms.txt'],
          },
          {
            'id': 'dup',
            'text_file': 'license/more.txt',
            'text_sha256': h,
            'consent': 'explicit',
            'usage_requirements': [],
            'required_attributions': [],
            'covered_files': ['license/more.txt'],
          },
        ],
      ),
      // Duplicate covered path within one entry.
      fullManifest(
        terms,
        mutate: (m) {
          final termsList = (m['terms'] as List)
              .map((e) => Map<String, Object?>.of(e as Map<String, dynamic>))
              .toList();
          termsList[0]['covered_files'] = ['weights.bin', 'weights.bin'];
          return {...m, 'terms': termsList};
        },
      ),
      // Incomplete coverage: weights.bin uncovered.
      fullManifest(
        terms,
        mutate: (m) {
          final termsList = (m['terms'] as List)
              .map((e) => Map<String, Object?>.of(e as Map<String, dynamic>))
              .toList();
          termsList[0]['covered_files'] = ['license/terms.txt'];
          return {...m, 'terms': termsList};
        },
      ),
      // File entry with unexpected property.
      fullManifest(
        terms,
        mutate: (m) {
          final files = (m['files'] as List)
              .map((e) => Map<String, Object?>.of(e as Map<String, dynamic>))
              .toList();
          files[0]['unexpected'] = true;
          return {...m, 'files': files};
        },
      ),
    ];
    for (var i = 0; i < cases.length; i++) {
      final r = reader(cases[i], {'license/terms.txt': terms});
      var called = false;
      await expectLater(
        const ModelTermsImport().run(r, (_) async {
          called = true;
          return true;
        }),
        throwsA(anything),
        reason: 'case $i',
      );
      expect(called, isFalse, reason: 'case $i');
    }
  });
  test('hash size and unsafe binding failures never invoke reviewer', () async {
    for (final m in [
      fullManifest('terms', hash: 'b' * 64),
      fullManifest('terms', size: 99),
      fullManifest('terms', path: '../terms.txt'),
    ]) {
      final r = reader(m, {'license/terms.txt': 'terms'});
      var called = false;
      await expectLater(
        const ModelTermsImport().run(r, (_) async {
          called = true;
          return true;
        }),
        throwsA(anything),
      );
      expect(called, isFalse);
      expect(r.requests.contains('weights.bin'), isFalse);
    }
  });
  test('decline gives no approval and never reads weights', () async {
    const terms = 'terms';
    final r = reader(fullManifest(terms), {'license/terms.txt': terms});
    final a = await const ModelTermsImport().run(r, (_) async => false);
    expect(a, isNull);
    expect(r.requests, ['model_manifest.json', 'license/terms.txt']);
    expect(r.requests.contains('weights.bin'), isFalse);
  });
}
