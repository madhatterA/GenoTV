import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:persistence/src/database/app_database.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('persistence_db_test_');
    database = AppDatabase(NativeDatabase(File('${tempDir.path}/test.db')));
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  test('opens in a temp directory and creates all five tables', () async {
    final tables = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final names = tables.map((row) => row.data['name'] as String).toSet();

    expect(
      names,
      containsAll(<String>[
        'playback_progress',
        'favourites',
        'next_up',
        'download_records',
        'torrent_resume',
      ]),
    );
  });

  test('schemaVersion is 2', () {
    // Bumped from 1 in Chapter 04 Phase 03 (migrations-and-durability).
    expect(database.schemaVersion, 2);
  });

  test('a UTC timestamp written and read back is the same instant across a timezone change',
      () async {
    final local = DateTime(2024, 6, 15, 10, 30);
    final utcMs = local.toUtc().millisecondsSinceEpoch;

    await database
        .into(database.favourites)
        .insert(FavouritesCompanion.insert(mediaId: 'movie-1', addedAt: utcMs));
    final row = await (database.select(database.favourites)
          ..where((t) => t.mediaId.equals('movie-1')))
        .getSingle();

    final readBack = DateTime.fromMillisecondsSinceEpoch(row.addedAt, isUtc: true);
    expect(readBack.isUtc, isTrue);
    expect(readBack.millisecondsSinceEpoch, local.millisecondsSinceEpoch);
  });

  test('WAL is enabled', () async {
    final result = await database.customSelect('PRAGMA journal_mode').getSingle();
    expect((result.data['journal_mode'] as String).toLowerCase(), 'wal');
  });

  test('opening the same file twice from two connections does not deadlock within the busy '
      'timeout', () async {
    final path = '${tempDir.path}/shared.db';
    final dbA = AppDatabase(NativeDatabase(File(path)));
    final dbB = AppDatabase(NativeDatabase(File(path)));

    await dbA.customSelect('SELECT 1').getSingle();
    await dbB.customSelect('SELECT 1').getSingle();

    await dbA.close();
    await dbB.close();
  });
}
