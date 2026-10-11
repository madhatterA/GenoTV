import 'dart:math';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:platform_services/platform_services.dart'
    show DisplayModeWhitelist, AudioPlanOverrides;
import 'package:playback/playback.dart' show HdrPolicy, TrackRules;

import 'platform_policy.dart';

/// The one place the Playback, Video and Display settings become engine and
/// platform behaviour. Everything here is pure, so it is testable without mpv.
///
/// mpv names and values: `research/technical/MPV_PLAYBACK.md` and the mpv
/// manual (hwdec, video-sync, tone-mapping, scale/cscale/dscale,
/// dither, interpolation, deband, demuxer cache options, panscan/keepaspect).

/// The mpv properties each setting writes. A property owned by several
/// settings (hwdec, the cache numbers, the video filter chain) is resolved
/// across all of them, so a value never depends on which setting changed.
import 'dart:io';

const Map<String, List<String>> _propertiesOf = {
  // These two are first: they set many options, so the explicit settings
  // below are applied after them to win. Their values are `_gpuLevels`.
  'performance.mode': [],
  'performance.gpuQuality': [],
  'performance.decoderThreads': ['vd-lavc-threads'],
  'playback.speed': ['speed'],
  'playback.syncToDisplay': ['video-sync'],
  'playback.avSyncCorrection': ['audio-delay'],
  'playback.cachePreset': [
    'cache-secs',
    'demuxer-max-bytes',
    'demuxer-readahead-secs',
  ],
  'playback.demuxerCacheSize': ['demuxer-max-bytes'],
  'streaming.bufferSize': ['demuxer-max-bytes'],
  'streaming.prebuffer': ['cache-pause-wait'],
  'playback.readAhead': ['demuxer-readahead-secs'],
  'playback.networkTimeout': ['network-timeout'],
  'video.hwdec': ['hwdec'],
  'video.decoder': ['hwdec'],
  'video.aspectRatio': ['keepaspect', 'panscan'],
  'video.scalingQuality': ['scale', 'cscale', 'dscale'],
  'video.toneMapping': ['tone-mapping'],
  'video.pixelFormat': ['vf'],
  'video.chroma': ['vf'],
  'video.bitDepth': ['dither-depth'],
  'video.dithering': ['dither'],
  'video.interpolation': ['interpolation'],
  'video.debanding': ['deband'],
  'video.gpuRendering': ['gpu-api'],
  'display.calibration': ['video-zoom', 'video-pan-x', 'video-pan-y'],
};

/// Every setting that maps to mpv properties in this phase.
final Set<SettingDef> engineSettingDefs = {
  for (final id in _propertiesOf.keys) settingById(id),
};

/// The settings of the Playback, Video and Display sections (including those
/// shared into them) whose changes affect playback.
final Set<SettingDef> playerSettingDefs = {
  for (final def in settingDefs)
    if (def.kind != SettingKind.page &&
        const {
          SettingSection.playback,
          SettingSection.video,
          SettingSection.display,
        }.any((s) => def.section == s || def.alsoIn.contains(s)))
      def,
};

/// Preset values of the cache/buffer presets. Balanced is the engine's own
/// state, so the default changes nothing.
const Map<String, Map<String, String>> _cachePresets = {
  'Low latency': {
    'cache-secs': '10',
    'demuxer-max-bytes': '8388608',
    'demuxer-readahead-secs': '1',
  },
  'Balanced': {
    'cache-secs': '3600000',
    'demuxer-max-bytes': '33554432',
    'demuxer-readahead-secs': '1',
  },
  'Large': {
    'cache-secs': '3600000',
    'demuxer-max-bytes': '134217728',
    'demuxer-readahead-secs': '60',
  },
};

const Map<String, String> _chromaFormat = {
  '4:2:0': 'yuv420p',
  '4:2:2': 'yuv422p',
  '4:4:4': 'yuv444p',
};

