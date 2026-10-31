import 'dart:convert';

import 'app_database.dart';

/// The small tables that must survive a tvOS Caches purge, as one JSON string.
/// Downloads and torrent resume data are large and re-creatable, so they are not mirrored.
const _tables = <String, List<String>>{
  'playback_progress': [
    'media_id',
    'position_ms',
    'duration_ms',
    'updated_at',
    'completed',
    'audio_track_id',
    'subtitle_track_id',
    'last_played_source_key',
  ],
  'favourites': ['media_id', 'added_at'],
  'next_up': ['series_id', 'media_id', 'season', 'episode', 'updated_at'],
};

Future<String> exportMirror(AppDatabase db) async {
  final out = <String, Object?>{};
  for (final table in _tables.keys) {
    final rows = await db.customSelect('SELECT * FROM $table').get();
    out[table] = [for (final row in rows) row.data];
  }
  return jsonEncode(out);
}

/// Inserts the mirrored rows into an empty database (existing rows win).
Future<void> importMirror(AppDatabase db, String json) async {
  final data = jsonDecode(json) as Map<String, Object?>;
  await db.transaction(() async {
    for (final entry in _tables.entries) {
      final rows = (data[entry.key] as List?) ?? const [];
      for (final row in rows.cast<Map<String, Object?>>()) {
        final columns = entry.value;
        await db.customStatement(
          'INSERT OR IGNORE INTO ${entry.key} (${columns.join(',')}) '
          'VALUES (${List.filled(columns.length, '?').join(',')})',
          [for (final c in columns) row[c]],
        );
      }
    }
  });
}
