import 'dart:convert';
import 'dart:io';

import 'package:cast/src/core/cast_device.dart';
import 'package:cast/src/core/cast_media.dart';
import 'package:cast/src/core/cast_session.dart';
import 'package:cast/src/protocols/chromecast/chromecast_session.dart';
import 'package:test/test.dart';

import 'integration/mock_chromecast_server.dart';

/// Phase 12 ch03 p01 proof against a fake receiver (no Chromecast on the LAN):
/// LOAD carries the proxy URL (never the provider URL) and a text/vtt track
/// served by the proxy with CORS headers, then seek and stop. Set
/// CHROMECAST_LOG to a file path to keep the log.
void main() {
  late HttpServer provider;
  late MockChromecastServer receiver;
  late ChromecastSession session;
  final providerSeen = <String>[];
  const srt = '1\n00:00:01,000 --> 00:00:02,500\nHello\n';

  setUp(() async {
    providerSeen.clear();
    provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    provider.listen((r) async {
      final authed = r.headers.value('Referer') == 'https://provider.example';
      providerSeen.add('${r.uri.path} authed=$authed');
      if (!authed) {
        r.response.statusCode = HttpStatus.forbidden;
      } else if (r.uri.path.endsWith('.srt')) {
        r.response.write(srt);
      } else {
        r.response.add(List<int>.filled(100, 7));
      }
      await r.response.close();
    });
    receiver = MockChromecastServer();
    session = ChromecastSession.withMocks(
      device: CastDevice(
        id: 'cc',
        name: 'Fake Chromecast',
        protocol: CastProtocol.chromecast,
        address: InternetAddress.loopbackIPv4,
        port: 8009,
      ),
      channel: receiver,
    );
  });

  tearDown(() async {
    await session.disconnect();
    session.dispose();
    await provider.close(force: true);
  });

  test(
    'LOAD uses proxy URLs and a CORS-enabled VTT track; seek; stop',
    () async {
      final log = <String>[];
      final base = 'http://127.0.0.1:${provider.port}';
      await session.connect();
      receiver.clearMessages();
      await session.loadMedia(
        CastMedia(
          url: '$base/movie.mp4',
          type: CastMediaType.mp4,
          title: 'Flow',
          httpHeaders: const {'Referer': 'https://provider.example'},
          subtitles: [
            CastSubtitle(
              url: '$base/en.srt',
              label: 'English',
              language: 'en',
              format: 'srt',
            ),
          ],
        ),
      );
      final load = receiver.sentMessages.firstWhere((m) => m.type == 'LOAD');
      final json = jsonEncode(load.payload);
      log.add('LOAD $json');
      final media = load.payload['media'] as Map;
      expect(json, isNot(contains('provider.example')));
      expect(json, isNot(contains('127.0.0.1:${provider.port}')));
      expect(media['contentType'], 'video/mp4');
      final track = (media['tracks'] as List).single as Map;
      expect(track['trackContentType'], 'text/vtt');
      expect(track['language'], 'en');

      final client = HttpClient();
      addTearDown(client.close);
      final req = await client.getUrl(
        Uri.parse(track['trackContentId'] as String),
      );
      req.headers.set('Origin', 'https://www.gstatic.com');
      final res = await req.close();
      final vtt = await utf8.decodeStream(res);
      log.add(
        'subtitle GET ${res.statusCode} ${res.headers.contentType} '
        'ACAO=${res.headers.value('access-control-allow-origin')}',
      );
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'text/vtt');
      expect(res.headers.value('access-control-allow-origin'), isNotNull);
      expect(vtt, startsWith('WEBVTT'));
      expect(vtt, contains('00:00:01.000 --> 00:00:02.500'));
      expect(providerSeen, ['/en.srt authed=true']);

      expect(session.state, SessionState.playing);
      receiver.clearMessages();
      await session.seek(const Duration(seconds: 30));
      expect(receiver.sentMessages.any((m) => m.type == 'SEEK'), isTrue);
      await session.stop();
      expect(receiver.sentMessages.any((m) => m.type == 'STOP'), isTrue);
      log.add('seek, stop sent; state=${session.state}');

      final path = Platform.environment['CHROMECAST_LOG'];
      if (path != null) File(path).writeAsStringSync('${log.join('\n')}\n');
    },
  );
}
