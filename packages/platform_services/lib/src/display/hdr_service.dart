import '../channel/platform_channel.dart';

final class HdrOutput {
  const HdrOutput({
    required this.available,
    required this.formats,
    this.fallbackReason,
  });

  final bool available;
  final List<String> formats;
  final String? fallbackReason;

  factory HdrOutput.fromPayload(Object? raw) {
    final map = asMap(raw);
    final formats = map['hdrFormats'] is List
        ? (map['hdrFormats'] as List).whereType<String>().toList(
            growable: false,
          )
        : const <String>[];
    final toggle = map['osHdrEnabled'];
    final available =
        boolValue(map['hdrOutput']) && formats.isNotEmpty && toggle != false;
    return HdrOutput(
      available: available,
      formats: available ? formats : const [],
      fallbackReason: available
          ? null
          : toggle == false
          ? 'OS HDR toggle is disabled'
          : formats.isEmpty
          ? 'display path reported no HDR formats'
          : 'display path cannot accept HDR right now',
    );
  }
}

/// Reads current HDR output state; it never alters playback or the picture.
final class HdrOutputService {
  const HdrOutputService(this.channel);

  final PlatformChannel channel;

  Future<HdrOutput> probe() async =>
      HdrOutput.fromPayload(await channel.invoke(PlatformMethods.probe));
}
