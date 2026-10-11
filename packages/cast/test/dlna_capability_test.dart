import 'dart:io';

import 'package:cast/src/core/cast_device.dart';
import 'package:cast/src/core/cast_media.dart';
import 'package:cast/src/protocols/dlna/dlna_device.dart';
import 'package:cast/src/protocols/dlna/dlna_session.dart';
import 'package:cast/src/protocols/dlna/capability.dart';
import 'package:cast/src/protocols/dlna/dlna_controller.dart';
import 'package:cast/src/protocols/dlna/overrides.dart';
import 'package:test/test.dart';

/// Fixtures are SYNTHETIC (no real TV on the LAN). Set DLNA_CAP_TABLE to a
/// file path to write the result table for the evidence directory.
void main() {
  const dir = '../../evidence/part-12/ch02-p02';
  List<String> sink(String f) =>
      DlnaSoapParser.parseProtocolInfo(File('$dir/$f').readAsStringSync());
  final mp4Only = sink('protocolinfo_mp4_only.xml');
  final mkvTs = sink('protocolinfo_mkv_ts.xml');
  const types = [
    CastMediaType.mp4,
    CastMediaType.mkv,
    CastMediaType.mpegTs,
    CastMediaType.hls,
  ];
  CastCompatibility run(
    CastMediaType t,
    List<String> s, {
    String? maker,
    String? model,
    List<DlnaOverride> o = const [],
  }) => DlnaCapability.evaluate(
    type: t,
    sink: s,
    manufacturer: maker,
    modelName: model,
    overrides: o,
  );

  test('mp4-only renderer: mp4 direct, everything else not compatible', () {
    expect(run(CastMediaType.mp4, mp4Only), CastCompatibility.direct);
    for (final t in [
      CastMediaType.mkv,
      CastMediaType.mpegTs,
      CastMediaType.hls,
    ]) {
      expect(run(t, mp4Only), CastCompatibility.notCompatible);
    }
  });

  test('mkv+ts renderer: all four types direct', () {
    for (final t in types) {
      expect(run(t, mkvTs), CastCompatibility.direct);
    }
  });

  test('transform chooses advertised MP4 or TS for unsupported MKV', () {
    expect(
      DlnaCapability.evaluateTransform(type: CastMediaType.mkv, sink: mp4Only),
      CastCompatibility.remuxToMp4,
    );
    expect(
      DlnaCapability.evaluateTransform(
        type: CastMediaType.mkv,
        sink: ['http-get:*:video/mp2t:*'],
      ),
      CastCompatibility.remuxToHls,
    );
    expect(
      DlnaCapability.evaluateTransform(type: CastMediaType.mkv, sink: []),
      CastCompatibility.notCompatible,
    );
  });

  test('empty sink is not compatible', () {
    expect(run(CastMediaType.mp4, const []), CastCompatibility.notCompatible);
  });

  test('deny override wins over an advertised MIME, by maker and model', () {
    const o = [
      DlnaOverride(
        manufacturer: 'acme',
        model: 'x1',
        deny: {'video/x-matroska'},
      ),
    ];
    expect(
      run(CastMediaType.mkv, mkvTs, maker: 'ACME Corp', model: 'X1-55', o: o),
      CastCompatibility.notCompatible,
    );
    expect(
      run(CastMediaType.mkv, mkvTs, maker: 'ACME Corp', model: 'Z9', o: o),
      CastCompatibility.direct,
    );
    expect(
      run(CastMediaType.mkv, mkvTs, maker: 'Other', model: 'X1', o: o),
      CastCompatibility.direct,
    );
  });

  test('allow override wins over a missing MIME', () {
    const o = [
      DlnaOverride(manufacturer: 'acme', allow: {'video/x-matroska'}),
    ];
    expect(
      run(CastMediaType.mkv, mp4Only, maker: 'Acme', o: o),
      CastCompatibility.direct,
    );
  });

  test('session asks the renderer over SOAP and maps the answer', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final xml = File('$dir/protocolinfo_mp4_only.xml').readAsStringSync();
    server.listen((r) async {
      r.response.write(xml);
      await r.response.close();
    });
    final session = DlnaSession(
      device: CastDevice(
        id: 'uuid:t',
        name: 'T',
        protocol: CastProtocol.dlna,
        address: InternetAddress.loopbackIPv4,
        port: server.port,
      ),
      description: DlnaDeviceDescription(
        friendlyName: 'T',
        udn: 'uuid:t',
        locationUrl: 'http://127.0.0.1:${server.port}',
        connectionManagerControlUrl: 'http://127.0.0.1:${server.port}/cm',
      ),
    );
    addTearDown(session.dispose);
    expect(
      await session.compatibilityFor(CastMediaType.mp4),
      CastCompatibility.direct,
    );
    expect(
      await session.compatibilityFor(CastMediaType.mkv),
      CastCompatibility.remuxToMp4,
    );
  });

  test('writes the capability table', () {
    final rows = StringBuffer(
      '# DLNA capability table (synthetic fixtures, no real TV)\n\n'
      '| Fixture | mp4 | mkv | mpegTs | hls |\n| --- | --- | --- | --- | --- |\n',
    );
    for (final e in {'mp4_only': mp4Only, 'mkv_ts': mkvTs}.entries) {
      rows.writeln(
        '| ${e.key} | ${types.map((t) => run(t, e.value).name).join(' | ')} |',
      );
    }
    final path = Platform.environment['DLNA_CAP_TABLE'];
    if (path != null) File(path).writeAsStringSync(rows.toString());
  });
}
