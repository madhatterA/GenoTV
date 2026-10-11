import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// One recorded request.
typedef Hit = ({String method, String path, Map<String, String> headers});

class _Server {
  _Server._(this.server);
  final HttpServer server;
  final List<Hit> hits = [];
  final List<String> aborted = [];
  Future<void> Function(HttpRequest request)? handle;

  static Future<_Server> start() async {
    final s = _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s.server.listen((request) async {
      final headers = <String, String>{};
      request.headers.forEach((k, v) => headers[k] = v.join(','));
      s.hits.add((
        method: request.method,
        path: request.uri.toString(),
        headers: headers,
      ));
      unawaited(
        request.response.done.then<void>(
          (_) {},
          onError: (Object _) => s.aborted.add(request.uri.path),
        ),
      );
      await (s.handle ?? _ok)(request);
    });
    return s;
  }

  static Future<void> _ok(HttpRequest r) async {
    r.response.write('ok');
    await r.response.close();
  }

  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');
  List<Hit> where(String method) =>
      hits.where((h) => h.method == method).toList();
}

void main() {
  late _Server direct;
  late _Server proxy;
  late BackupRouter router;
  late HttpClient client;

  setUp(() async {
    direct = await _Server.start();
    proxy = await _Server.start();
    // Production maps https targets with proxyUriFor; local http targets
    // keep host:port in the first segment the same way.
    router = BackupRouter(
      proxy: proxy.origin,
      deadline: const Duration(milliseconds: 300),
      proxyUriOf: (t) => Uri.parse(
        '${proxy.origin}/${t.authority}${t.path}${t.hasQuery ? '?${t.query}' : ''}',
      ),
    );
    client = HttpClient();
  });

  tearDown(() async {
    client.close(force: true);
    await direct.server.close(force: true);
    await proxy.server.close(force: true);
  });

  Future<(int, String)> get(Uri uri, [Map<String, String> h = const {}]) async {
    final r = await router.send(client, 'GET', uri, h);
    return (r.statusCode, await utf8.decodeStream(r));
  }

  test('production mapping: host first, raw query kept, port 2053', () {
    expect(
      proxyUriFor(
        Uri.parse('https://api.themoviedb.org/3/movie/123?language=fa-IR'),
      ).toString(),
      'https://genotv.cubernets.com:2053/api.themoviedb.org/3/movie/123?language=fa-IR',
    );
    expect(proxyUriFor(Uri.parse('http://cdntmp.x.ir/a')), isNull);
    expect(proxyUriFor(Uri.parse('https://x.com:8443/a')), isNull);
  });

  test('TMDb/OMDb go only to the proxy, with no key', () async {
    final tmdbRouter = BackupRouter(
      proxy: proxy.origin,
      proxyUriOf: (t) =>
          Uri.parse('${proxy.origin}/${t.host}${t.path}?${t.query}'),
    );
    for (final target in [
      'https://api.themoviedb.org/3/movie/1?language=en-US',
      'https://www.omdbapi.com/?i=tt1',
    ]) {
      final r = await tmdbRouter.send(client, 'GET', Uri.parse(target), {});
      await r.drain<void>();
    }
    expect(proxy.hits.map((h) => h.path), [
      '/api.themoviedb.org/3/movie/1?language=en-US',
      '/www.omdbapi.com/?i=tt1',
    ]);
    for (final h in proxy.hits) {
      expect(h.path, isNot(matches(RegExp('api_?key', caseSensitive: false))));
      expect(h.headers.containsKey('authorization'), isFalse);
    }
  });

  test('direct success under the deadline: no proxy call', () async {
    expect(await get(direct.origin.resolve('/a?x=1')), (200, 'ok'));
    expect(direct.hits.single.path, '/a?x=1');
    expect(proxy.hits, isEmpty);
  });

  test('direct DNS failure: exactly one proxy call', () async {
    final target = Uri.parse('http://no-such-host.invalid/p?q=1');
    expect(await get(target), (200, 'ok'));
    expect(proxy.hits.single.path, '/no-such-host.invalid/p?q=1');
  });

  test('connection refused: exactly one proxy call', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    expect(await get(Uri.parse('http://127.0.0.1:$port/z')), (200, 'ok'));
    expect(proxy.hits, hasLength(1));
  });

  test(
    'connect hang (accepts, never answers): cancelled, one proxy call',
    () async {
      final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final closed = Completer<void>();
      silent.listen(
        (socket) => socket.listen(
          (_) {},
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
        ),
      );
      addTearDown(silent.close);
      final watch = Stopwatch()..start();
      expect(await get(Uri.parse('http://127.0.0.1:${silent.port}/h')), (
        200,
        'ok',
      ));
      expect(watch.elapsedMilliseconds, lessThan(2000));
      expect(proxy.hits, hasLength(1));
      await closed.future.timeout(const Duration(seconds: 2));
    },
  );

  test('slow headers past the deadline: first request aborted, one proxy call', () async {
    // Answers only after 800 ms (deadline 300 ms); records the client closing.
    final slow = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(slow.close);
    final closedEarly = Completer<bool>();
    slow.listen((socket) {
      final timer = Timer(const Duration(milliseconds: 800), () {
        socket.write('HTTP/1.1 200 OK\r\ncontent-length: 4\r\n\r\nlate');
        if (!closedEarly.isCompleted) closedEarly.complete(false);
      });
      socket.listen(
        (_) {},
        onDone: () {
          timer.cancel();
          if (!closedEarly.isCompleted) closedEarly.complete(true);
        },
        onError: (Object _) {},
      );
    });
    expect(await get(Uri.parse('http://127.0.0.1:${slow.port}/slow')), (
      200,
      'ok',
    ));
    expect(proxy.hits, hasLength(1));
    expect(
      await closedEarly.future.timeout(const Duration(seconds: 2)),
      isTrue,
    );
  });

  test('direct 404, 401 and 503 are real answers: no proxy call', () async {
    for (final status in [404, 401, 503]) {
      direct.handle = (r) async {
        r.response.statusCode = status;
        await r.response.close();
      };
      expect((await get(direct.origin.resolve('/e'))).$1, status);
    }
    expect(proxy.hits, isEmpty);
  });

  test(
    'POST reachable direct: HEAD probe, POST once, never to the proxy',
    () async {
      final r = await router.send(
        client,
        'POST',
        direct.origin.resolve('/login'),
        {},
        body: utf8.encode('a=1'),
      );
      await r.drain<void>();
      expect(direct.where('POST'), hasLength(1));
      expect(direct.where('HEAD'), hasLength(1));
      expect(proxy.hits, isEmpty);
    },
  );

  test('POST unreachable direct: sent once, only via the proxy', () async {
    final r = await router.send(
      client,
      'POST',
      Uri.parse('http://no-such-host.invalid/login'),
      {},
      body: utf8.encode('a=1'),
    );
    await r.drain<void>();
    expect(proxy.where('POST'), hasLength(1));
    expect(proxy.hits, hasLength(1));
  });

  test('POST that times out after sending is not replayed', () async {
    direct.handle = (r) async {
      if (r.method == 'POST') {
        await Future<void>.delayed(const Duration(seconds: 3));
      }
      await r.response.close();
    };
    final slowRouter = BackupRouter(
      proxy: proxy.origin,
      proxyUriOf: (t) => Uri.parse('${proxy.origin}/${t.authority}${t.path}'),
    );
    // The POST itself gets the normal route timeout; shorten it by cancelling.
    final sending = slowRouter.send(
      client,
      'POST',
      direct.origin.resolve('/pay'),
      {},
      body: utf8.encode('x'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 500));
    client.close(force: true);
    await expectLater(sending, throwsA(anything));
    expect(direct.where('POST'), hasLength(1));
    expect(proxy.hits, isEmpty);
  });

  test(
    'same-origin redirect from the proxy maps back; each hop routes itself',
    () async {
      proxy.handle = (r) async {
        if (r.uri.path.endsWith('/start')) {
          // The proxy rewrites a same-origin Location to its own path.
          r.response
            ..statusCode = 302
            ..headers.set('location', '/no-such-host.invalid/next?k=v');
        } else {
          r.response.write('proxied ${r.uri.path}');
        }
        await r.response.close();
      };
      final (status, body) = await get(
        Uri.parse('http://no-such-host.invalid/start'),
      );
      expect(status, 200);
      expect(body, 'proxied /no-such-host.invalid/next');
      // Second hop tried direct again (DNS fails) before the proxy.
      expect(proxy.hits.map((h) => h.path), [
        '/no-such-host.invalid/start',
        '/no-such-host.invalid/next?k=v',
      ]);
    },
  );

  test(
    'cross-origin redirect drops credentials; same-origin keeps them',
    () async {
      final other = await _Server.start();
      addTearDown(() => other.server.close(force: true));
      direct.handle = (r) async {
        if (r.uri.path == '/a') {
          r.response
            ..statusCode = 302
            ..headers.set('location', '/b');
        } else {
          r.response
            ..statusCode = 302
            ..headers.set('location', '${other.origin}/c');
        }
        await r.response.close();
      };
      final (status, _) = await get(direct.origin.resolve('/a'), {
        'Authorization': 'Bearer secret',
        'Cookie': 's=1',
        'Referer': 'https://provider.example/',
      });
      expect(status, 200);
      expect(direct.hits[1].headers['authorization'], 'Bearer secret');
      final crossed = other.hits.single.headers;
      expect(crossed.containsKey('authorization'), isFalse);
      expect(crossed.containsKey('cookie'), isFalse);
      expect(crossed['referer'], 'https://provider.example/');
      expect(proxy.hits, isEmpty);
    },
  );

  test('relative links resolve to the provider, not the proxy', () async {
    proxy.handle = (r) async {
      r.response.write('<a href="/movie/1">x</a>');
      await r.response.close();
    };
    final page = Uri.parse('http://no-such-host.invalid/search?q=a');
    final http = ProviderHttp(null, router);
    final html = await http.getText(page);
    final href = RegExp('href="([^"]+)"').firstMatch(html!)![1]!;
    // Body unchanged; callers resolve against the provider URL they asked for.
    expect(
      page.resolve(href).toString(),
      'http://no-such-host.invalid/movie/1',
    );
    http.close();
  });

  test('media URLs and Range requests never reach the proxy', () async {
    for (final (path, headers) in [
      ('/film.mkv', const <String, String>{}),
      ('/live/index.m3u8', const <String, String>{}),
      ('/seg-1.ts', const <String, String>{}),
      ('/file', const {'Range': 'bytes=0-1'}),
    ]) {
      await expectLater(
        router.send(
          client,
          'GET',
          Uri.parse('http://127.0.0.1:1$path'),
          headers,
        ),
        throwsA(isA<SocketException>()),
      );
    }
    expect(proxy.hits, isEmpty);
    expect(
      isMediaRequest(Uri.parse('https://a/b.MP4?md5=1'), const {}),
      isTrue,
    );
    expect(
      isMediaRequest(Uri.parse('https://a/api/x'), const {'if-range': 'x'}),
      isTrue,
    );
    expect(
      isMediaRequest(Uri.parse('https://a/api/x.json'), const {}),
      isFalse,
    );
  });

  test('package:http client (Playtorrio) uses the same routing', () async {
    final routed = RoutedHttpClient(router: router);
    final response = await http.runWithClient(
      () => http.get(Uri.parse('http://no-such-host.invalid/api/source?id=1')),
      () => routed,
    );
    expect(response.statusCode, 200);
    expect(response.body, 'ok');
    expect(proxy.hits.single.path, '/no-such-host.invalid/api/source?id=1');
    routed.close();
  });
}
