import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/play_link.dart';

const _hex = '0123456789abcdef0123456789abcdef01234567';
const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

void main() {
  late HttpServer server;
  late Directory dir;
  late String base;
  var heads = 0;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('play-link-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final response = request.response;
      final path = request.uri.path;
      if (request.method == 'HEAD') heads++;
      switch (path) {
        case '/bt':
          response.headers.contentType = ContentType(
            'application',
            'x-bittorrent',
          );
        case '/hls':
          response.headers.contentType = ContentType(
            'application',
            'vnd.apple.mpegurl',
          );
        case '/hls2':
          response.headers.contentType = ContentType(
            'application',
            'x-mpegURL',
          );
        case '/big.torrent':
          response.headers.contentType = ContentType(
            'application',
            'x-bittorrent',
          );
          response.add(List<int>.filled(maxTorrentBytes + 1, 0x64));
        case '/html.torrent':
          response.write('<html>');
        case '/real.torrent':
          response.write('d4:infod4:name1:aee');
        case '/gone':
          response.statusCode = 404;
        default:
          response.headers.contentType = ContentType('video', 'x-matroska');
      }
      await response.close();
    });
  });
  tearDownAll(() async {
    await server.close(force: true);
    await dir.delete(recursive: true);
  });

  File torrent(String name) =>
      File('${dir.path}/$name')..writeAsStringSync('d');

  test('classifier table', () async {
    final local = torrent('a.torrent').path;
    final table = <String, LinkKind>{
      'magnet:?xt=urn:btih:$_hex': LinkKind.magnet,
      '  MAGNET:?xt=urn:btih:${_hex.toUpperCase()}&dn=x  ': LinkKind.magnet,
      'magnet:?dn=x&xt=urn:btih:$_b32': LinkKind.magnet,
      'magnet:?xt=urn:btih:${_b32.toLowerCase()}': LinkKind.magnet,
      local: LinkKind.torrentFile,
      ' ${local.replaceAll('.torrent', '.TORRENT')} ': LinkKind.torrentFile,
      Uri.file(local).toString(): LinkKind.torrentFile,
      'https://e.example/a/b.torrent': LinkKind.torrentUrl,
      'HTTPS://E.EXAMPLE/a/b.torrent?x=1': LinkKind.torrentUrl,
      'https://e.example/a.m3u8': LinkKind.hls,
      'https://e.example/a/b.M3U8?token=abc&e=2': LinkKind.hls,
      'https://e.example/a.m3u': LinkKind.hls,
      '$base/bt': LinkKind.torrentUrl,
      '$base/hls': LinkKind.hls,
      '$base/hls2?q=1': LinkKind.hls,
      '$base/movie.mkv?sig=a b'.replaceAll(' ', '%20'): LinkKind.directFile,
      '$base/gone': LinkKind.directFile,
      '  $base/x  ': LinkKind.directFile,
    };
    for (final entry in table.entries) {
      expect(await classifyLink(entry.key), entry.value, reason: entry.key);
    }
  });

  test('extension decides without a HEAD request', () async {
    heads = 0;
    await classifyLink('$base/a.m3u8');
    await classifyLink('$base/a.torrent');
    expect(heads, 0);
    await classifyLink('$base/a');
    expect(heads, 1);
  });

  test('invalid input is a typed failure', () async {
    final bad = <String>[
      '',
      '   ',
      'hello world',
      'ftp://e.example/a.mkv',
      'http://',
      'magnet:',
      'magnet:?dn=x',
      'magnet:?xt=urn:btih:xyz',
      'magnet:?xt=urn:sha1:$_hex',
      '${dir.path}/missing.torrent',
      '${dir.path}/movie.mkv',
    ];
    for (final input in bad) {
      await expectLater(
        classifyLink(input),
        throwsA(isA<PlayLinkFailure>()),
        reason: input,
      );
    }
    await expectLater(
      classifyLink('http://127.0.0.1:1/x'),
      throwsA(isA<PlayLinkFailure>()),
      reason: 'unreachable host',
    );
  });

  group('resolver', () {
    late LinkResolver resolver;
    setUp(
      () => resolver = LinkResolver(torrentDir: Directory('${dir.path}/t')),
    );

    test('each kind becomes the matching SourceSpec', () async {
      final magnet = await resolver.resolve(' magnet:?xt=urn:btih:$_hex ');
      expect(magnet.kind, SourceKind.torrentMagnet);
      expect(magnet.uri.toString(), 'magnet:?xt=urn:btih:$_hex');
      final file = await resolver.resolve(torrent('b.torrent').path);
      expect(file.kind, SourceKind.torrentFile);
      expect(file.uri.toFilePath(), '${dir.path}/b.torrent');
      final hls = await resolver.resolve('$base/a.m3u8?t=1');
      expect(hls.kind, SourceKind.hlsUrl);
      final direct = await resolver.resolve('$base/movie.mkv');
      expect(direct.kind, SourceKind.httpUrl);
    });

    test('a torrent URL is downloaded to a stable local file', () async {
      final first = await resolver.resolve('$base/real.torrent');
      final again = await resolver.resolve('$base/real.torrent');
      expect(first.kind, SourceKind.torrentFile);
      expect(first.uri, again.uri);
      expect(File.fromUri(first.uri).readAsStringSync(), 'd4:infod4:name1:aee');
    });

    test('bad torrent downloads are failures', () async {
      for (final path in ['/big.torrent', '/html.torrent']) {
        await expectLater(
          resolver.resolve('$base$path'),
          throwsA(isA<PlayLinkFailure>()),
          reason: path,
        );
      }
    });
  });

  test('linkTitle: magnet dn, URL file name, local file name, else null', () {
    expect(
      linkTitle('magnet:?xt=urn:btih:$_hex&dn=Sample+Film'),
      'Sample Film',
    );
    expect(linkTitle('magnet:?xt=urn:btih:$_hex'), isNull);
    expect(linkTitle('https://x.test/a/My%20Film.mp4?t=1'), 'My Film.mp4');
    expect(linkTitle('/tmp/dir/x.torrent'), 'x.torrent');
    expect(linkTitle('https://x.test/'), isNull);
  });

  test('torrentName reads info.name; malformed or nameless is null', () {
    Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));
    expect(
      torrentName(
        b(
          'd8:announce3:udp4:infod6:lengthi5e4:name10:Sample.mkv12:piece lengthi16384eee',
        ),
      ),
      'Sample.mkv',
    );
    expect(torrentName(b('d4:infod6:lengthi5eee')), isNull);
    expect(torrentName(b('d4:infod4:name99:shorte')), isNull);
    expect(torrentName(b('not a torrent')), isNull);
    expect(torrentName(Uint8List(0)), isNull);
  });
}
