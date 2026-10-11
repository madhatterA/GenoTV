import '../core/cast_device.dart';
import '../protocols/dlna/capability.dart';

/// One TV as the user sees it: every protocol that reaches it, and the one
/// to cast with.
class MergedCastDevice {
  final String name;
  final List<CastDevice> devices;
  final CastDevice best;
  final CastCompatibility compatibility;

  const MergedCastDevice({
    required this.name,
    required this.devices,
    required this.best,
    required this.compatibility,
  });
}

String _key(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

bool _same(CastDevice a, CastDevice b) =>
    a.protocol != b.protocol &&
    (a.address.address == b.address.address ||
        (_key(a.name).isNotEmpty && _key(a.name) == _key(b.name)));

/// Merges devices that are the same TV: found over different protocols with
/// the same IP address, else the same friendly name (SOURCE_2026-09-30 §5).
/// Identity is recomputed every call, never persisted (IPs change by DHCP).
///
/// [compatibilityOf] is the result for the stream being cast; the best
/// protocol is the most direct one, Chromecast on a tie.
List<MergedCastDevice> mergeCastDevices(
  List<CastDevice> found,
  CastCompatibility Function(CastDevice) compatibilityOf,
) {
  final groups = <List<CastDevice>>[];
  for (final d in found) {
    final g = groups.where((g) => g.any((o) => _same(d, o))).firstOrNull;
    if (g != null) {
      g.add(d);
    } else {
      groups.add([d]);
    }
  }
  return [
    for (final g in groups)
      () {
        final ranked = [...g]
          ..sort((a, b) {
            final c = compatibilityOf(a).index - compatibilityOf(b).index;
            return c != 0 ? c : a.protocol.index - b.protocol.index;
          });
        return MergedCastDevice(
          name: ranked.first.name,
          devices: g,
          best: ranked.first,
          compatibility: compatibilityOf(ranked.first),
        );
      }(),
  ];
}