Object _typed(SettingDef def, String text) => switch (def.kind) {
  SettingKind.toggle => text == 'true',
  SettingKind.number => double.parse(text),
  _ => text,
};

/// Whether the user changed [def] from its default.
bool isChanged(SettingsValues values, SettingDef def) =>
    values.read<Object>(def) != _typed(def, def.defaultValue);

/// Opening options normally apply changes; Android also resets retained video
/// rendering options so defaults cannot inherit a previous video's values.
Set<SettingDef> changedEngineSettings(SettingsValues values, {String? os}) => {
  for (final def in engineSettingDefs)
    if (isChanged(values, def)) def,
  // Auto (30 s) must always reach mpv: unwritten, media_kit's 5 s applies and
  // gives up before a direct file's first bytes arrive through the local
  // range server (bug_history.md 2026-10-11 stream-fail).
  settingById('playback.networkTimeout'),
  // Android retains its decoder/renderer between videos. Reset rendering
  // values too, so a previous video's CPU filter or HDR curve cannot leak.
  if (_hwdecApi(os) != null)
    for (final def in engineSettingDefs)
      if (def.id.startsWith('video.') ||
          def.id == 'display.calibration' ||
          def.id == 'playback.syncToDisplay')
        def,
};

/// The platform's native hardware decoder API (mpv hwdec name), if it has one
/// that Kodi turns on by default.
String? _hwdecApi(String? os) => switch (os ?? Platform.operatingSystem) {
  'android' => 'mediacodec',
  'ios' => 'videotoolbox',
  // Kodi Windows 2.1: DXVA (D3D11VA) is the only accelerator, default on.
  // media_kit renders through ANGLE, which has no D3D11 decoder-surface interop
  // (mpv rejects zero-copy `d3d11va`, hwdec-current "no"): GPU decode + copy.
  'windows' => 'd3d11va-copy',
  _ => null,
};

String _flag(bool value) => value ? 'yes' : 'no';

