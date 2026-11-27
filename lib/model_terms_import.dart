import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'language_roles.dart';
import 'model_capabilities.dart';

/// Largest byte count representable by a signed 64-bit JSON integer.
const int _maxByteCount = 0x7fffffffffffffff;

/// Metadata-only, read-in-place package access. Implementations must never follow
/// paths outside the selected package root or persist provider permissions.
abstract interface class PackageReader {
  Future<Uint8List?> readDirectoryFile(String relativePath, int maxBytes);
}

typedef TermsReviewer = Future<bool> Function(VerifiedTerms review);

/// A non-terms file declared in the manifest. Only metadata crosses the
/// platform boundary; the native side streams the bytes in place when asked.
class DeclaredModelFile {
  const DeclaredModelFile({
    required this.path,
    required this.role,
    required this.sizeBytes,
    required this.sha256,
  });
  final String path, role, sha256;
  final int sizeBytes;

  Map<String, Object> toPlatformArguments() => {
    'path': path,
    'sizeBytes': sizeBytes,
    'sha256': sha256,
  };
}

class VerifiedTerms {
  const VerifiedTerms({
    required this.modelId,
    required this.modelName,
    required this.publisher,
    required this.documents,
    required this.verifiedTermsFileCount,
    required this.manifestDigest,
    required this.termsDigest,
    required this.declaredFiles,
    this.capabilities = const DeclaredModelCapabilities(
      modelId: '',
      engineId: '',
      adapterId: '',
      tasks: [],
      requiredCapabilities: [],
      resources: DeclaredResourceNeeds(
        storageBytes: 0,
        peakHostBytes: 0,
        peakAcceleratorBytes: 0,
        basis: 'declared',
        conditions: '',
      ),
    ),
  });
  final String modelId, modelName, publisher;
  final List<TermsDocument> documents;
  final List<DeclaredModelFile> declaredFiles;
  final int verifiedTermsFileCount;
  final String manifestDigest, termsDigest;

  /// Manifest-DECLARED capability snapshot from the reviewed manifest: not
  /// verified support, availability or quality. A matching digest or declared
  /// route proves nothing about origin or runtime capability.
  final DeclaredModelCapabilities capabilities;
}

class TermsDocument {
  const TermsDocument(
    this.id,
    this.text,
    this.usageRequirements,
    this.attributions,
  );
  final String id, text;
  final List<String> usageRequirements, attributions;
}

/// Exists only in memory after explicit acceptance. It does not authorize an
/// engine: this increment has no runtime or weight-file reader. Callers must
/// hold only this digest binding in volatile state, clear it on a new,
/// declined, or failed review, and never persist it.
class EphemeralModelAuthorization {
  const EphemeralModelAuthorization(
    this.manifestDigest,
    this.termsDigest, [
    this.declaredFiles = const <DeclaredModelFile>[],
  ]);
  final String manifestDigest, termsDigest;

  /// Declared non-terms files, in manifest order. An integrity check is a
  /// separate explicit action; acceptance alone never opens these files.
  final List<DeclaredModelFile> declaredFiles;
}

/// Strict terms-review contract.
///
/// Validates the full `model_manifest.schema.json` structure used here
/// (required top-level keys with no extras, identifier patterns, executor,
/// tasks, resources including the storage total, and exact complete terms
/// coverage with unique term IDs), then verifies every declared terms file
/// by exact byte length and SHA-256 before invoking the reviewer.
///
/// Hashes prove only that the bytes read match the manifest. They do not
/// prove origin, authenticity, signature/provenance, or license approval,
/// and acceptance never enables an engine. This review itself opens only the
/// manifest and terms files; a separate, explicit integrity action is required
/// before any declared non-terms file is streamed.
class ModelTermsImport {
  const ModelTermsImport({
    this.maxManifestBytes = 1024 * 1024,
    this.maxTermsBytes = 1024 * 1024,
    this.maxTotalTermsBytes = 4 * 1024 * 1024,
  });
  final int maxManifestBytes, maxTermsBytes, maxTotalTermsBytes;

