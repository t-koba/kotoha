/// Output budget for editor operations that grow text.
///
/// The unit is UTF-16 code units, matching Dart string lengths. This is
/// deployment policy rather than a document-format limit: callers pass it to the
/// operation so other configurations can choose a different budget. Deployments
/// can override the default at build time with
/// `--dart-define=KOTOHA_REPLACE_ALL_OUTPUT_LIMIT=<code units>`.
const int replaceAllOutputLimit = int.fromEnvironment(
  'KOTOHA_REPLACE_ALL_OUTPUT_LIMIT',
  defaultValue: 8 * 1024 * 1024,
);