/// mpv property values for the properties written by [scope]'s settings.
Map<String, String> engineOptionsFor(
  SettingsValues values, {
  required Set<SettingDef> scope,
  String? os,
}) {
  T read<T>(String id) => values.read<T>(settingById(id));
  final all = <String, String>{};

  all['speed'] = read<double>('playback.speed').toString();
  all['video-sync'] = read<bool>('playback.syncToDisplay')
      ? 'display-resample'
      : 'audio';
  all['audio-delay'] = read<double>('playback.avSyncCorrection').toString();

  // An Expert number that is not Auto overrides the preset's property.
  all.addAll(_cachePresets[read<String>('playback.cachePreset')]!);
  // Streaming's buffer size is the same property and wins when set.
  final streamingMb = read<double>('streaming.bufferSize');
  final cacheMb = streamingMb > 0
      ? streamingMb
      : read<double>('playback.demuxerCacheSize');
  if (cacheMb > 0) {
    all['demuxer-max-bytes'] = (cacheMb * 1024 * 1024).round().toString();
  }
  final readAhead = read<double>('playback.readAhead');
  if (readAhead > 0) all['demuxer-readahead-secs'] = readAhead.toString();
  final prebuffer = read<double>('streaming.prebuffer');
  all['cache-pause-wait'] = prebuffer > 0 ? prebuffer.toString() : '1';
  final timeout = read<double>('playback.networkTimeout');
  // Auto: 30 s, the transport range server's own wait for bytes it has not
  // fetched yet. media_kit's 5 s gave up on direct files before their first
  // bytes arrived (they come through 127.0.0.1 after aria2 fetches them).
  all['network-timeout'] = timeout > 0 ? timeout.toString() : '30';

  // The Advanced decoder choice overrides the hardware decoding choice.
  all['hwdec'] = switch ((
    read<String>('video.decoder'),
    read<String>('video.hwdec'),
  )) {
    ('hardware', _) => 'auto',
    ('software', _) => 'no',
    (_, 'On') => 'auto',
    (_, 'Off') => 'no',
    _ => 'auto-safe',
  };

  // Kodi enables MediaCodec (Android 2.1) / VideoToolbox (iOS 2.1) by default.
  final hwApi = _hwdecApi(os);
  if (hwApi != null && all['hwdec'] != 'no') all['hwdec'] = hwApi;

  final aspect = read<String>('video.aspectRatio');
  all['keepaspect'] = _flag(aspect != 'Stretch');
  all['panscan'] = aspect == 'Fill' ? '1.0' : '0.0';

  final scaling = read<String>('video.scalingQuality');
  final filter = scaling == 'High' ? 'ewa_lanczossharp' : 'bilinear';
  all['scale'] = filter;
  all['cscale'] = filter;
  all['dscale'] = scaling == 'High' ? 'mitchell' : 'bilinear';
  all['tone-mapping'] = read<String>('video.toneMapping');

  final pixelFormat = read<String>('video.pixelFormat');
  final chroma = _chromaFormat[read<String>('video.chroma')];
  final format = pixelFormat != 'auto' ? pixelFormat : chroma;
  all['vf'] = format == null ? '' : 'format=$format';
  // CPU format filters cannot consume MediaCodec's opaque surface frames.
  if (hwApi != null && all['hwdec'] != 'no' && format != null) {
    all['hwdec'] = hwApi.endsWith('-copy') ? hwApi : '$hwApi-copy';
  }
  final depth = read<String>('video.bitDepth');
  all['dither-depth'] = depth == 'auto' ? 'no' : depth;
  all['dither'] = read<String>('video.dithering');
  all['interpolation'] = _flag(read<bool>('video.interpolation'));
  all['deband'] = _flag(read<bool>('video.debanding'));
  all['vd-lavc-threads'] = read<double>('performance.decoderThreads')
      .round()
      .toString();
  all['gpu-api'] = read<String>('video.gpuRendering');

  // "zoom,panX,panY"; anything left out stays at 0.
  final calibration = read<String>('display.calibration')
      .split(',')
      .map((part) => part.trim())
      .toList();
  String part(int index) =>
      index < calibration.length && calibration[index].isNotEmpty
      ? calibration[index]
      : '0';
  all['video-zoom'] = part(0);
  all['video-pan-x'] = part(1);
  all['video-pan-y'] = part(2);

  // GPU quality and the mode overwrite options the user may have set, so
  // changing either re-applies every explicit setting after them.
  final owners = scope.where((d) => _levelOwners.contains(d.id)).toList();
  final android = hwApi != null;
  final rest = {
    ...scope,
    if (owners.isNotEmpty) ...changedEngineSettings(values, os: os),
    // Live CPU filter edits also switch decode output, including a reset.
    if (android &&
        scope.any(
          (def) => def.id == 'video.pixelFormat' || def.id == 'video.chroma',
        ))
      settingById('video.hwdec'),
  };
  return {
    if (owners.isNotEmpty) ..._gpuLevelFor(values),
    // Kodi uses software when MediaCodec cannot decode the source.
    if (android &&
        rest.any(
          (def) => def.id == 'video.hwdec' || def.id == 'video.decoder',
        )) ...{
      'vd-lavc-software-fallback': 'yes',
      // Remove the CPU filter before restoring opaque surface output.
      if (format == null &&
          rest.any(
            (def) => def.id == 'video.pixelFormat' || def.id == 'video.chroma',
          ))
        'vf': all['vf']!,
      'hwdec': all['hwdec']!,
    },
    for (final def in rest)
      for (final property in _propertiesOf[def.id] ?? const <String>[])
        property: all[property]!,
  };
}

const _levelOwners = {'performance.mode', 'performance.gpuQuality'};