  Future<EphemeralModelAuthorization?> run(
    PackageReader reader,
    TermsReviewer reviewer,
  ) async {
    final manifestBytes = await reader.readDirectoryFile(
      'model_manifest.json',
      maxManifestBytes,
    );
    if (manifestBytes == null) {
      throw const FormatException('Missing model manifest');
    }
    if (manifestBytes.length > maxManifestBytes) {
      throw const FormatException('Manifest too large');
    }
    final Object? decoded = jsonDecode(
      utf8.decode(manifestBytes, allowMalformed: false),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid manifest');
    }
    final files = _validateManifest(decoded);
    // The validated declarations are reported as declared data only, never as
    // verified support or runtime capability.
    final capabilities = _buildDeclaredCapabilities(decoded);
    final docs = <TermsDocument>[];
    final verifiedText = <String, String>{};
    final terms = decoded['terms'] as List;
    final declaredTermsFiles = files.entries
        .where((entry) => entry.value['role'] == 'terms')
        .map((entry) => entry.key)
        .toSet();
    final referencedTermsFiles = terms
        .map((item) => (item as Map<String, dynamic>)['text_file'] as String)
        .toSet();
    if (!referencedTermsFiles.containsAll(declaredTermsFiles)) {
      throw const FormatException('Unreferenced terms file');
    }
    var totalTermsBytes = 0;
    for (final path in referencedTermsFiles) {
      final size = files[path]!['size_bytes'] as int;
      if (size > maxTermsBytes || size > maxTotalTermsBytes - totalTermsBytes) {
        throw const FormatException('Terms size limit exceeded');
      }
      totalTermsBytes += size;
    }
    for (final item in terms) {
      final entry = item as Map<String, dynamic>;
      final path = entry['text_file'] as String;
      final expected = entry['text_sha256'] as String;
      final binding = files[path]!;
      final size = binding['size_bytes'] as int;
      if (size > maxTermsBytes) throw const FormatException('Terms too large');
      var text = verifiedText[path];
      if (text == null) {
        final bytes = await reader.readDirectoryFile(path, size);
        if (bytes == null ||
            bytes.length != size ||
            sha256.convert(bytes).toString() != expected) {
          throw const FormatException('Terms integrity failure');
        }
        text = utf8.decode(bytes, allowMalformed: false);
        verifiedText[path] = text;
      }
      docs.add(
        TermsDocument(
          entry['id'] as String,
          text,
          List<String>.unmodifiable(
            (entry['usage_requirements'] as List).cast<String>(),
          ),
          List<String>.unmodifiable(
            (entry['required_attributions'] as List).cast<String>(),
          ),
        ),
      );
    }
    // The reviewer runs only after all unique terms files verify.
    final digestPaths = verifiedText.keys.toList()..sort();
    final digestEntries = digestPaths.map((path) {
      final digest = files[path]!['sha256'] as String;
      return '$path:$digest:${sha256.convert(utf8.encode(verifiedText[path]!))}';
    });
    final declaredFiles = <DeclaredModelFile>[];
    for (final entry in files.entries) {
      if (entry.value['role'] == 'terms') continue;
      declaredFiles.add(
        DeclaredModelFile(
          path: entry.key,
          role: entry.value['role'] as String,
          sizeBytes: entry.value['size_bytes'] as int,
          sha256: entry.value['sha256'] as String,
        ),
      );
    }
    final review = VerifiedTerms(
      modelId: decoded['id'] as String,
      modelName: decoded['display_name'] as String,
      publisher: decoded['publisher'] as String,
      documents: List.unmodifiable(docs),
      verifiedTermsFileCount: verifiedText.length,
      manifestDigest: sha256.convert(manifestBytes).toString(),
      termsDigest: sha256
          .convert(utf8.encode(digestEntries.join('\n')))
          .toString(),
      declaredFiles: List.unmodifiable(declaredFiles),
      capabilities: capabilities,
    );
    if (!await reviewer(review)) return null;
    return EphemeralModelAuthorization(
      review.manifestDigest,
      review.termsDigest,
      review.declaredFiles,
    );
  }
}

