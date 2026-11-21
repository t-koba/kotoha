/// Default output budget for editor operations that grow text.
///
/// The unit is UTF-16 code units, matching Dart string lengths. This is
/// runtime policy rather than a document-format limit: callers pass it to the
/// operation so other configurations can choose a different budget.
const int replaceAllOutputLimit = 8 * 1024 * 1024;