// mpv 0.36 has the gpu-hq profile but no `fast` profile, and a profile cannot
// be switched back on a running engine, so the three levels are written as
// explicit options (the gpu-hq list is the engine's own, from `profile-list`).
const Map<String, String> _levelAuto = {
  'scale': 'bilinear',
  'cscale': 'bilinear',
  'dscale': 'bilinear',
  'dither': 'fruit',
  'correct-downscaling': 'no',
  'linear-downscaling': 'no',
  'sigmoid-upscaling': 'no',
  'deband': 'no',
};
const Map<String, String> _levelFast = {
  'scale': 'bilinear',
  'cscale': 'bilinear',
  'dscale': 'bilinear',
  'dither': 'no',
  'correct-downscaling': 'no',
  'linear-downscaling': 'no',
  'sigmoid-upscaling': 'no',
  'deband': 'no',
};
const Map<String, String> _levelHigh = {
  'scale': 'spline36',
  'cscale': 'spline36',
  'dscale': 'mitchell',
  'dither-depth': 'auto',
  'correct-downscaling': 'yes',
  'linear-downscaling': 'yes',
  'sigmoid-upscaling': 'yes',
  'deband': 'yes',
};

/// The option set of the chosen GPU quality; Auto follows the mode (Battery
/// saver = Fast, Quality = High, Auto = the engine's defaults).
Map<String, String> _gpuLevelFor(SettingsValues values) {
  final mode = values.read<String>(settingById('performance.mode'));
  final level = switch ((
    values.read<String>(settingById('performance.gpuQuality')),
    mode,
  )) {
    ('Fast', _) || ('Auto', 'Battery saver') => _levelFast,
    ('High', _) || ('Auto', 'Quality') => _levelHigh,
    _ => _levelAuto,
  };
  return {...level, if (mode == 'Battery saver') 'interpolation': 'no'};
}

/// What happens when a video ends and an opening video finds saved progress.
enum ResumeMode { ask, always, never }

ResumeMode resumeModeOf(SettingsValues values) =>
    switch (values.read<String>(settingById('playback.resume'))) {
      'Always' => ResumeMode.always,
      'Never' => ResumeMode.never,
      _ => ResumeMode.ask,
    };

bool autoPlayNextOf(SettingsValues values) =>
    values.read<bool>(settingById('playback.autoPlayNext'));

bool rememberPositionOf(SettingsValues values) =>
    values.read<bool>(settingById('playback.rememberPosition'));

/// Whether the window should be in native fullscreen.
bool fullscreenOf(SettingsValues values) =>
    values.read<String>(settingById('display.fullscreenMode')) == 'Fullscreen';

/// The HDR handling choice. Force SDR in either HDR setting wins; HDR10 or
/// Dolby Vision output and Passthrough HDR pass HDR sources through.
HdrPolicy hdrPolicyOf(SettingsValues values) {
  final hdr = values.read<String>(settingById('video.hdr'));
  final output = values.read<String>(settingById('display.hdrOutputMode'));
  if (hdr == 'Force SDR' || output == 'SDR') return HdrPolicy.forceSdr;
  if (hdr == 'Passthrough HDR' ||
      output == 'HDR10' ||
      output == 'Dolby Vision') {
    return HdrPolicy.passthrough;
  }
  return HdrPolicy.auto;
}

/// Whether the display is matched to the video, and how.
({bool enabled, DisplayMatchOptions options}) displayMatchingOf(
  SettingsValues values,
) {
  final rate = values.read<String>(settingById('video.matchFrameRate'));
  final refresh = values.read<String>(settingById('display.refreshRate'));
  return (
    enabled: rate != 'Off',
    options: DisplayMatchOptions(
      matchResolution:
          values.read<String>(settingById('video.matchResolution')) == 'Auto',
      whitelist: DisplayModeWhitelist.parse(
        values.read<String>(settingById('video.displayModeWhitelist')),
      ),
      forcedRefreshHz: refresh == 'auto' ? null : double.parse(refresh),
      rematchOnChange: rate == 'Always',
    ),
  );
}

