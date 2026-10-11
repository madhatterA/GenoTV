import '../../transform/audio_capability.dart';
import '../dlna/capability.dart' show CastCompatibility;

/// Chromecast hardware families with distinct media support.
enum ChromecastModel {
  gen1Gen2,
  gen3,
  ultra,
  googleTv,
  googleTvStreamer,
  nestHub,
}

/// Model -> codec table from Google's published supported-media page
/// (https://developers.google.com/cast/docs/media, accessed 2026-10-01).
/// Profile/level and resolution limits are not modelled; only the codec family.
const Map<ChromecastModel, Set<String>> _videoCodecs = {
  ChromecastModel.gen1Gen2: {'h264', 'vp8'},
  ChromecastModel.gen3: {'h264', 'vp8'},
  ChromecastModel.ultra: {'h264', 'vp8', 'hevc', 'vp9'},
  ChromecastModel.googleTv: {'h264', 'hevc', 'vp9'},
  ChromecastModel.googleTvStreamer: {'h264', 'hevc', 'vp9', 'av1'},
  ChromecastModel.nestHub: {'h264', 'vp9'},
};

/// Audio codecs the page lists for every model (AC-3 / E-AC-3 included).
const Set<String> _audioCodecs = {
  'aac',
  'mp3',
  'opus',
  'vorbis',
  'flac',
  'pcm',
  'ac3',
  'eac3',
};

/// Containers the page lists: MP2T, MP3, MP4, OGG, WAV, WebM, plus HLS.
/// Matroska is not listed, so it can only be played after a remux.
const Set<String> _containers = {'mp4', 'webm', 'mpegts', 'hls'};

const Map<String, String> _alias = {
  'avc': 'h264',
  'avc1': 'h264',
  'h.264': 'h264',
  'h265': 'hevc',
  'h.265': 'hevc',
  'hvc1': 'hevc',
  'hev1': 'hevc',
  'ac-3': 'ac3',
  'e-ac-3': 'eac3',
  'ec3': 'eac3',
  'aac_latm': 'aac',
  'mp4a': 'aac',
  'matroska': 'mkv',
  'ts': 'mpegts',
  'mp2t': 'mpegts',
};

String _norm(String s) {
  final k = s.toLowerCase().trim();
  return _alias[k] ?? k;
}

/// Decides how a stream plays on a Chromecast [model].
///
/// The remuxer is deferred (owner, 2026-10-01), so a stream that would need
/// one (for example MKV) is [CastCompatibility.notCompatible]: the UI shows
/// "This device can't play this file". Unknown codecs are not compatible.
CastCompatibility chromecastCompatibility({
  required ChromecastModel model,
  required String container,
  required String videoCodec,
  required String audioCodec,
}) {
  if (!_videoCodecs[model]!.contains(_norm(videoCodec))) {
    return CastCompatibility.notCompatible;
  }
  final normalizedContainer = _norm(container);
  if (normalizedContainer == 'mkv') return CastCompatibility.remuxToMp4;
  return _containers.contains(normalizedContainer)
      ? CastCompatibility.direct
      : CastCompatibility.notCompatible;
}

/// Maps the mDNS `md` TXT value to a [ChromecastModel].
///
/// `md` strings follow pychromecast's `model_name` (Chromecast, Chromecast
/// Ultra, Chromecast Audio, Google Home...). Gen 1/2/3 share one string and
/// one codec set. An unrecognised string gets the narrowest video set
/// (gen1Gen2) so a TV is never promised a codec it may lack.
ChromecastModel chromecastModelFromMd(String md) {
  final m = md.toLowerCase();
  if (m.contains('ultra')) return ChromecastModel.ultra;
  if (m.contains('streamer')) return ChromecastModel.googleTvStreamer;
  if (m.contains('google tv')) return ChromecastModel.googleTv;
  if (m.contains('nest hub') || m.contains('home hub')) {
    return ChromecastModel.nestHub;
  }
  if (m == 'chromecast') return ChromecastModel.gen3;
  return ChromecastModel.gen1Gen2;
}

/// The existing published Chromecast audio family list.
AudioCapability chromecastAudioCapability() =>
    AudioCapability.known(_audioCodecs);
