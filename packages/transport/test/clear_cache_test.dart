import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/fakes/fake_repositories.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';
import 'package:transport/src/cache/cache_budget.dart';

// Active native windows are protected individually; crash orphans remain reclaimable.

void main() {
  test(
    'cache ownership keeps active staging and reclaims orphan staging',
    () async {
      final cache = await Directory.systemTemp.createTemp('staging-cache-');
      addTearDown(() => cache.delete(recursive: true));
      for (final name in ['aria2-window-active', 'aria2-window-orphan']) {
        final dir = await Directory('${cache.path}/$name').create();
        await File('${dir.path}/window.bin').writeAsBytes(Uint8List(4096));
      }
      final budget = CacheBudget(
        dir: cache,
        fs: FsNative(),
        logger: MemoryLogger(),
        state: null,
        openNames: () => {'aria2-window-active'},
        openKeys: () => {},
      );
      expect(
        (await budget.closedEntries()).map(
          (e) => e.entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
        ),
        ['aria2-window-orphan'],
      );
      await budget.clear();
      expect(
        await Directory('${cache.path}/aria2-window-active').exists(),
        isTrue,
      );
      expect(
        await Directory('${cache.path}/aria2-window-orphan').exists(),
        isFalse,
      );
    },
  );
  test(
    'clearCache deletes closed-stream files and state, returns freed bytes',
    () async {
      final cache = await Directory.systemTemp.createTemp('clear-cache-');
      addTearDown(() => cache.delete(recursive: true));
      await File('${cache.path}/keep.txt').writeAsBytes(Uint8List(7));
      await File('${cache.path}/a.partial').writeAsBytes(Uint8List(1000));
      await File('${cache.path}/a.partial.aria2').writeAsBytes(Uint8List(24));
      await File('${cache.path}/a.partial.evicted').writeAsString('1');
      await Directory('${cache.path}/show').create();
      await File('${cache.path}/show/e1.mkv').writeAsBytes(Uint8List(500));
      final state = FakeTransportStateRepository();
      final http = SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1:1/a'),
      );
      final torrent = SourceSpec(
        kind: SourceKind.torrentMagnet,
        uri: Uri.parse('magnet:?xt=urn:btih:clear'),
      );
      for (final spec in [http, torrent]) {
        await state.upsert(
          DownloadRecord(
            sourceKey: deriveSourceKey(spec),
            kind: spec.kind,
            filePath: spec == torrent ? '${cache.path}/show/e1.mkv' : null,
            lastUsedAt: DateTime.now().toUtc(),
          ),
        );
      }
      await state.putTorrentResumeData(
        deriveSourceKey(torrent),
        Uint8List.fromList([1]),
      );
      final source = StreamSourceImpl(
        logger: MemoryLogger(),
        cacheDir: cache,
        state: state,
      );

      expect(await source.clearCache(), 1525);
      expect(cache.listSync().map((e) => e.uri.pathSegments.last), [
        'keep.txt',
      ]);
      expect(await state.all(), isEmpty);
      expect(await state.torrentResumeData(deriveSourceKey(torrent)), isEmpty);
      await source.dispose();
    },
  );
}