/// Audio settings override the inputs of the existing fallback chain.
AudioPlanOverrides audioPlanOverridesFor(
  SettingsValues values, {
  String? os,
  int? maxChannels,
  Map<String, Object> nextVideo = const {},
}) {
  T read<T>(String id) => nextVideo.containsKey(id)
      ? nextVideo[id] as T
      : values.read<T>(settingById(id));
  bool? choice(String id) => switch (read<String>(id)) {
    'Enabled' => true,
    'Disabled' => false,
    _ => null,
  };
  const codecs = {
    'dolbyDigital': AudioFormat.ac3,
    'ddPlus': AudioFormat.eac3,
    'dts': AudioFormat.dts,
    'trueHd': AudioFormat.trueHd,
    'dtsHd': AudioFormat.dtsHd,
  };
  final system = os ?? Platform.operatingSystem;
  final audioTrack = system == 'android';
  // Windows probes the WASAPI endpoint like Android probes AudioTrack.
  final sinkProbed = audioTrack || system == 'windows';
  return AudioPlanOverrides(
    restrictToSinkFormats: sinkProbed,
    // iOS: session maximum (Kodi iOS sink is stereo until the session says more).
    pcmChannelLimit: audioTrack
        ? 8
        : (system == 'ios' || system == 'windows' ? maxChannels ?? 2 : null),
    passthrough:
        system == 'windows' && read<String>('audio.outputMode') == 'Fixed'
        ? 'Disabled'
        : read<String>('audio.passthrough'),
    receiverFormats: {
      for (final entry in codecs.entries)
        if (sinkProbed
            ? choice('audio.receiver.${entry.key}') != false
            : choice('audio.receiver.${entry.key}') == true)
          entry.value,
    },
    multichannelLpcm: choice('audio.multichannelLpcm'),
    ac3Transcoding: choice('audio.ac3Transcode'),
    layoutChannels: switch (read<String>('audio.speakerLayout')) {
      'Stereo' => 2,
      '5.1' => 6,
      '7.1' => 8,
      _ => null,
    },
    receiverAtmos: sinkProbed || choice('audio.receiver.atmos') == true,
    receiverDtsX: sinkProbed || choice('audio.receiver.dtsX') == true,
  );
}

final audioSettingDefs = {
  for (final def in settingDefs)
    if (def.section == SettingSection.audio &&
        def.id != preferredAudioLanguageSetting.id)
      def,
};

/// An unavailable saved device remains saved, but playback uses Auto.
AudioDevice? selectedAudioDevice(
  SettingsValues values,
  List<AudioDevice> devices, {
  bool bitstream = false,
  AppLogger? logger,
  Map<String, Object> nextVideo = const {},
}) {
  var id = values.read<String>(settingById('audio.outputDevice'));
  final passthrough =
      nextVideo['audio.passthroughDevice'] as String? ??
      values.read<String>(settingById('audio.passthroughDevice'));
  if (bitstream && passthrough.isNotEmpty) id = passthrough;
  if (id == 'Auto' || id.isEmpty) {
    return devices.where((device) => device.isCurrent).firstOrNull;
  }
  final device = devices.where((device) => device.id == id).firstOrNull;
  if (device != null) return device;
  logger?.warn('Saved audio output "$id" is unavailable; using Auto');
  return null;
}

String selectedAudioDeviceId(
  SettingsValues values,
  List<AudioDevice> devices, {
  bool bitstream = false,
  Map<String, Object> nextVideo = const {},
  String? passthroughDefault,
}) {
  var id = values.read<String>(settingById('audio.outputDevice'));
  final passthrough =
      nextVideo['audio.passthroughDevice'] as String? ??
      values.read<String>(settingById('audio.passthroughDevice'));
  if (bitstream && passthroughDefault != null) {
    // Windows resolves an unavailable or PCM-only request to a capable endpoint.
    id = passthroughDefault;
  } else if (bitstream && passthrough.isNotEmpty) {
    id = passthrough;
  }
  return devices.any((d) => d.id == id) ? id : 'auto';
}

