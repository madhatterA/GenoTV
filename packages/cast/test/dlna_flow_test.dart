import 'dart:convert';
import 'dart:io';

import 'package:cast/src/core/cast_device.dart';
import 'package:cast/src/core/cast_media.dart';
import 'package:cast/src/core/cast_session.dart';
import 'package:cast/src/protocols/dlna/dlna_device.dart';
import 'package:cast/src/protocols/dlna/dlna_discovery_provider.dart';
import 'package:cast/src/protocols/dlna/dlna_session.dart';
import 'package:test/test.dart';

import 'integration/mock_dlna_server.dart';

/// Phase 12 ch02 p01 proof against a local fake renderer: SSDP discovery,
/// SetAVTransportURI with DIDL-Lite pointing at the proxy (never at the
/// provider), protocolInfo MIME equal to the MIME the proxy serves, Play,
/// seek to 50%, Stop. Set DLNA_LOG to a file path to keep the action log.
void main() {
  late MockDlnaServer renderer;
  late HttpServer provider;
  late DlnaSession session;
  final providerSeen = <String>[];
  final media = List<int>.generate(1000, (i) => i % 251);

  setUp(() async {
    providerSeen.clear();
    provider = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    provider.listen((r) async {
      final authed = r.headers.value('Referer') == 'https://provider.example';
      providerSeen.add('${r.method} ${r.uri.path} authed=$authed');
      if (!authed) {
        r.response.statusCode = HttpStatus.forbidden;
      } else {
        r.response.headers.contentType = ContentType('video', 'mp4');
        r.response.add(media);
      }
      await r.response.close();
    });
    renderer = MockDlnaServer();
    await renderer.start();
    final description = DlnaDeviceDescription.parse(
      renderer.deviceDescriptionXml,
      renderer.descriptionUrl,
    );
    session = DlnaSession(
      device: CastDevice(
        id: renderer.udn,
        name: renderer.friendlyName,
        protocol: CastProtocol.dlna,
        address: InternetAddress.loopbackIPv4,
        port: renderer.httpPort,
      ),
      description: description,
    );
  });

  tearDown(() async {
    await session.disconnect();
    session.dispose();
    await renderer.stop();
    await provider.close(force: true);
  });

  test('SSDP finds the renderer from an M-SEARCH answer', () async {
    // Answer the provider's own M-SEARCH from a second socket on loopback.
    final probe = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(probe.close);
    final finder = DlnaDiscoveryProvider(
      socketFactory: (host, port) async {
        final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        final port = s.port;
        Future<void>.delayed(const Duration(milliseconds: 100), () {
          probe.send(
            utf8.encode(
              'HTTP/1.1 200 OK\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
              'USN: ${renderer.udn}::urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
              'LOCATION: ${renderer.descriptionUrl}\r\n\r\n',
            ),
            InternetAddress.loopbackIPv4,
            port,
          );
        });
        return s;
      },
      httpFetcher: (url) async {
        expect(url, renderer.descriptionUrl);
        return renderer.deviceDescriptionXml;
      },
    );
    addTearDown(finder.dispose);
    final devices = await finder
        .startDiscovery(timeout: const Duration(seconds: 2))
        .firstWhere((l) => l.isNotEmpty);
    expect(devices.single.name, renderer.friendlyName);
    expect(devices.single.protocol, CastProtocol.dlna);
    expect(devices.single.metadata['avTransportControlUrl'], isNotEmpty);
  });

  test('plays through the proxy, seeks to 50%, stops', () async {
    final log = <String>[];
    renderer.durationSeconds = 600;
    await session.connect();
    await session.loadMedia(
      CastMedia(
        url: 'http://127.0.0.1:${provider.port}/secret/movie.mp4',
        type: CastMediaType.mp4,
        title: 'Flow',
        httpHeaders: const {'Referer': 'https://provider.example'},
        duration: const Duration(seconds: 600),
      ),
    );
    log.add('loaded state=${session.state}');
    final set = renderer.capturedActions.firstWhere(
      (a) => a.action == 'SetAVTransportURI',
    );
    final body = set.body
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&');
    expect(body, isNot(contains('provider.example')));
    expect(body, isNot(contains('127.0.0.1:${provider.port}')));
    final url = RegExp(r'<CurrentURI>([^<]+)</CurrentURI>')
        .firstMatch(body)!
        .group(1)!
        .replaceAll('&amp;', '&');
    final pi = RegExp(r'protocolInfo="([^"]+)"').firstMatch(body)!.group(1)!;
    log.add('uri=$url');
    log.add('protocolInfo=$pi');
    expect(url, contains('/stream/'));
    expect(url, isNot(contains('provider')));
    expect(body, contains('<dc:title>Flow</dc:title>'));
    expect(body, contains('duration="00:10:00'));

    // The renderer fetches what it was given: MIME must equal protocolInfo.
    final client = HttpClient();
    addTearDown(client.close);
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    log.add('renderer GET ${res.statusCode} ${res.headers.contentType}');
    expect(res.statusCode, 200);
    expect(bytes, media);
    expect(
      '${res.headers.contentType!.primaryType}/${res.headers.contentType!.subType}',
      pi.split(':')[2],
    );
    expect(providerSeen, ['GET /secret/movie.mp4 authed=true']);

    expect(renderer.transportState, 'PLAYING');
    await session.seek(const Duration(seconds: 300));
    log.add('seek 300s position=${renderer.positionSeconds}');
    expect(renderer.positionSeconds, 300.0);
    expect(session.position, const Duration(seconds: 300));
    await session.stop();
    log.add('stop transport=${renderer.transportState} state=${session.state}');
    expect(renderer.transportState, 'STOPPED');
    expect(session.state, SessionState.idle);
    log.addAll(renderer.capturedActions.map((a) => 'soap ${a.action}'));

    final path = Platform.environment['DLNA_LOG'];
    if (path != null) File(path).writeAsStringSync('${log.join('\n')}\n');
  });
}
