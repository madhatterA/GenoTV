import '../../core/cast_media.dart';
import 'overrides.dart';

/// Whether a renderer can play a stream, per Part 09's contract.
///
/// The remuxer is deferred (owner, 2026-10-01), so [DlnaCapability] only ever
/// returns [direct] or [notCompatible]; the remux values are reserved for it.
enum CastCompatibility { direct, remuxToMp4, remuxToHls, notCompatible }

/// Decides [CastCompatibility] from a renderer's `GetProtocolInfo` Sink list.
class DlnaCapability {
  DlnaCapability._();

  /// MIME types a renderer may advertise for each container we can serve.
  /// HLS is piped to DLNA as MPEG-TS, so it needs the TS MIME.
  static const Map<CastMediaType, List<String>> mimesFor = {
    CastMediaType.mp4: ['video/mp4'],
    CastMediaType.mkv: ['video/x-matroska', 'video/matroska', 'video/x-mkv'],
    CastMediaType.mpegTs: ['video/mp2t', 'video/vnd.dlna.mpeg-tts'],
    CastMediaType.hls: ['video/mp2t', 'video/vnd.dlna.mpeg-tts'],
  };

  /// Choose a stream-copy container only when the renderer advertises it.
  static CastCompatibility evaluateTransform({
    required CastMediaType type,
    required List<String> sink,
    String? manufacturer,
    String? modelName,
  }) {
    CastCompatibility forType(CastMediaType candidate) => evaluate(
      type: candidate,
      sink: sink,
      manufacturer: manufacturer,
      modelName: modelName,
    );
    if (forType(type) == CastCompatibility.direct) {
      return CastCompatibility.direct;
    }
    if (forType(CastMediaType.mp4) == CastCompatibility.direct) {
      return CastCompatibility.remuxToMp4;
    }
    if (forType(CastMediaType.hls) == CastCompatibility.direct) {
      return CastCompatibility.remuxToHls;
    }
    return CastCompatibility.notCompatible;
  }

  /// [sink] is the parsed Sink list (`http-get:*:video/mp4:...` entries).
  /// Overrides win over the advertised list in both directions.
  static CastCompatibility evaluate({
    required CastMediaType type,
    required List<String> sink,
    String? manufacturer,
    String? modelName,
    List<DlnaOverride> overrides = dlnaOverrides,
  }) {
    final mimes = mimesFor[type];
    if (mimes == null) return CastCompatibility.notCompatible;
    final advertised = sink
        .map((p) => p.split(':'))
        .where((f) => f.length >= 3)
        .map((f) => f[2].toLowerCase())
        .toSet();
    var supported = mimes.any(advertised.contains);
    for (final o in overrides) {
      if (!o.matches(manufacturer, modelName)) continue;
      if (mimes.any(o.deny.contains)) supported = false;
      if (mimes.any(o.allow.contains)) supported = true;
    }
    return supported
        ? CastCompatibility.direct
        : CastCompatibility.notCompatible;
  }
}