/// Actual Windows pan output presented to the unchanged audio planner.
int? audioFilterOutputChannelsFor(
  SettingsValues values, {
  String? os,
  int? sourceChannels,
  int? maxChannels,
  AudioCapabilityModel? model,
  Map<String, Object> nextVideo = const {},
}) {
  final upmix =
      nextVideo['audio.stereoUpmix'] as bool? ??
      values.read<bool>(settingById('audio.stereoUpmix'));
  if ((os ?? Platform.operatingSystem) != 'windows' ||
      !upmix ||
      sourceChannels != 2) {
    return sourceChannels;
  }
  final o = audioPlanOverridesFor(
    values,
    os: 'windows',
    maxChannels: maxChannels,
    nextVideo: nextVideo,
  );
  final layout = o.layoutChannels ?? 2;
  final limit = o.multichannelLpcm == false ? 2 : o.pcmChannelLimit ?? 2;
  final target = min(layout, limit);
  if (target >= 8) return 8;
  if (target >= 6) return 6;
  if (layout <= 2 &&
      o.passthrough != 'Disabled' &&
      o.ac3Transcoding == true &&
      o.receiverFormats.contains(AudioFormat.ac3) &&
      model?.formats.contains(AudioFormat.ac3) == true) {
    return 6;
  }
  return 2;
}

const kodiStereoUpmix =
    'lavfi=[pan=7.1|FL=FL|FR=FR|FC=0.5*FL+0.5*FR|LFE=0.5*FL+0.5*FR'
    '|BL=FL|BR=FR|SL=FL|SR=FR]';

