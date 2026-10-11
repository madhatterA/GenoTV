import 'dart:convert';
import 'dart:io';

import 'package:cast/src/core/media_proxy.dart';
import 'package:cast/src/utils/logger.dart';
import 'package:test/test.dart';

/// Phase 09 ch01 p02 proof: the cast proxy injects provider headers, forwards
/// Range, rewrites every playlist URL to itself and refuses to fetch anything
/// a playlist did not name. Set CAST_PROXY_ACCESS_LOG to a file path to write
/// the proxy access log for the evidence directory.
void main() {
  late MediaProxy proxy;
  late HttpServer upstream;
  late HttpServer foreign;
  late String up;
  final upstreamSeen = <String>[]; // "METHOD path referer-present range"
  final foreignHits = <String>[];
  final access = <String>[];
  const secret = 'Bearer s3cret-token';
  final media = List<int>.generate(100, (i) => i);

  setUp(() async {
    upstreamSeen.clear();
    foreignHits.clear();
    access.clear();
    CastLogger.setCallback((level, message) {
      final first = message.split('\n').first;
      if (first.startsWith('MediaProxy: GET ') ||
          first.startsWith('MediaProxy: upstream ')) {
        access.add(first);
      }
    });
    upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    up = 'http://127.0.0.1:${upstream.port}';
    upstream.listen((r) async {
      final authed =
          r.headers.value('Referer') == 'https://provider.example' &&
          r.headers.value('Authorization') == secret;
      upstreamSeen.add(
        '${r.method} ${r.uri.path} authed=$authed '
        'range=${r.headers.value('Range') ?? '-'}',
      );
      if (!authed) {
        r.response.statusCode = HttpStatus.forbidden;
      } else if (r.uri.path == '/movie.mp4') {
        final range = r.headers.value('Range');
        if (range != null) {
          final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
          final s = int.parse(m[1]!), e = int.parse(m[2]!);
          r.response.statusCode = HttpStatus.partialContent;
          r.response.headers.set(
            'Content-Range',
            'bytes $s-$e/${media.length}',
          );
          r.response.add(media.sublist(s, e + 1));
        } else {
          r.response.add(media);
        }
      } else if (r.uri.path == '/master.m3u8') {
        r.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        r.response.write(
          '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1000\nv/media.m3u8\n',
        );
      } else if (r.uri.path == '/v/media.m3u8') {
        r.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        r.response.write(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n'
          '#EXTINF:4,\nseg0.ts\n#EXTINF:4,\nhttp://127.0.0.1:${foreign.port}/cdn/seg1.ts\n#EXT-X-ENDLIST\n',
        );
      } else if (r.uri.path == '/v/seg0.ts') {
        r.response.add(List<int>.filled(188, 0));
      } else {
        r.response.statusCode = HttpStatus.notFound;
      }
      await r.response.close();
    });
    foreign = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    foreign.listen((r) async {
      foreignHits.add(
        '${r.uri.path} auth=${r.headers.value('Authorization') ?? '-'}',
      );
      r.response.add([1, 2, 3]);
      await r.response.close();
    });
    proxy = MediaProxy();
    await proxy.start();
  });

  tearDown(() async {
    CastLogger.setCallback(null);
    final path = Platform.environment['CAST_PROXY_ACCESS_LOG'];
    if (path != null) {
      File(path).writeAsStringSync(
        '--- test access log\n${access.join('\n')}\n'
        '--- upstream saw\n${upstreamSeen.join('\n')}\n'
        '--- foreign host saw\n${foreignHits.join('\n')}\n',
        mode: FileMode.append,
      );
    }
    await proxy.stop();
    await upstream.close(force: true);
    await foreign.close(force: true);
  });

  Future<(int, Map<String, String>, List<int>)> get(
    String url, {
    String? range,
  }) async {
    final c = HttpClient();
    try {
      final req = await c.getUrl(Uri.parse(url));
      if (range != null) req.headers.set('Range', range);
      final res = await req.close();
      final body = await res.fold<List<int>>([], (p, c) => p..addAll(c));
      final h = <String, String>{};
      res.headers.forEach((n, v) => h[n] = v.join(','));
      return (res.statusCode, h, body);
    } finally {
      c.close(force: true);
    }
  }

  String register(String path) => proxy.registerMedia(
    '$up$path',
    headers: {'Referer': 'https://provider.example', 'Authorization': secret},
  );

  test('serves on the LAN interface address, not a fixed port', () {
    expect(proxy.baseUrl, startsWith('http://'));
    expect(Uri.parse(proxy.baseUrl!).port, isNot(0));
  });

  test(
    'injects provider headers and the TV never sees the upstream URL',
    () async {
      final url = register('/movie.mp4');
      expect(url, isNot(contains('127.0.0.1:${upstream.port}')));
      final (status, _, body) = await get(url);
      expect(status, 200);
      expect(body, media);
      expect(upstreamSeen.single, contains('authed=true'));
    },
  );

  test('forwards Range and answers 206 with Content-Range', () async {
    final (status, headers, body) = await get(
      register('/movie.mp4'),
      range: 'bytes=10-19',
    );
    expect(status, 206);
    expect(headers['content-range'], 'bytes 10-19/100');
    expect(body, media.sublist(10, 20));
    expect(upstreamSeen.single, contains('range=bytes=10-19'));
  });

  test(
    'every playlist URL is rewritten to the proxy, at every level',
    () async {
      final (_, _, masterBody) = await get(register('/master.m3u8'));
      final master = utf8.decode(masterBody);
      final variant = master
          .split('\n')
          .firstWhere((l) => l.startsWith('http'));
      expect(variant, startsWith(proxy.baseUrl!));

      final (_, _, mediaBody) = await get(variant);
      final playlist = utf8.decode(mediaBody);
      final uris = [
        ...RegExp(r'URI="([^"]+)"').allMatches(playlist).map((m) => m[1]!),
        ...playlist
            .split('\n')
            .where((l) => l.isNotEmpty && !l.startsWith('#')),
      ];
      expect(uris, hasLength(3)); // key + 2 segments
      for (final u in uris) {
        expect(u, startsWith(proxy.baseUrl!));
      }
      expect(playlist, isNot(contains('http://127.0.0.1:${foreign.port}/')));

      // A segment on another host is fetched through the proxy with headers.
      final (status, _, _) = await get(uris.last);
      expect(status, 200);
      expect(foreignHits.single, '/cdn/seg1.ts auth=$secret');
    },
  );

  test('refuses a sub-resource URL no playlist named (no header leak)', () async {
    final url = register('/master.m3u8');
    await get(url); // playlist fetched, rewritten
    final (status, _, _) = await get(
      '$url?url=${Uri.encodeComponent('http://127.0.0.1:${foreign.port}/steal')}',
    );
    expect(status, 403);
    expect(foreignHits, isEmpty);
  });

  test('unknown token is 404', () async {
    final (status, _, _) = await get('${proxy.baseUrl}/stream/nope');
    expect(status, 404);
  });
}
