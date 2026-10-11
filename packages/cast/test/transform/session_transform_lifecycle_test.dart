import 'dart:io';
import 'dart:async';

import 'package:cast/dart_cast.dart';
import 'package:flutter_test/flutter_test.dart';

import '../protocols/dlna/dlna_session_test.dart' show MockDlnaServer;

class _OwnedMedia extends TransformedMedia {
  _OwnedMedia()
    : super(
        proxyUrl: 'http://127.0.0.1/output.mp4',
        effectiveType: CastMediaType.mp4,
      );
  int disposals = 0;
  @override
  Future<void> dispose() async => disposals++;
}

class _Transformer implements MediaTransformer {
  final results = <_OwnedMedia>[];
  @override
  Future<TransformedMedia> transform(CastMedia media, MediaProxy proxy) async {
    final result = _OwnedMedia();
    results.add(result);
    return result;
  }
}

class _DelayedTransformer implements MediaTransformer {
  final started = Completer<void>();
  final result = Completer<TransformedMedia>();
  @override
  Future<TransformedMedia> transform(CastMedia media, MediaProxy proxy) {
    started.complete();
    return result.future;
  }
}

void main() {
  test(
    'DLNA releases transformation on replacement, stop and disconnect',
    () async {
      final server = MockDlnaServer();
      await server.start();
      final transformer = _Transformer();
      final session = DlnaSession(
        device: CastDevice(
          id: 'lifecycle',
          name: 'Lifecycle',
          protocol: CastProtocol.dlna,
          address: InternetAddress.loopbackIPv4,
          port: Uri.parse(server.baseUrl).port,
        ),
        description: DlnaDeviceDescription(
          friendlyName: 'Lifecycle',
          udn: 'lifecycle',
          avTransportControlUrl: server.avTransportUrl,
          locationUrl: server.baseUrl,
        ),
        mediaTransformer: transformer,
      );
      addTearDown(() async {
        session.dispose();
        await server.stop();
      });
      const media = CastMedia(
        url: 'http://127.0.0.1/source.mp4',
        type: CastMediaType.mp4,
      );
      await session.connect();
      await session.loadMedia(media);
      await session.loadMedia(media);
      expect(transformer.results[0].disposals, 1);
      expect(transformer.results[1].disposals, 0);
      await session.stop();
      expect(transformer.results[1].disposals, 1);
      await session.loadMedia(media);
      await session.disconnect();
      expect(transformer.results[2].disposals, 1);
    },
  );
  test(
    'disconnect releases a late transform and never sends LOAD or Play',
    () async {
      final server = MockDlnaServer();
      await server.start();
      final transformer = _DelayedTransformer();
      final session = DlnaSession(
        device: CastDevice(
          id: 'late',
          name: 'Late',
          protocol: CastProtocol.dlna,
          address: InternetAddress.loopbackIPv4,
          port: Uri.parse(server.baseUrl).port,
        ),
        description: DlnaDeviceDescription(
          friendlyName: 'Late',
          udn: 'late',
          avTransportControlUrl: server.avTransportUrl,
          locationUrl: server.baseUrl,
        ),
        mediaTransformer: transformer,
      );
      addTearDown(() async {
        session.dispose();
        await server.stop();
      });
      await session.connect();
      final loading = session.loadMedia(
        const CastMedia(
          url: 'http://127.0.0.1/source.mp4',
          type: CastMediaType.mp4,
        ),
      );
      await transformer.started.future;
      await session.disconnect();
      final lateResult = _OwnedMedia();
      transformer.result.complete(lateResult);
      await loading;
      expect(lateResult.disposals, 1);
      expect(
        server.capturedActions.where(
          (action) =>
              action.action == 'SetAVTransportURI' || action.action == 'Play',
        ),
        isEmpty,
      );
      expect(session.state, SessionState.disconnected);
    },
  );
}
