/// Technical facts about the media that is playing. Every field is null when
/// the engine does not know it; consumers omit unknown values.
class MediaInfo {
  const MediaInfo({
    this.container,
    this.fileSizeBytes,
    this.duration,
    this.bitrate,
    this.videoCodec,
    this.width,
    this.height,
    this.frameRate,
    this.bitDepth,
    this.colorMatrix,
    this.colorPrimaries,
    this.colorTransfer,
    this.audioCodec,
    this.audioChannels,
    this.audioChannelLayout,
    this.audioSampleRate,
    this.subtitleFormat,
  });

  /// Container format name, e.g. `matroska`.
  final String? container;
  final int? fileSizeBytes;
  final Duration? duration;

  /// Overall bitrate in bits per second.
  final int? bitrate;
  final String? videoCodec;
  final int? width;
  final int? height;
  final double? frameRate;
  final int? bitDepth;
  final String? colorMatrix;
  final String? colorPrimaries;

  /// Transfer characteristic as mpv names it, e.g. `pq`, `hlg`, `bt.1886`.
  final String? colorTransfer;
  final String? audioCodec;
  final int? audioChannels;

  /// Channel layout as mpv names it, e.g. `5.1(side)`, `stereo`.
  final String? audioChannelLayout;
  final int? audioSampleRate;

  /// Codec name of the selected subtitle track.
  final String? subtitleFormat;

  static const MediaInfo empty = MediaInfo();

  @override
  bool operator ==(Object other) =>
      other is MediaInfo && toString() == other.toString();

  @override
  int get hashCode => toString().hashCode;

  @override
  String toString() =>
      'MediaInfo($container,$fileSizeBytes,$duration,$bitrate,$videoCodec,'
      '$width,$height,$frameRate,$bitDepth,$colorMatrix,$colorPrimaries,'
      '$colorTransfer,$audioCodec,$audioChannels,$audioChannelLayout,'
      '$audioSampleRate,$subtitleFormat)';
}
