import 'dart:io';

import 'package:cast/dart_cast.dart';
import 'package:test/test.dart';

// SYNTHETIC discovery data shaped like real mDNS TXT / UPnP descriptions.
// No real device was on the LAN.
CastDevice cc(String name, String ip, String md) => CastDevice(
  id: 'cc-$ip',
  name: name,
  protocol: CastProtocol.chromecast,
  address: InternetAddress(ip),
  port: 8009,
  metadata: {'md': md},
);

CastDevice dlna(String name, String ip, {String maker = 'Sony'}) => CastDevice(
  id: 'uuid:$ip',
  name: name,
  protocol: CastProtocol.dlna,
  address: InternetAddress(ip),
  port: 52323,
  metadata: {'manufacturer': maker},
);

void main() {
  final log = StringBuffer();

  void note(String s) => log.writeln(s);

  // H.264/AC3 in MKV: Chromecast needs remux; this DLNA TV plays it directly.
  CastCompatibility mkv(CastDevice d) => d.protocol == CastProtocol.chromecast
      ? chromecastCompatibility(
          model: chromecastModelFromMd(d.metadata['md']!),
          container: 'mkv',
          videoCodec: 'h264',
          audioCodec: 'ac3',
        )
      : CastCompatibility.direct;
  CastCompatibility mp4(CastDevice d) => CastCompatibility.direct;

  tearDownAll(() {
    File('../../evidence/part-12/ch05-p01/device_list.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(log.toString());
  });

  test('same IP over both protocols is listed once; protocol follows compat', () {
    final found = [
      cc('Living Room', '192.168.1.20', 'Chromecast'),
      dlna('BRAVIA 4K', '192.168.1.20'),
      dlna('Kitchen TV', '192.168.1.31'),
    ];
    final m = mergeCastDevices(found, mkv);
    expect(m, hasLength(2));
    final tv = m.firstWhere((e) => e.devices.length == 2);
    expect(tv.best.protocol, CastProtocol.dlna);
    expect(tv.compatibility, CastCompatibility.direct);
    final tie = mergeCastDevices(found, mp4).first;
    expect(tie.best.protocol, CastProtocol.chromecast);
    note('SYNTHETIC discovery data (no real device on LAN)');
    for (final e in mergeCastDevices(found, mkv)) {
      note(
        'MKV stream: ${e.name} -> ${e.best.protocol.name} '
        '(${e.compatibility.name}) from ${e.devices.map((d) => '${d.protocol.name}@${d.address.address}').join(', ')}',
      );
    }
    for (final e in mergeCastDevices(found, mp4)) {
      note(
        'MP4 stream: ${e.name} -> ${e.best.protocol.name} (${e.compatibility.name})',
      );
    }
  });

  test('different IP but same friendly name merges (DHCP change)', () {
    final m = mergeCastDevices([
      cc('Living-Room TV', '192.168.1.20', 'Chromecast'),
      dlna('living room tv', '192.168.1.99'),
    ], mp4);
    expect(m, hasLength(1));
  });

  test('different TVs and same-protocol twins stay separate', () {
    final m = mergeCastDevices([
      cc('Bedroom', '192.168.1.21', 'Chromecast'),
      dlna('Office', '192.168.1.22'),
      dlna('Office', '192.168.1.23'),
    ], mp4);
    expect(m, hasLength(3));
  });

  test('all protocols not compatible keeps the device with that result', () {
    final m = mergeCastDevices([
      cc('Den', '10.0.0.5', 'Chromecast'),
    ], (_) => CastCompatibility.notCompatible);
    expect(m.single.compatibility, CastCompatibility.notCompatible);
  });

  test('md string maps to model', () {
    expect(chromecastModelFromMd('Chromecast'), ChromecastModel.gen3);
    expect(chromecastModelFromMd('Chromecast Ultra'), ChromecastModel.ultra);
    expect(
      chromecastModelFromMd('Chromecast with Google TV'),
      ChromecastModel.googleTv,
    );
    expect(
      chromecastModelFromMd('Google TV Streamer'),
      ChromecastModel.googleTvStreamer,
    );
    expect(chromecastModelFromMd('Google Nest Hub'), ChromecastModel.nestHub);
    expect(chromecastModelFromMd('Mystery'), ChromecastModel.gen1Gen2);
  });

  test('Chromecast-only MKV target retains remux compatibility', () {
    final devices = mergeCastDevices([
      cc('Den', '10.0.0.5', 'Chromecast'),
    ], mkv);
    expect(devices.single.compatibility, CastCompatibility.remuxToMp4);
  });
}
