import 'dart:io';
import 'dart:typed_data';

import 'package:cast/src/utils/network_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multicast sockets leave through the LAN interface, not the VPN route',
      () async {
    final lan = await NetworkUtils.getLocalIpAddress();
    expect(lan, isNotNull, reason: 'test host needs an IPv4 LAN address');

    final bind = await NetworkUtils.lanMulticastSocketFactory();
    final socket = await bind(InternetAddress.anyIPv4, 0);
    addTearDown(socket.close);

    final out = RawSocketOption(
      RawSocketOption.levelIPv4,
      RawSocketOption.IPv4MulticastInterface,
      Uint8List(4),
    );
    socket.getRawOption(out);
    expect(out.value, InternetAddress(lan!).rawAddress);
  });
}
