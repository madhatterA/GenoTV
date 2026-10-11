/// Whether a renderer actually advertised an audio codec list.
enum AudioSupport { known, unknown }

/// Audio capability from the renderer, independent of container compatibility.
final class AudioCapability {
  const AudioCapability.unknown()
    : support = AudioSupport.unknown,
      codecs = const {};

  AudioCapability.known(Set<String> codecs)
    : support = AudioSupport.known,
      codecs = Set.unmodifiable(codecs.map((codec) => codec.toLowerCase()));

  /// Uses only the GetProtocolInfo Sink entries; container MIMEs prove nothing
  /// about their audio. Recognized profiles take precedence over broader MIMEs.
  factory AudioCapability.dlna(List<String> sink) {
    final codecs = <String>{};
    for (final entry in sink) {
      final fields = entry.split(':');
      if (fields.length < 4) continue;
      final mime = fields[2].split(';').first.trim().toLowerCase();
      final profile = RegExp(
        r'(?:^|;)\s*DLNA\.ORG_PN\s*=\s*([^;]+)',
        caseSensitive: false,
      ).firstMatch(fields.sublist(3).join(':'))?.group(1)?.trim().toUpperCase();
      final profileCodec = _profileCodecs[profile];
      codecs.addAll(
        profileCodec == null ? _mimeCodecs[mime] ?? const {} : {profileCodec},
      );
    }
    return codecs.isEmpty
        ? const AudioCapability.unknown()
        : AudioCapability.known(codecs);
  }

  final AudioSupport support;
  final Set<String> codecs;

  /// Unknown audio support must never cause an audio track to be dropped.
  bool supports(String codec) =>
      support == AudioSupport.unknown || codecs.contains(codec.toLowerCase());
}

// IANA audio registrations; RFC3003 includes MPEG layers I, II and III.
// L16 is signed 16-bit network byte order (RFC2586), not arbitrary PCM.
const _mimeCodecs = <String, Set<String>>{
  'audio/aac': {'aac'},
  'audio/ac3': {'ac3'},
  'audio/eac3': {'eac3'},
  'audio/flac': {'flac'},
  'audio/opus': {'opus'},
  'audio/vorbis': {'vorbis'},
  'audio/mpeg': {'mp1', 'mp2', 'mp3'},
  'audio/l16': {'pcm_s16be'},
  'audio/vnd.dlna.adts': {'aac'},
  'audio/vnd.dolby.dd-raw': {'ac3'},
  'audio/vnd.dts': {'dts'},
};

// Exact profile names and audio restrictions from GNOME gupnp-dlna's
// data/{aac,ac3,mp3,lpcm,avc}.xml. Unknown vendor names are never guessed.
const _profileCodecs = <String, String>{
  'AAC_ADTS_320': 'aac',
  'AAC_ADTS': 'aac',
  'AAC_ISO_320': 'aac',
  'AAC_ISO': 'aac',
  'AAC_MULT5_ADTS': 'aac',
  'AAC_MULT5_ISO': 'aac',
  'AC3': 'ac3',
  'EAC3': 'eac3',
  'MP3': 'mp3',
  'MP3X': 'mp3',
  'LPCM': 'pcm_s16be',
  'AVC_MP4_BL_CIF15_AAC_520': 'aac',
  'AVC_MP4_BL_CIF15_AAC': 'aac',
  'AVC_MP4_BL_L3L_SD_AAC': 'aac',
  'AVC_MP4_BL_L3_SD_AAC': 'aac',
  'AVC_MP4_MP_SD_AAC_MULT5': 'aac',
  'AVC_MP4_MP_SD_MPEG1_L3': 'mp3',
  'AVC_MP4_MP_SD_AC3': 'ac3',
  'AVC_MP4_MP_SD_EAC3': 'eac3',
  'AVC_MP4_MP_HD_720P_AAC': 'aac',
  'AVC_MP4_MP_HD_1080I_AAC': 'aac',
  'AVC_MKV_MP_HD_AAC_MULT5': 'aac',
  'AVC_MKV_HP_HD_AAC_MULT5': 'aac',
  'AVC_MKV_MP_HD_AC3': 'ac3',
  'AVC_MKV_HP_HD_AC3': 'ac3',
  'AVC_MKV_MP_HD_MPEG1_L3': 'mp3',
  'AVC_MKV_HP_HD_MPEG1_L3': 'mp3',
  'AVC_MP4_HP_HD_EAC3': 'eac3',
};
