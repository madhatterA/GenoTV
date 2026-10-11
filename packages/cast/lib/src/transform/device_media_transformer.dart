import '../core/cast_device.dart';
import '../core/cast_media.dart';
import '../core/media_transformer.dart';
import '../protocols/chromecast/capability.dart';
import '../protocols/dlna/capability.dart';
import '../core/media_proxy.dart';
import '../remux/remuxer.dart';
import 'audio_capability.dart';
import 'media_transformer.dart';

/// Resolves the discovered renderer's capabilities before preparing its media.
class DeviceMediaTransformer implements MediaTransformer {
  DeviceMediaTransformer({required this.device, this.dlnaSink, this.remuxer});

  final CastDevice device;
  final Future<List<String>> Function()? dlnaSink;
  final Remuxer? remuxer;

  /// Native probing needs filesystem paths rather than file URIs.
  static String? localInputPath(CastMedia media) {
    final uri = Uri.tryParse(media.url);
    if (uri?.scheme == 'file') return uri!.toFilePath();
    return media.isLocalFile ? media.url : null;
  }

  @override
  Future<TransformedMedia> transform(CastMedia media, MediaProxy proxy) async {
    final AudioCapability audio;
    CastCompatibility compatibility;
    var embedSubtitles = false;
    List<RemuxStream>? probedStreams;
    if (device.protocol == CastProtocol.chromecast) {
      final localInput = localInputPath(media);
      final input =
          localInput ??
          (media.source != null
              ? proxy.registerSource(
                  media.source!,
                  fileExtension: media.type.name,
                )
              : proxy.registerMedia(
                  media.url,
                  headers: media.httpHeaders,
                  stripDvbTables: false,
                ));
      final List<RemuxStream> streams;
      try {
        streams = await (remuxer ?? Remuxer()).probe(input);
        probedStreams = streams;
      } finally {
        if (localInput == null) proxy.unregisterMedia(input);
      }
      final video = streams.where(
        (stream) => stream.type == 'video' && !stream.attachedPicture,
      );
      compatibility = chromecastCompatibility(
        model: chromecastModelFromMd(device.metadata['md'] ?? ''),
        container: media.type == CastMediaType.mpegTs
            ? 'mpegts'
            : media.type.name,
        videoCodec: video.isEmpty ? '' : video.first.codec,
        audioCodec: '',
      );
      if (compatibility == CastCompatibility.direct &&
          media.type == CastMediaType.mpegTs) {
        compatibility = CastCompatibility.remuxToHls;
      }
      audio = chromecastAudioCapability();
    } else if (device.protocol == CastProtocol.dlna) {
      final sink = await dlnaSink?.call() ?? const <String>[];
      compatibility = DlnaCapability.evaluateTransform(
        type: media.type,
        sink: sink,
        manufacturer: device.metadata['manufacturer'],
        modelName: device.metadata['modelName'],
      );
      audio = AudioCapability.dlna(sink);
      final subtitlesRequested =
          media.subtitles.isNotEmpty || media.defaultSubtitle != null;
      if (subtitlesRequested) {
        final mkvCompatibility = DlnaCapability.evaluate(
          type: CastMediaType.mkv,
          sink: sink,
          manufacturer: device.metadata['manufacturer'],
          modelName: device.metadata['modelName'],
        );
        if (mkvCompatibility != CastCompatibility.direct) {
          throw const CastTransformFailure();
        }
        compatibility = CastCompatibility.direct;
        embedSubtitles = true;
      }
    } else {
      throw UnsupportedError(
        'No media capability path for ${device.protocol.name}',
      );
    }
    return CastRemuxMediaTransformer(
      compatibility: compatibility,
      audioCapability: audio,
      embedSubtitles: embedSubtitles,
      remuxer: remuxer,
      streams: probedStreams,
    ).transform(media, proxy);
  }
}
