import 'dart:convert';
import 'dart:typed_data';

import 'draft_envelope.dart';
import 'draft_file_store.dart';
import 'workspace.dart';

/// Composes the envelope and file layers into a full draft save/reopen path.
/// The caller supplies the key; this class never generates, stores, resets or
/// derives one. It is framing/composition only: no cryptography, filesystem,
/// native or cross-platform behavior is implemented or claimed here.
class DraftStore {
  DraftStore({
    required this.fileStore,
    required this.envelope,
    required this.key,
  });

  final DraftFileStore fileStore;
  final DraftEnvelopeCodec envelope;
  final Uint8List key;

  Future<void> save(TextWorkspaceDraft draft) async {
    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(draft.toJson())),
    );
    final sealed = envelope.seal(key: key, plaintext: plaintext);
    await fileStore.save(sealed);
  }

  /// Returns null when nothing has been saved. Authentication, file and format
  /// failures propagate to the caller as the typed exceptions of the layers.
  Future<TextWorkspaceDraft?> load() async {
    final sealed = await fileStore.load();
    if (sealed == null) return null;
    final plaintext = envelope.open(key: key, envelope: sealed);
    return TextWorkspaceDraft.fromJson(jsonDecode(utf8.decode(plaintext)));
  }
}
