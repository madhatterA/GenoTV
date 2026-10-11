import 'dart:async';
import 'package:cast/src/core/cast_service.dart';
import 'package:cast/src/protocols/chromecast/chromecast_discovery_provider.dart';
import 'package:cast/src/protocols/dlna/dlna_discovery_provider.dart';
import 'package:cast/src/utils/logger.dart';

/// Headless discovery with the app's own CastService providers.
Future<void> main() async {
  CastLogger.setCallback((l, m) => print('[$l] $m'));
  final service = CastService(
    discoveryProviders: [ChromecastDiscoveryProvider(), DlnaDiscoveryProvider()],
  );
  final seen = <String>{};
  final done = Completer<void>();
  service.startDiscovery(timeout: const Duration(seconds: 20)).listen((ds) {
    for (final d in ds) {
      if (seen.add(d.id)) {
        print('${d.protocol.name}\t${d.name}\t${d.address.address}:${d.port}');
      }
    }
  }, onDone: done.complete);
  await done.future;
  print('done: ${seen.length} device(s)');
}
