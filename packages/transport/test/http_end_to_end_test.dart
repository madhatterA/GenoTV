import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

void main() {
  test('HTTP source probes, serves ranges, and seeks to an uncached region', () async {
    final payload = List<int>.generate(4096, (index) => index % 251);
    final cache = await Directory.systemTemp.createTemp('transport-http-');
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serverSub = upstream.listen((request) async {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (request.method == 'HEAD') {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = payload.length;
        await request.response.close();
        return;
      }
      var start = 0;
      var end = payload.length - 1;
      if (range != null) {
        final parts = range.substring(6).split('-');
        start = int.parse(parts.first);
        end = int.parse(parts.last);
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set('Content-Range', 'bytes $start-$end/${payload.length}');
      }
      request.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = end - start + 1;
      request.response.add(payload.sublist(start, end + 1));
      await request.response.close();
    });
    final logger = MemoryLogger();
    final source = StreamSourceImpl(logger: logger, cacheDir: cache);
    try {
      final direct = RemoteHttpSparseSource(
        uri: Uri.parse('http://127.0.0.1:${upstream.port}/media.bin'),
        file: File('${Directory.systemTemp.path}/part03-direct-${upstream.port}.partial'),
        headers: const <String, String>{},
        totalBytes: payload.length,
      );
      await direct.waitFor(const ByteRange(100, 199));
      expect(await direct.read(const ByteRange(100, 199)).expand((chunk) => chunk).toList(), payload.sublist(100, 200));
      await direct.dispose();
      final handle = await source.open(SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1:${upstream.port}/media.bin'),
      ));
      // The facade registers the source; its first demand must land before
      // the range response can complete.
      expect(handle.playbackUri.host, '127.0.0.1');
      late List<int> first;
      late List<int> second;
      try {
        first = await _get(handle.playbackUri, 100, 199);
        second = await _get(handle.playbackUri, 3000, 3099);
      } catch (error) {
        fail('$error; transport logs: ${logger.records}');
      }
      expect(first, payload.sublist(100, 200));
      expect(second, payload.sublist(3000, 3100));
      // Live aria2 counters, read on demand.
      final stats = await (handle as TransportStatsProvider).readStats();
      expect(stats.totalBytes, payload.length);
      expect(stats.downloadedBytes, greaterThan(0));
      expect(stats.connections, isNotNull);
      expect(stats.torrent, isNull);
      await handle.dispose();
      await source.dispose();
    } finally {
      await serverSub.cancel();
      await upstream.close(force: true);
      await cache.delete(recursive: true);
    }
  });

  test('reopening an HTTP source reuses its persisted partial-file record', () async {
    final payload = List<int>.generate(32, (index) => index);
    final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sub = upstream.listen((request) async {
      if (request.method == 'HEAD') {
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = payload.length;
      } else {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final bounds = range == null ? const <int>[0, 31] : range.substring(6).split('-').map(int.parse).toList();
        final start = bounds[0];
        final end = bounds[1];
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers
          ..set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..contentLength = end - start + 1
          ..set('Content-Range', 'bytes $start-$end/${payload.length}');
        request.response.add(payload.sublist(start, end + 1));
      }
      await request.response.close();
    });
    final state = _MemoryTransportState();
    final cache = await Directory.systemTemp.createTemp('transport-http-persist-');
    final spec = SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse('http://127.0.0.1:${upstream.port}/x'));
    final source = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache, state: state);
    try {
      final handle = await source.open(spec);
      final first = await _get(handle.playbackUri, 0, 7);
      expect(first, payload.sublist(0, 8));
      await handle.dispose();
      expect(state.records, hasLength(1));
      final path = state.records.values.single.filePath;
      await source.dispose();
      final reopened = StreamSourceImpl(logger: MemoryLogger(), cacheDir: cache, state: state);
      final second = await reopened.open(spec);
      expect((await second.status.first).available.containsRange(const ByteRange(0, 7)), isTrue);
      await second.dispose();
      expect(state.records.values.single.filePath, path);
      await reopened.dispose();
    } finally {
      await sub.cancel();
      await upstream.close(force: true);
      await cache.delete(recursive: true);
    }
  });
}

final class _MemoryTransportState implements TransportStateRepository {
  final Map<String, DownloadRecord> records = <String, DownloadRecord>{};
  final Map<String, Uint8List> resume = <String, Uint8List>{};
  @override Future<DownloadRecord?> get(String sourceKey) async => records[sourceKey];
  @override Future<void> upsert(DownloadRecord record) async => records[record.sourceKey] = record;
  @override Future<List<DownloadRecord>> all() async => records.values.toList();
  @override Future<void> delete(String sourceKey) async => records.remove(sourceKey);
  @override Future<Uint8List?> torrentResumeData(String infoHash) async => resume[infoHash];
  @override Future<void> putTorrentResumeData(String infoHash, Uint8List data) async => resume[infoHash] = data;
}

Future<List<int>> _get(Uri uri, int start, int end) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
    final response = await request.close();
    expect(response.statusCode, HttpStatus.partialContent);
    return await response.fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  } finally {
    client.close(force: true);
  }
}