/// All audio properties are resolved together so filters and the fallback plan
/// never overwrite one another during a live change.
Map<String, String> audioEngineOptionsFor(
  SettingsValues values, {
  String? os,
  AudioPlan? plan,
  MediaInfo? info,
  AudioDevice? device,
  String deviceId = 'auto',
  Map<String, Object> nextVideo = const {},
}) {
  T read<T>(String id) => nextVideo.containsKey(id)
      ? nextVideo[id] as T
      : values.read<T>(settingById(id));
  final system = os ?? Platform.operatingSystem;
  final audioTrack = system == 'android';
  final windows = system == 'windows';
  final filters = <String>[];
  // Kodi macOS 1.8: stereo-only source; FL/BL/SL = L, FR/BR/SR = R, FC/LFE = (L+R)/2.
  if (read<bool>('audio.stereoUpmix') && info?.audioChannels == 2) {
    if (!windows || (plan?.channels ?? 2) > 2) {
      filters.add(
        windows && plan?.channels == 6
            ? kodiStereoUpmix
                  .replaceFirst('pan=7.1', 'pan=5.1')
                  .replaceFirst('|SL=FL|SR=FR', '')
            : kodiStereoUpmix,
      );
    }
  }
  if (plan != null && plan.af.isNotEmpty) filters.add(plan.af);
  final mode = read<String>('audio.outputMode');
  final selectedRate = read<String>('audio.sampleRate');
  var rate = mode == 'Fixed' && selectedRate != 'Auto'
      ? int.parse(selectedRate)
      : 0;
  final sourceRate = info?.audioSampleRate;
  final rates = device?.supportedSampleRates ?? const <int>[];
  if (mode == 'Optimized' &&
      sourceRate != null &&
      rates.isNotEmpty &&
      !rates.contains(sourceRate) &&
      sourceRate % 11025 == 0) {
    final candidate = sourceRate ~/ 11025 * 12000;
    if (rates.contains(candidate)) rate = candidate;
  }
  if ((audioTrack || windows) && rates.isNotEmpty) {
    final requested = rate > 0 ? rate : sourceRate;
    if (requested != null && !rates.contains(requested)) {
      int score(int s) =>
          (requested - s).abs() +
          8 * (s > requested ? s % requested : requested % s);
      rate = rates.reduce((a, b) => score(a) <= score(b) ? a : b);
    }
  }
  final quality = read<String>('audio.resamplingQuality');
  final resample = <String>[
    if (audioTrack || windows)
      ...switch (quality) {
        'Fast' => ['filter_size=32', 'cutoff=0.97'],
        'High' => ['filter_size=256', 'cutoff=1.0'],
        _ => ['filter_size=64', 'cutoff=0.985'],
      },
  ];
  final dialogue = read<double>('audio.downmixDialogue');
  // FFmpeg's centre mix level is linear amplitude; 0 dB keeps its sqrt(0.5)
  // baseline, and each user dB adds gain relative to that baseline.
  final centre = 0.7071067811865476 * pow(10, dialogue / 20);
  final keepAlive = read<bool>('audio.deviceKeepAlive');
  return {
    if (audioTrack) ...{
      // Production AudioTrack output; never select a physical AudioDeviceInfo id.
      'ao': 'audiotrack',
      // Kodi uses S16 for multichannel (multichannel float is opt-in).
      'audio-format': (plan?.channels ?? info?.audioChannels ?? 2) > 2
          ? 's16'
          : 'float',
    },
    // Production WASAPI output (Kodi's Windows sink); device ids are mpv's
    // `wasapi/<endpoint id>` names.
    if (windows) 'ao': 'wasapi',
    'audio-device': deviceId,
    'audio-channels':
        (mode != 'Fixed' ? plan?.audioChannels : null) ??
        switch (read<String>('audio.speakerLayout')) {
          'Stereo' => 'stereo',
          '5.1' => '5.1',
          '7.1' => '7.1',
          _ => 'auto-safe',
        },
    // Windows has no probed model before the plan exists; an unprobed carrier
    // sent to a PCM-only endpoint would stall the open (Kodi 1.5.8: only
    // probed streams are bitstreamed), so the plan alone decides.
    'audio-spdif':
        (windows && mode == 'Fixed' ? '' : plan?.audioSpdif) ??
        (windows
            ? ''
            : trackRulesFor(
                values,
                nextVideo: nextVideo,
              ).passthroughCodecs.join(',')),
    'af': filters.join(','),
    // Kodi 1.10: normalizelevels = !maintainoriginalvolume (downmix gain only).
    'audio-normalize-downmix': _flag(read<bool>('audio.normalizeVolume')),
    'audio-swresample-o': [
      if (dialogue > 0) 'center_mix_level=$centre',
      ...resample,
    ].join(','),
    'audio-resample-filter-size': switch (read<String>(
      'audio.resamplingQuality',
    )) {
      'Fast' => '8',
      'High' => '32',
      _ => '16',
    },
    'audio-samplerate': rate.toString(),
    'audio-exclusive': _flag(read<bool>('audio.exclusiveMode')),
    'audio-stream-silence': _flag(keepAlive),
    'gapless-audio': keepAlive ? 'yes' : 'weak',
    'keep-open': _flag(keepAlive),
  };
}

final subtitleSettingDefs = {
  for (final def in settingDefs)
    if (def.section == SettingSection.subtitles && def.target is MpvProperty)
      def,
};

