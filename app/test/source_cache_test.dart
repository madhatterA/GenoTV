import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/source_cache.dart';

final class _Provider implements SourceProvider {
  int calls = 0;
  @override
  String get id => 'ccloud';
  @override
  String get displayName => 'CCloud';
  @override
  Future<MediaPage> browse(BrowseQuery query) async =>
      MediaPage(items: [], hasMore: false);
  @override
  Future<MediaPage> search(String query, {int limit = 50}) async =>
      MediaPage(items: [], hasMore: false);
  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async {
    calls++;
    return <SourceSpec>[
      SourceSpec(
        kind: SourceKind.hlsUrl,
        uri: Uri.parse('https://a/master.m3u8'),
        headers: const {'Referer': 'https://a/'},
        quality: '1080p',
        label: 'Site: Movy\nMovy 1080p',
        fileHint: 'Movy 1080p',
      ),
    ];
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  const movie = MediaItem(id: 'tmdb:1', title: 'M', kind: MediaKind.movie);

  test(
    'saved list is reused, forget reloads, 7-day-old list expires',
    () async {
      final dir = Directory.systemTemp.createTempSync('source_cache_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final cache = SourceCache(dir, MemoryLogger());
      final inner = _Provider();
      final provider = CachedSourceProvider(inner, cache);

      final first = await provider.resolve(movie);
      final second = await provider.resolve(movie);
      expect(inner.calls, 1);
      expect(second.single.uri, first.single.uri);
      expect(second.single.headers, {'Referer': 'https://a/'});
      expect(second.single.label, 'Site: Movy\nMovy 1080p');
      expect(second.single.kind, SourceKind.hlsUrl);

      await cache.forget('ccloud', movie);
      await provider.resolve(movie);
      expect(inner.calls, 2);

      final file = dir.listSync().whereType<File>().single;
      file.setLastModifiedSync(
        DateTime.now().subtract(const Duration(days: 8)),
      );
      await provider.resolve(movie);
      expect(inner.calls, 3);
    },
  );
}