/// Copies the already-validated manifest capability declarations into a typed
/// snapshot. Any unexpected shape fails closed before the reviewer runs.
/// The snapshot reports manifest-DECLARED values only: not verified support,
/// availability or quality; a matching digest or declared route proves nothing
/// about origin or runtime capability.
DeclaredModelCapabilities _buildDeclaredCapabilities(
  Map<String, dynamic> manifest,
) {
  try {
    final executor = manifest['executor'] as Map<String, dynamic>;
    final resources = manifest['resources'] as Map<String, dynamic>;
    final tasks = (manifest['tasks'] as List).map((item) {
      final task = item as Map<String, dynamic>;
      final languages = task['languages'] as Map<String, dynamic>;
      final routes = (languages['routes'] as List).map((item) {
        final route = item as Map<String, dynamic>;
        final evidence = parseDeclaredRouteEvidence(
          route['evidence'] as String,
        );
        if (evidence == null) {
          throw const FormatException('Invalid capability declarations');
        }
        return DeclaredRoute(
          source: _requireLanguageTag(
            route['source'] as String,
            'route source',
          ),
          target: _requireLanguageTag(
            route['target'] as String,
            'route target',
          ),
          evidence: evidence,
          evidenceRef: route['evidence_ref'] as String?,
        );
      }).toList();
      return DeclaredTaskCapability(
        id: task['capability'] as String,
        inputTypes: List<String>.unmodifiable(
          (task['input_types'] as List).cast<String>(),
        ),
        outputTypes: List<String>.unmodifiable(
          (task['output_types'] as List).cast<String>(),
        ),
        sourceLanguages: List<String>.unmodifiable(
          (languages['source'] as List).map(
            (tag) => _requireLanguageTag(tag as String, 'language tag'),
          ),
        ),
        targetLanguages: List<String>.unmodifiable(
          (languages['target'] as List).map(
            (tag) => _requireLanguageTag(tag as String, 'language tag'),
          ),
        ),
        scripts: List<String>.unmodifiable(
          (languages['scripts'] as List).cast<String>(),
        ),
        routes: List<DeclaredRoute>.unmodifiable(routes),
      );
    }).toList();
    return DeclaredModelCapabilities(
      modelId: manifest['id'] as String,
      engineId: executor['engine_id'] as String,
      adapterId: executor['adapter_id'] as String,
      tasks: List<DeclaredTaskCapability>.unmodifiable(tasks),
      requiredCapabilities: List<String>.unmodifiable(
        (executor['required_capabilities'] as List).cast<String>(),
      ),
      resources: DeclaredResourceNeeds(
        storageBytes: resources['storage_bytes'] as int,
        peakHostBytes: resources['peak_host_bytes'] as int,
        peakAcceleratorBytes: resources['peak_accelerator_bytes'] as int,
        basis: resources['basis'] as String,
        conditions: resources['conditions'] as String,
      ),
    );
  } catch (_) {
    throw const FormatException('Invalid capability declarations');
  }
}

final RegExp _idPattern = RegExp(r'^[a-z][a-z0-9._-]*$');
final RegExp _shaPattern = RegExp(r'^[a-f0-9]{64}$');
const Set<String> _fileRoles = {
  'weights',
  'tokenizer',
  'vocabulary',
  'configuration',
  'terms',
  'auxiliary',
};

Never _invalid(String detail) {
  throw FormatException(detail);
}

/// Validates a manifest language tag with the same structural parser the
/// application uses and returns its lowercase canonical form. Registry checks
/// are deliberately not performed here.
String _requireLanguageTag(String entry, String context) {
  if (entry.trim() != entry) _invalid('Invalid $context');
  final tag = LanguageTag.parse(entry);
  if (tag == null) _invalid('Invalid $context');
  return tag.canonical.toLowerCase();
}

void _requireKeys(
  Map<String, dynamic> map,
  Set<String> required,
  Set<String> allowed,
  String context,
) {
  for (final key in required) {
    if (!map.containsKey(key)) _invalid('Missing $context.$key');
  }
  for (final key in map.keys) {
    if (!allowed.contains(key)) _invalid('Unexpected $context.<rejected>');
  }
}

