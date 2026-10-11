import 'package:cast/src/utils/logger.dart';
import 'package:cast/src/utils/mdns_discovery.dart';

/// Prints every mDNS service of the given type (default _googlecast._tcp.local)
/// that the cast stack's own mDNS client finds. Used as a control with
/// _airplay._tcp.local, which the Apple TV answers.
Future<void> main(List<String> args) async {
  CastLogger.setCallback((l, m) => print('[$l] $m'));
  final type = args.isEmpty ? '_googlecast._tcp.local' : args.first;
  var n = 0;
  await for (final s in MdnsDiscovery.discover(type)) {
    n++;
    print('found\t${s.friendlyName}\t${s.host}:${s.port}');
  }
  print('done: $n service(s) of $type');
}
