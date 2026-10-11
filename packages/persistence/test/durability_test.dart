import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:persistence/persistence.dart';

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.supportPath);
  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;

  // drift_flutter's native connection helper also asks for a temp
  // directory (for sqlite3's own scratch files).
  @override
  Future<String?> getTemporaryPath() async => supportPath;
}

void main() {
  late Directory tempDir;
  late AppPaths paths;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('persistence_durability_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
    paths = AppPaths(logger: MemoryLogger());
    dbFile = File('${tempDir.path}/app.db');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('a corrupt file yields storage.corrupt on open, not an untyped exception', () async {
    dbFile.writeAsBytesSync(Uint8List.fromList(List.filled(64, 0xFF)));

    await expectLater(
      () => openDatabase(paths: paths),
      throwsA(isA<PersistenceFailure>().having((f) => f.code, 'code', 'storage.corrupt')),
    );
  });

  test(
      'recoverByRenaming() moves the bad file aside and opens a fresh one; '
      'nothing calls it automatically', () async {
    dbFile.writeAsBytesSync(Uint8List.fromList(List.filled(64, 0xFF)));

    // Confirm the failure is still there — nothing recovered it on its own.
    await expectLater(() => openDatabase(paths: paths), throwsA(isA<PersistenceFailure>()));
    expect(dbFile.existsSync(), isTrue);

    await recoverByRenaming(paths: paths);
    expect(dbFile.existsSync(), isFalse);

    final db = await openDatabase(paths: paths);
    expect(db.schemaVersion, 2);
    await db.close();
  });

  test('rows written and committed survive an abrupt reopen (no clean close)', () async {
    final db1 = await openDatabase(paths: paths);
    final repo1 = createFavouritesRepository(db1, MemoryLogger());
    await repo1.setFavourite('movie-1', true);
    // Deliberately no db1.close() — simulates the process being killed
    // right after a committed write, which WAL should still survive.

    final db2 = await openDatabase(paths: paths);
    final repo2 = createFavouritesRepository(db2, MemoryLogger());
    expect(await repo2.isFavourite('movie-1'), isTrue);
    await db2.close();
  });
}
