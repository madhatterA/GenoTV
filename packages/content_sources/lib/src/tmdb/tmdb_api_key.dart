import 'dart:io';

import '../session_file.dart';

/// The user's own TMDB API key (Settings > Title API > TMDB). Stored like the
/// SubDL/SubSource keys: a session file in the app's session directory.
/// [value] is read on every TMDB request; it is never logged.
class TmdbApiKey {
  TmdbApiKey(this._file);

  final File _file;

  /// The saved key, or null for the built-in behaviour (backup proxy).
  String? value;

  Future<void> load() async {
    try {
      value = await readSessionToken(_file, 'token');
    } on Object {
      value = null; // no saved key: built-in behaviour
    }
  }

  Future<void> save(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return clear();
    await writeSession(_file, {'token': trimmed});
    value = trimmed;
  }

  Future<void> clear() async {
    await deleteSession(_file);
    value = null;
  }
}