Map<String, String> subtitleEngineOptionsFor(
  SettingsValues values, {
  Set<SettingDef>? scope,
}) {
  final size = subtitleSizes[values.read<String>(defaultSubtitleSizeSetting)]!;
  final result = <String, String>{
    'sub-font': values.read<String>(settingById('subtitles.font')).isEmpty
        ? 'DejaVu Sans'
        : values.read<String>(settingById('subtitles.font')),
    'sub-font-size': (42 * size).toString(),
    'sub-scale': '1',
    // Kodi's 4.95% margin in mpv's 720-high scaled pixels (integer).
    'sub-margin-y': (720 * 0.0495).round().toString(),
    'sub-use-margins': 'yes',
    'sub-pos': values
        .read<double>(settingById('subtitles.position'))
        .round()
        .toString(),
    'sub-border-size': values
        .read<double>(settingById('subtitles.border'))
        .toString(),
    'sub-shadow-offset': values
        .read<double>(settingById('subtitles.shadow'))
        .toString(),
    'sub-back-color': values.read<bool>(settingById('subtitles.background'))
        ? '#CC000000'
        : '#00000000',
    'sub-ass-override': switch (values.read<String>(
      settingById('subtitles.assStyling'),
    )) {
      'Embedded' => 'no',
      'Override' => 'force',
      _ => 'yes',
    },
    'sub-codepage': values.read<String>(settingById('subtitles.encoding')),
    'sub-delay': values.read<double>(settingById('subtitles.delay')).toString(),
  };
  if (scope == null) return result;
  final keys = {
    for (final def in scope) (def.target as MpvProperty).name,
    if (scope.any((def) => def.id == 'subtitles.position')) ...[
      'sub-margin-y',
      'sub-use-margins',
    ],
    if (scope.contains(defaultSubtitleSizeSetting)) ...[
      'sub-font-size',
      'sub-scale',
    ],
  };
  return {
    for (final entry in result.entries)
      if (keys.contains(entry.key)) entry.key: entry.value,
  };
}

TrackRules trackRulesFor(
  SettingsValues values, {
  AppLogger? logger,
  Map<String, Object> nextVideo = const {},
}) {
  T read<T>(String id) => nextVideo.containsKey(id)
      ? nextVideo[id] as T
      : values.read<T>(settingById(id));
  PlayerLanguage? language(String id) {
    final code = read<String>(id);
    if (code == 'forced_only') {
      return const PlayerLanguage('forced_only', 'Forced only', {});
    }
    return playerLanguages.where((l) => l.code == code).firstOrNull;
  }

  final priority = <String>[];
  for (final token in read<String>('languages.trackPriority').split(',')) {
    final rule = token.trim();
    if (rule.isEmpty) continue;
    if (trackPriorityError(rule) == null) {
      priority.add(rule);
    } else {
      logger?.warn('Ignoring invalid track priority token: $rule');
    }
  }
  return TrackRules(
    audioLanguage: language('playback.preferredAudioLanguage'),
    subtitleLanguage: language('playback.preferredSubtitleLanguage'),
    preferOriginal: read<bool>('languages.preferOriginalAudio'),
    autoSubtitles: read<bool>('subtitles.autoEnable'),
    hearingImpaired: read<String>('subtitles.hearingImpaired'),
    preferForced: read<bool>('languages.preferForcedSubtitles'),
    forcedBehaviour: read<String>('subtitles.forcedBehaviour'),
    passthroughCodecs:
        read<String>('audio.passthrough') == 'Enabled' &&
            read<String>('audio.speakerLayout') != 'Stereo'
        ? {
            for (final entry in const {
              'dolbyDigital': 'ac3',
              'ddPlus': 'eac3',
              'dts': 'dts',
              'trueHd': 'truehd',
              'dtsHd': 'dts-hd',
            }.entries)
              if (read<String>('audio.receiver.${entry.key}') == 'Enabled')
                entry.value,
          }
        : const {},
    quality: read<List<String>>('languages.preferBestAudio'),
    priority: priority,
    allowAtmos:
        read<String>('audio.passthrough') != 'Enabled' ||
        read<String>('audio.receiver.atmos') == 'Enabled',
  );
}

/// The Advanced "Custom mpv options" text as options (one `name=value` per
/// line, `#` comments, a leading `--` allowed) and the lines that are not in
/// that form, which mpv never sees.
({Map<String, String> options, Map<String, String> malformed})
parseCustomMpvOptions(String text) {
  final options = <String, String>{};
  final malformed = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final at = line.indexOf('=');
    final name = at < 0
        ? ''
        : line.substring(0, at).trim().replaceFirst(RegExp('^--'), '');
    if (name.isEmpty) {
      malformed[line] = 'expected name=value';
      continue;
    }
    options[name] = line.substring(at + 1).trim();
  }
  return (options: options, malformed: malformed);
}