void _requireIdString(Object? value, String context) {
  if (value is! String || !_idPattern.hasMatch(value)) {
    _invalid('Invalid $context');
  }
}

void _requireNonEmptyString(Object? value, String context) {
  if (value is! String || value.isEmpty) _invalid('Invalid $context');
}

/// `jsonDecode` turns 0.0 and integers beyond int64 into doubles; never
/// round those into a byte count.
void _requireByteCount(Object? value, int minimum, String context) {
  if (value is! int || value < minimum || value > _maxByteCount) {
    _invalid('Invalid $context');
  }
}

void _requireStringList(
  Object? value,
  String context, {
  bool allowEmpty = true,
}) {
  if (value is! List) _invalid('Invalid $context');
  final list = value;
  if (!allowEmpty && list.isEmpty) _invalid('Invalid $context');
  for (final entry in list) {
    if (entry is! String || entry.isEmpty) _invalid('Invalid $context');
  }
}

void _requireUniqueStrings(List list, String context) {
  if (list.toSet().length != list.length) _invalid('Duplicate $context');
}

/// Returns the validated `files` table keyed by exact path.
Map<String, Map<String, dynamic>> _validateManifest(
  Map<String, dynamic> manifest,
) {
  _requireKeys(
    manifest,
    const {
      'id',
      'display_name',
      'publisher',
      'files',
      'executor',
      'tasks',
      'resources',
      'terms',
    },
    const {
      'id',
      'display_name',
      'publisher',
      'files',
      'executor',
      'tasks',
      'resources',
      'terms',
    },
    'manifest',
  );
  _requireIdString(manifest['id'], 'manifest.id');
  _requireNonEmptyString(manifest['display_name'], 'manifest.display_name');
  _requireNonEmptyString(manifest['publisher'], 'manifest.publisher');

  final filesRaw = manifest['files'];
  if (filesRaw is! List || filesRaw.isEmpty) _invalid('Invalid files');
  final files = <String, Map<String, dynamic>>{};
  final foldedPaths = <String>{};
  for (final item in filesRaw) {
    if (item is! Map<String, dynamic>) _invalid('Invalid file entry');
    _requireKeys(
      item,
      const {'path', 'role', 'sha256', 'size_bytes'},
      const {'path', 'role', 'sha256', 'size_bytes'},
      'files entry',
    );
    final path = item['path'];
    if (path is! String || !_safePath(path)) _invalid('Invalid file path');
    if (files.containsKey(path)) _invalid('Duplicate file path');
    // Reject case collisions that distinct OS filesystems would conflate.
    if (!foldedPaths.add(path.toLowerCase())) {
      _invalid('Duplicate file path');
    }
    if (item['role'] is! String || !_fileRoles.contains(item['role'])) {
      _invalid('Invalid file role');
    }
    if (item['sha256'] is! String ||
        !_shaPattern.hasMatch(item['sha256'] as String)) {
      _invalid('Invalid file digest');
    }
    _requireByteCount(item['size_bytes'], 1, 'file size');
    files[path] = item;
  }

  final executor = manifest['executor'];
  if (executor is! Map<String, dynamic>) _invalid('Invalid executor');
  _requireKeys(
    executor,
    const {'engine_id', 'adapter_id', 'required_capabilities'},
    const {'engine_id', 'adapter_id', 'required_capabilities'},
    'executor',
  );
  _requireIdString(executor['engine_id'], 'executor.engine_id');
  _requireIdString(executor['adapter_id'], 'executor.adapter_id');
  if (executor['required_capabilities'] is! List ||
      (executor['required_capabilities'] as List).isEmpty) {
    _invalid('Invalid required capabilities');
  }
  final capabilities = executor['required_capabilities'] as List;
  for (final cap in capabilities) {
    _requireIdString(cap, 'required capability');
  }
  _requireUniqueStrings(capabilities, 'required capability');
  final requiredCaps = capabilities.cast<String>().toSet();

  final tasksRaw = manifest['tasks'];
  if (tasksRaw is! List || tasksRaw.isEmpty) _invalid('Invalid tasks');
  final seenCaps = <String>{};
  for (final item in tasksRaw) {
    if (item is! Map<String, dynamic>) _invalid('Invalid task entry');
    _requireKeys(
      item,
      const {'capability', 'input_types', 'output_types', 'languages'},
      const {'capability', 'input_types', 'output_types', 'languages'},
      'task',
    );
    _requireIdString(item['capability'], 'task.capability');
    final cap = item['capability'] as String;
    if (!seenCaps.add(cap)) _invalid('Duplicate task capability');
    if (!requiredCaps.contains(cap)) {
      _invalid('Task capability missing from executor');
    }
    for (final key in ['input_types', 'output_types']) {
      if (item[key] is! List || (item[key] as List).isEmpty) {
        _invalid('Invalid task.$key');
      }
      final list = item[key] as List;
      for (final entry in list) {
        _requireIdString(entry, 'task.$key');
      }
      _requireUniqueStrings(list, 'task.$key');
    }
    final languages = item['languages'];
    if (languages is! Map<String, dynamic>) _invalid('Invalid languages');
    _requireKeys(
      languages,
      const {'source', 'target', 'routes', 'scripts'},
      const {'source', 'target', 'routes', 'scripts'},
      'languages',
    );
    for (final side in ['source', 'target']) {
      if (languages[side] is! List) _invalid('Invalid languages.$side');
      final tags = languages[side] as List;
      for (final tag in tags) {
        if (tag is! String) _invalid('Invalid language tag');
      }
      final folded = tags
          .map((tag) => _requireLanguageTag(tag as String, 'language tag'))
          .toList();
      if (folded.toSet().length != folded.length) {
        _invalid('Duplicate language tag');
      }
    }
    if (languages['scripts'] is! List) _invalid('Invalid scripts');
    final scripts = languages['scripts'] as List;
    for (final script in scripts) {
      _requireNonEmptyString(script, 'script');
    }
    _requireUniqueStrings(scripts, 'script');
    if (languages['routes'] is! List) _invalid('Invalid routes');
    final routes = languages['routes'] as List;
    final sources = (languages['source'] as List)
        .map((tag) => _requireLanguageTag(tag as String, 'language tag'))
        .toSet();
    final targets = (languages['target'] as List)
        .map((tag) => _requireLanguageTag(tag as String, 'language tag'))
        .toSet();
    final pairs = <String>{};
    for (final route in routes) {
      if (route is! Map<String, dynamic>) _invalid('Invalid route');
      _requireKeys(
        route,
        const {'source', 'target', 'evidence'},
        const {'source', 'target', 'evidence', 'evidence_ref'},
        'route',
      );
      if (route['source'] is! String) _invalid('Invalid route source');
      if (route['target'] is! String) _invalid('Invalid route target');
      final routeSource = _requireLanguageTag(
        route['source'] as String,
        'route source',
      );
      final routeTarget = _requireLanguageTag(
        route['target'] as String,
        'route target',
      );
      if (route['evidence'] is! String ||
          !const {
            'provider',
            'evaluation',
            'user',
          }.contains(route['evidence'])) {
        _invalid('Invalid route evidence');
      }
      final pair = '$routeSource→$routeTarget';
      if (!pairs.add(pair)) _invalid('Duplicate language route');
      if (!sources.contains(routeSource)) _invalid('Unknown route source');
      if (!targets.contains(routeTarget)) _invalid('Unknown route target');
      if (route['evidence'] == 'evaluation') {
        _requireNonEmptyString(route['evidence_ref'], 'route.evidence_ref');
      } else if (route.containsKey('evidence_ref')) {
        _requireNonEmptyString(route['evidence_ref'], 'route.evidence_ref');
      }
    }
    if (routes.length != pairs.length) _invalid('Duplicate language route');
    if (cap.startsWith('translation.') && routes.isEmpty) {
      _invalid('Translation routes required');
    }
  }

  final resources = manifest['resources'];
  if (resources is! Map<String, dynamic>) _invalid('Invalid resources');
  _requireKeys(
    resources,
    const {
      'storage_bytes',
      'peak_host_bytes',
      'peak_accelerator_bytes',
      'basis',
      'conditions',
    },
    const {
      'storage_bytes',
      'peak_host_bytes',
      'peak_accelerator_bytes',
      'basis',
      'conditions',
    },
    'resources',
  );
  _requireByteCount(resources['storage_bytes'], 1, 'storage bytes');
  _requireByteCount(resources['peak_host_bytes'], 0, 'peak_host_bytes');
  _requireByteCount(
    resources['peak_accelerator_bytes'],
    0,
    'peak_accelerator_bytes',
  );
  if (resources['basis'] is! String ||
      !const {'declared', 'measured'}.contains(resources['basis'])) {
    _invalid('Invalid basis');
  }
  _requireNonEmptyString(resources['conditions'], 'resources.conditions');
  var total = 0;
  for (final entry in files.values) {
    final size = entry['size_bytes'] as int;
    if (size > _maxByteCount - total) _invalid('Storage total overflow');
    total += size;
  }
  if (total != resources['storage_bytes']) _invalid('Storage total mismatch');

  final termsRaw = manifest['terms'];
  if (termsRaw is! List || termsRaw.isEmpty) _invalid('Invalid terms');
  final termIds = <String>{};
  final coverage = <String>{};
  for (final item in termsRaw) {
    if (item is! Map<String, dynamic>) _invalid('Invalid terms entry');
    _requireKeys(
      item,
      const {
        'id',
        'text_file',
        'text_sha256',
        'consent',
        'usage_requirements',
        'required_attributions',
        'covered_files',
      },
      const {
        'id',
        'text_file',
        'text_sha256',
        'consent',
        'usage_requirements',
        'required_attributions',
        'covered_files',
      },
      'terms entry',
    );
    _requireIdString(item['id'], 'terms.id');
    if (!termIds.add(item['id'] as String)) _invalid('Duplicate terms id');
    final path = item['text_file'];
    if (path is! String || !_safePath(path)) _invalid('Invalid terms path');
    final expected = item['text_sha256'];
    if (expected is! String || !_shaPattern.hasMatch(expected)) {
      _invalid('Invalid terms digest');
    }
    if (item['consent'] != 'explicit') _invalid('Invalid terms consent');
    _requireStringList(item['usage_requirements'], 'usage_requirements');
    _requireStringList(item['required_attributions'], 'required_attributions');
    final covered = item['covered_files'];
    if (covered is! List || covered.isEmpty) _invalid('Invalid covered files');
    final coveredSet = <String>{};
    for (final entry in covered) {
      if (entry is! String || !_safePath(entry)) {
        _invalid('Invalid covered path');
      }
      if (!coveredSet.add(entry)) _invalid('Duplicate covered path');
      if (!files.containsKey(entry)) _invalid('Unknown covered file');
    }
    if (!coveredSet.contains(path)) _invalid('Terms must cover its own file');
    final binding = files[path];
    if (binding == null ||
        binding['role'] != 'terms' ||
        binding['sha256'] != expected) {
      _invalid('Terms file binding mismatch');
    }
    coverage.addAll(coveredSet);
  }
  if (coverage.length != files.length || !coverage.containsAll(files.keys)) {
    _invalid('Incomplete terms coverage');
  }
  return files;
}

bool _safePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
    return false;
  }
  // Deliberately ASCII-only: default APFS/macOS and Windows compare names
  // case- and normalization-insensitively, so canonically equivalent Unicode
  // spellings can collapse onto one on-disk entry.
  if (path.codeUnits.any((unit) => unit < 0x20 || unit > 0x7e) ||
      path.contains(RegExp(r'[<>:"|?*]'))) {
    return false;
  }
  const reserved = {'con', 'prn', 'aux', 'nul'};
  for (final part in path.split('/')) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith('.') ||
        part.endsWith(' ') ||
        part.contains(':')) {
      return false;
    }
    final base = part.split('.').first.toLowerCase();
    if (reserved.contains(base) || RegExp(r'^(com|lpt)[1-9]$').hasMatch(base)) {
      return false;
    }
  }
  return true;
}
