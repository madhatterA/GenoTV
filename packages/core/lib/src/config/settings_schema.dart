import 'dart:io';

import 'app_settings.dart';

/// Android AudioTrack and iOS AudioUnit defaults from Kodi; stored user
/// choices take precedence.
String defaultSettingValue(String id, String fallback, {String? os}) =>
    switch (os ?? Platform.operatingSystem) {
      // Kodi iOS 1.2/1.4/1.5: 2.0 layout, 48000 Hz, no passthrough.
      'ios' => switch (id) {
        'audio.speakerLayout' => 'Stereo',
        'audio.passthrough' || 'audio.ac3Transcode' => 'Disabled',
        'audio.sampleRate' => '48000',
        _ => fallback,
      },
      // Kodi Windows 1.2/1.4/1.5 defaults equal Android's: 2.0, 48000, no
      // passthrough, every receiver tick box on.
      'android' || 'windows' => switch (id) {
        'audio.speakerLayout' => 'Stereo',
        'audio.passthrough' || 'audio.ac3Transcode' => 'Disabled',
        'audio.receiver.dolbyDigital' ||
        'audio.receiver.ddPlus' ||
        'audio.receiver.dts' ||
        'audio.receiver.dtsHd' ||
        'audio.receiver.trueHd' => 'Enabled',
        'audio.sampleRate' => '48000',
        _ => fallback,
      },
      _ => fallback,
    };

/// The ten sections of the owner review §1, in source order.
enum SettingSection {
  playback,
  video,
  audio,
  subtitles,
  display,
  streaming,
  downloads,
  languages,
  performance,
  advanced,
}

/// Visibility level: the source's unprefixed / "Adv:" / "Exp:" items.
enum SettingTier { basic, advanced, expert }

enum SettingKind {
  toggle,
  choice,
  number,
  text,
  path,

  /// Multi-select; stored comma-joined, every element one of [SettingDef.choices].
  list,

  /// Read-only diagnostics page (§1.10); holds no value.
  page,
}

/// The one platform-capability rule of a setting. A setting whose capability
/// the platform lacks is hidden (evaluated against real capabilities in 1.2).
enum SettingCapability {
  none,
  displayModeSwitching,

  /// Refresh-rate control over the mode list (Kodi iOS 4.3/4.4/4.6: none; every
  /// mode has refresh 0.0).
  refreshRateControl,
  hdrOutput,
  audioPassthrough,
  audioDeviceSelection,
  exclusiveAudio,
  multipleDisplays,
  desktopWindow,

  /// The user can pick the renderer backend (iOS: GLES via EAGL only, Kodi 3.1).
  gpuBackend,
}

/// When a changed value takes effect.
enum SettingApply { live, nextVideo, restart }

/// What a setting maps to. Names are declarations only in this phase.
sealed class SettingTarget {
  const SettingTarget(this.name);
  final String name;
}

class MpvProperty extends SettingTarget {
  const MpvProperty(super.name);
}

class TransportOption extends SettingTarget {
  const TransportOption(super.name);
}

class PlatformCall extends SettingTarget {
  const PlatformCall(super.name);
}

class AppBehaviour extends SettingTarget {
  const AppBehaviour(super.description);
}

/// One setting. [id] is also its [SettingsStore] key. [sourceItems] are the
/// owner-review lines it covers, as `"<section number> | <item text>"`
/// (`test/fixtures/settings_source_items.txt`).
class SettingDef {
  const SettingDef({
    required this.id,
    required this.section,
    required this.kind,
    required this.defaultValue,
    required this.target,
    required this.sourceItems,
    this.alsoIn = const [],
    this.tier = SettingTier.basic,
    this.choices = const [],
    this.requires = SettingCapability.none,
    this.apply = SettingApply.nextVideo,
    this.min,
    this.max,
    this.step,
    this.unit,
  });

  final String id;
  final SettingSection section;
  final List<SettingSection> alsoIn;
  final SettingTier tier;
  final SettingKind kind;
  final List<String> choices;

  /// The stored-string form of the default (`true`/`false`, a number, a
  /// choice, comma-joined list, text).
  final String defaultValue;
  final SettingCapability requires;
  final SettingApply apply;

  /// Number settings: the allowed range, the stepper increment and the unit
  /// shown beside the value.
  final double? min;
  final double? max;
  final double? step;
  final String? unit;
  final SettingTarget target;
  final List<String> sourceItems;
}

const _adv = SettingTier.advanced;
const _exp = SettingTier.expert;
const _live = SettingApply.live;
const _toggle = SettingKind.toggle;
const _choice = SettingKind.choice;
const _number = SettingKind.number;
const _text = SettingKind.text;
const _list = SettingKind.list;

const _auto3 = ['Auto', 'Enabled', 'Disabled'];

/// Existing keys (no migration): language and subtitle-size defaults.
final SettingDef preferredAudioLanguageSetting = SettingDef(
  id: 'playback.preferredAudioLanguage',
  section: SettingSection.audio,
  alsoIn: const [SettingSection.languages],
  kind: _choice,
  choices: [for (final l in playerLanguages) l.code],
  defaultValue: '', // empty = original / first track
  apply: SettingApply.nextVideo,
  target: const AppBehaviour('track selection: preferred audio language'),
  sourceItems: const [
    '3 | Preferred audio language',
    '8 | Preferred audio language',
  ],
);

final SettingDef preferredSubtitleLanguageSetting = SettingDef(
  id: 'playback.preferredSubtitleLanguage',
  section: SettingSection.subtitles,
  alsoIn: const [SettingSection.languages],
  kind: _choice,
  choices: ['', 'forced_only', for (final l in playerLanguages) l.code],
  defaultValue: 'forced_only', // Kodi: forced tracks in the audio language
  apply: SettingApply.nextVideo,
  target: const AppBehaviour('track selection: preferred subtitle language'),
  sourceItems: const [
    '4 | Preferred language',
    '8 | Preferred subtitle language',
  ],
);

final SettingDef defaultSubtitleSizeSetting = SettingDef(
  id: 'playback.defaultSubtitleSize',
  section: SettingSection.subtitles,
  kind: _choice,
  choices: subtitleSizes.keys.toList(),
  defaultValue: 'Normal',
  apply: _live,
  target: const MpvProperty('sub-scale'),
  sourceItems: const ['4 | Font / size / position'],
);

/// App language (Part 06 ch04). Not a Kodi source item, so it is outside
/// [settingDefs] and shown on the Settings root, not in a section. Kodi
/// `locale.language` defaults to English; ours defaults to the system language.
const SettingDef appLanguageSetting = SettingDef(
  id: 'app.language',
  section: SettingSection.languages,
  kind: _choice,
  choices: ['system', 'en', 'fa'],
  defaultValue: 'system',
  apply: _live,
  target: AppBehaviour('UI language'),
  sourceItems: ['app | Language'],
);

/// Every setting, section by section in source order.
final List<SettingDef> settingDefs = List.unmodifiable(<SettingDef>[
  // 1. Playback
  const SettingDef(
    id: 'playback.resume',
    section: SettingSection.playback,
    kind: _choice,
    choices: ['Ask', 'Always', 'Never'],
    defaultValue: 'Ask',
    target: AppBehaviour('resume prompt'),
    sourceItems: ['1 | Resume playback (Ask / Always / Never)'],
  ),
  const SettingDef(
    id: 'playback.autoPlayNext',
    section: SettingSection.playback,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: AppBehaviour('start next episode at end'),
    sourceItems: ['1 | Auto-play next episode'],
  ),
  const SettingDef(
    id: 'playback.rememberPosition',
    section: SettingSection.playback,
    kind: _toggle,
    defaultValue: 'true',
    apply: _live,
    target: AppBehaviour('save and restore watch position'),
    sourceItems: ['1 | Remember position'],
  ),
  const SettingDef(
    id: 'playback.speed',
    section: SettingSection.playback,
    kind: _number,
    min: 0.25,
    max: 4.0,
    step: 0.25,
    unit: '×',
    defaultValue: '1.0',
    apply: _live,
    target: MpvProperty('speed'),
    sourceItems: ['1 | Preferred playback speed'],
  ),
  const SettingDef(
    id: 'playback.syncToDisplay',
    section: SettingSection.playback,
    tier: _adv,
    kind: _toggle,
    defaultValue: 'false',
    target: MpvProperty('video-sync'),
    sourceItems: ['1 | Adv: Sync playback to display'],
  ),
  const SettingDef(
    id: 'playback.avSyncCorrection',
    section: SettingSection.playback,
    tier: _adv,
    kind: _number,
    min: -5.0,
    max: 5.0,
    step: 0.1,
    unit: 's',
    defaultValue: '0',
    apply: _live,
    target: MpvProperty('audio-delay'),
    sourceItems: ['1 | Adv: A/V sync correction'],
  ),
  const SettingDef(
    id: 'playback.cachePreset',
    section: SettingSection.playback,
    tier: _adv,
    kind: _choice,
    choices: ['Low latency', 'Balanced', 'Large'],
    defaultValue: 'Balanced',
    target: MpvProperty('cache-secs'),
    sourceItems: [
      '1 | Adv: Cache/buffer preset (Low latency / Balanced / Large)',
    ],
  ),
  const SettingDef(
    id: 'playback.demuxerCacheSize',
    section: SettingSection.playback,
    tier: _exp,
    kind: _number,
    min: 0.0,
    max: 2048.0,
    step: 16.0,
    unit: 'MB',
    defaultValue: '0',
    target: MpvProperty('demuxer-max-bytes'),
    sourceItems: ['1 | Exp: demuxer/cache size, read-ahead, network timeout'],
  ),
  const SettingDef(
    id: 'playback.readAhead',
    section: SettingSection.playback,
    tier: _exp,
    kind: _number,
    min: 0.0,
    max: 300.0,
    step: 5.0,
    unit: 's',
    defaultValue: '0',
    target: MpvProperty('demuxer-readahead-secs'),
    sourceItems: ['1 | Exp: demuxer/cache size, read-ahead, network timeout'],
  ),
  const SettingDef(
    id: 'playback.networkTimeout',
    section: SettingSection.playback,
    tier: _exp,
    kind: _number,
    min: 0.0,
    max: 120.0,
    step: 5.0,
    unit: 's',
    defaultValue: '0',
    target: MpvProperty('network-timeout'),
    sourceItems: ['1 | Exp: demuxer/cache size, read-ahead, network timeout'],
  ),

  // 2. Video
  const SettingDef(
    id: 'video.hwdec',
    section: SettingSection.video,
    alsoIn: [SettingSection.performance],
    kind: _choice,
    choices: ['Auto', 'On', 'Off'],
    defaultValue: 'Auto',
    target: MpvProperty('hwdec'),
    sourceItems: [
      '2 | Hardware decoding (Auto / On / Off)',
      '9 | Hardware acceleration (Auto)',
    ],
  ),
  const SettingDef(
    id: 'video.hdr',
    section: SettingSection.video,
    alsoIn: [SettingSection.display],
    kind: _choice,
    choices: ['Auto', 'Force SDR', 'Passthrough HDR'],
    defaultValue: 'Auto',
    requires: SettingCapability.hdrOutput,
    target: PlatformCall('hdrOutput'),
    sourceItems: [
      '2 | HDR (Auto / Force SDR / Passthrough HDR)',
      '5 | Match content dynamic range',
    ],
  ),
  const SettingDef(
    id: 'video.matchFrameRate',
    section: SettingSection.video,
    alsoIn: [SettingSection.display],
    kind: _choice,
    choices: ['Off', 'On start-stop', 'Always'],
    defaultValue: 'On start-stop',
    requires: SettingCapability.refreshRateControl,
    target: PlatformCall('matchDisplay'),
    sourceItems: [
      '2 | Match frame rate (Off / On start-stop / Always)',
      '5 | Match content frame rate',
    ],
  ),
  const SettingDef(
    id: 'video.matchResolution',
    section: SettingSection.video,
    alsoIn: [SettingSection.display],
    kind: _choice,
    choices: ['Auto', 'Off'],
    defaultValue: 'Auto',
    requires: SettingCapability.displayModeSwitching,
    target: PlatformCall('matchDisplay'),
    sourceItems: ['2 | Match resolution (Auto / Off)', '5 | Adv: resolution'],
  ),
  const SettingDef(
    id: 'video.aspectRatio',
    section: SettingSection.video,
    kind: _choice,
    choices: ['Original', 'Fit', 'Fill', 'Stretch'],
    defaultValue: 'Original',
    apply: _live,
    target: MpvProperty('video-aspect-override, panscan'),
    sourceItems: ['2 | Aspect ratio (Original / Fit / Fill / Stretch)'],
  ),
  const SettingDef(
    id: 'video.decoder',
    section: SettingSection.video,
    tier: _adv,
    kind: _choice,
    choices: ['Auto', 'hardware', 'software'],
    defaultValue: 'Auto',
    target: MpvProperty('hwdec'),
    sourceItems: ['2 | Adv: video decoder (Auto / hardware / software)'],
  ),
  const SettingDef(
    id: 'video.scalingQuality',
    section: SettingSection.video,
    tier: _adv,
    kind: _choice,
    choices: ['Fast', 'Balanced', 'High'],
    defaultValue: 'Balanced',
    apply: _live,
    target: MpvProperty('scale, cscale, dscale'),
    sourceItems: ['2 | Adv: scaling quality (Fast / Balanced / High)'],
  ),
  const SettingDef(
    id: 'video.toneMapping',
    section: SettingSection.video,
    tier: _adv,
    kind: _choice,
    choices: [
      'auto',
      'clip',
      'mobius',
      'reinhard',
      'hable',
      'gamma',
      'linear',
      'spline',
      'bt.2390',
      'bt.2446a',
      'st2094-40',
      'st2094-10',
    ],
    defaultValue: 'auto',
    apply: _live,
    target: MpvProperty('tone-mapping'),
    sourceItems: ['2 | Adv: HDR→SDR tone mapping'],
  ),
  const SettingDef(
    id: 'video.pixelFormat',
    section: SettingSection.video,
    tier: _exp,
    kind: _choice,
    choices: [
      'auto',
      'nv12',
      'yuv420p',
      'yuv420p10',
      'yuv422p',
      'yuv422p10',
      'yuv444p',
      'yuv444p10',
      'rgb24',
    ],
    defaultValue: 'auto',
    target: MpvProperty('vf format'),
    sourceItems: ['2 | Exp: output pixel format / bit depth / chroma'],
  ),
  const SettingDef(
    id: 'video.bitDepth',
    section: SettingSection.video,
    tier: _exp,
    kind: _choice,
    choices: ['auto', '8', '10', '12'],
    defaultValue: 'auto',
    target: MpvProperty('dither-depth'),
    sourceItems: ['2 | Exp: output pixel format / bit depth / chroma'],
  ),
  const SettingDef(
    id: 'video.chroma',
    section: SettingSection.video,
    tier: _exp,
    kind: _choice,
    choices: ['auto', '4:2:0', '4:2:2', '4:4:4'],
    defaultValue: 'auto',
    target: MpvProperty('vf format'),
    sourceItems: ['2 | Exp: output pixel format / bit depth / chroma'],
  ),
  const SettingDef(
    id: 'video.dithering',
    section: SettingSection.video,
    tier: _exp,
    kind: _choice,
    choices: ['no', 'fruit', 'ordered'],
    defaultValue: 'no',
    apply: _live,
    target: MpvProperty('dither'),
    sourceItems: [
      '2 | Exp: dithering, interpolation, debanding, GPU rendering options',
    ],
  ),
  const SettingDef(
    id: 'video.interpolation',
    section: SettingSection.video,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: MpvProperty('interpolation'),
    sourceItems: [
      '2 | Exp: dithering, interpolation, debanding, GPU rendering options',
    ],
  ),
  const SettingDef(
    id: 'video.debanding',
    section: SettingSection.video,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: MpvProperty('deband'),
    sourceItems: [
      '2 | Exp: dithering, interpolation, debanding, GPU rendering options',
    ],
  ),
  const SettingDef(
    id: 'video.gpuRendering',
    section: SettingSection.video,
    tier: _exp,
    kind: _choice,
    choices: ['auto', 'opengl'],
    defaultValue: 'auto',
    requires: SettingCapability.gpuBackend,
    target: MpvProperty('gpu-api'),
    sourceItems: [
      '2 | Exp: dithering, interpolation, debanding, GPU rendering options',
    ],
  ),
  const SettingDef(
    id: 'video.displayModeWhitelist',
    section: SettingSection.video,
    alsoIn: [SettingSection.display],
    tier: _exp,
    kind: _text,
    defaultValue: '',
    requires: SettingCapability.refreshRateControl,
    target: PlatformCall('matchDisplay'),
    sourceItems: [
      '2 | Exp: allowed display modes / resolution whitelist',
      '5 | Exp: resolution + refresh-rate whitelist',
    ],
  ),

  // 3. Audio
  const SettingDef(
    id: 'audio.outputDevice',
    section: SettingSection.audio,
    kind: _choice,
    choices: [], // Actual platform audio device IDs are supplied by the app.
    defaultValue: 'Auto',
    apply: _live,
    requires: SettingCapability.audioDeviceSelection,
    target: MpvProperty('audio-device'),
    sourceItems: ['3 | Output device (Auto / HDMI / speakers / headphones)'],
  ),
  SettingDef(
    id: 'audio.speakerLayout',
    section: SettingSection.audio,
    kind: _choice,
    choices: ['Auto', 'Stereo', '5.1', '7.1'],
    defaultValue: defaultSettingValue('audio.speakerLayout', 'Auto'),
    target: MpvProperty('audio-channels'),
    sourceItems: ['3 | Speaker layout (Auto / Stereo / 5.1 / 7.1)'],
  ),
  preferredAudioLanguageSetting,
  const SettingDef(
    id: 'audio.normalizeVolume',
    section: SettingSection.audio,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: MpvProperty('audio-normalize-downmix'),
    sourceItems: ['3 | Normalize volume'],
  ),
  const SettingDef(
    id: 'audio.outputMode',
    section: SettingSection.audio,
    tier: _adv,
    kind: _choice,
    choices: ['Best Match', 'Fixed', 'Optimized'],
    defaultValue: 'Optimized',
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Adv: output mode (Best Match / Fixed / Optimized)'],
  ),
  SettingDef(
    id: 'audio.passthrough',
    section: SettingSection.audio,
    tier: _adv,
    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.passthrough', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Adv: passthrough (Auto / Enabled / Disabled)'],
  ),
  const SettingDef(
    id: 'audio.passthroughDevice',
    section: SettingSection.audio,
    tier: _adv,
    kind: _text,
    defaultValue: '',
    requires: SettingCapability.audioDeviceSelection,
    target: MpvProperty('audio-device'),
    sourceItems: ['3 | Adv: passthrough output device'],
  ),
  SettingDef(
    id: 'audio.receiver.dolbyDigital',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.receiver.dolbyDigital', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: Dolby Digital'],
  ),
  SettingDef(
    id: 'audio.receiver.ddPlus',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.receiver.ddPlus', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: DD+'],
  ),
  SettingDef(
    id: 'audio.receiver.dts',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.receiver.dts', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: DTS'],
  ),
  SettingDef(
    id: 'audio.receiver.trueHd',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.receiver.trueHd', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: TrueHD'],
  ),
  SettingDef(
    id: 'audio.receiver.dtsHd',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.receiver.dtsHd', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: DTS-HD'],
  ),
  const SettingDef(
    id: 'audio.receiver.atmos',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: 'Auto',
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: Atmos'],
  ),
  const SettingDef(
    id: 'audio.receiver.dtsX',
    section: SettingSection.audio,
    tier: _adv,

    kind: _choice,
    choices: _auto3,
    defaultValue: 'Auto',
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Receiver supports: DTS:X'],
  ),
  const SettingDef(
    id: 'audio.multichannelLpcm',
    section: SettingSection.audio,
    tier: _adv,
    kind: _choice,
    choices: _auto3,
    defaultValue: 'Auto',
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Adv: multichannel LPCM'],
  ),
  SettingDef(
    id: 'audio.ac3Transcode',
    section: SettingSection.audio,
    tier: _adv,
    kind: _choice,
    choices: _auto3,
    defaultValue: defaultSettingValue('audio.ac3Transcode', 'Auto'),
    requires: SettingCapability.audioPassthrough,
    target: PlatformCall('audioPlan'),
    sourceItems: ['3 | Adv: AC3 transcoding for unsupported multichannel'],
  ),
  const SettingDef(
    id: 'audio.stereoUpmix',
    section: SettingSection.audio,
    tier: _adv,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: MpvProperty('af surround'),
    sourceItems: ['3 | Adv: stereo upmix'],
  ),
  const SettingDef(
    id: 'audio.downmixDialogue',
    section: SettingSection.audio,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 12.0,
    step: 1.0,
    unit: 'dB',
    defaultValue: '0',
    apply: _live,
    target: MpvProperty('audio-swresample-o'),
    sourceItems: ['3 | Adv: downmix centre/dialogue level'],
  ),
  const SettingDef(
    id: 'audio.resamplingQuality',
    section: SettingSection.audio,
    tier: _adv,
    kind: _choice,
    choices: ['Fast', 'Balanced', 'High'],
    defaultValue: 'Balanced',
    target: MpvProperty('audio-resample-filter-size'),
    sourceItems: ['3 | Adv: resampling quality'],
  ),
  SettingDef(
    id: 'audio.sampleRate',
    section: SettingSection.audio,
    tier: _exp,
    kind: _choice,
    choices: [
      'Auto',
      '32000',
      '44100',
      '48000',
      '88200',
      '96000',
      '176400',
      '192000',
    ],
    defaultValue: defaultSettingValue('audio.sampleRate', 'Auto'),
    target: MpvProperty('audio-samplerate'),
    sourceItems: [
      '3 | Exp: output sample rate / exclusive mode / device keep-alive',
    ],
  ),
  const SettingDef(
    id: 'audio.exclusiveMode',
    section: SettingSection.audio,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'false',
    apply: SettingApply.restart,
    requires: SettingCapability.exclusiveAudio,
    target: MpvProperty('audio-exclusive'),
    sourceItems: [
      '3 | Exp: output sample rate / exclusive mode / device keep-alive',
    ],
  ),
  const SettingDef(
    id: 'audio.deviceKeepAlive',
    section: SettingSection.audio,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'true',
    apply: SettingApply.restart,
    requires: SettingCapability.exclusiveAudio,
    target: MpvProperty('audio-stream-silence'),
    sourceItems: [
      '3 | Exp: output sample rate / exclusive mode / device keep-alive',
    ],
  ),

  // 4. Subtitles
  preferredSubtitleLanguageSetting,
  const SettingDef(
    id: 'subtitles.autoEnable',
    section: SettingSection.subtitles,
    kind: _toggle,
    defaultValue: 'true',
    target: AppBehaviour('select a subtitle track on open'),
    sourceItems: ['4 | Auto-enable'],
  ),
  const SettingDef(
    id: 'subtitles.hearingImpaired',
    section: SettingSection.subtitles,
    kind: _choice,
    choices: ['Prefer', 'Avoid', 'No preference'],
    defaultValue: 'No preference',
    target: AppBehaviour('prefer SDH/CC subtitle tracks'),
    sourceItems: ['4 | Hearing-impaired preference'],
  ),
  const SettingDef(
    id: 'subtitles.font',
    section: SettingSection.subtitles,
    kind: _text,
    defaultValue: 'DejaVu Sans',
    apply: _live,
    target: MpvProperty('sub-font'),
    sourceItems: ['4 | Font / size / position'],
  ),
  defaultSubtitleSizeSetting,
  const SettingDef(
    id: 'subtitles.position',
    section: SettingSection.subtitles,
    kind: _number,
    min: 0.0,
    max: 100.0,
    step: 5.0,
    unit: '%',
    defaultValue: '100',
    apply: _live,
    target: MpvProperty('sub-pos'),
    sourceItems: ['4 | Font / size / position'],
  ),
  const SettingDef(
    id: 'subtitles.encoding',
    section: SettingSection.subtitles,
    kind: _choice,
    choices: [
      'auto',
      'utf-8',
      'cp1250',
      'cp1251',
      'cp1252',
      'cp1253',
      'cp1254',
      'cp1256',
      'iso-8859-1',
      'iso-8859-2',
      'shift_jis',
      'gbk',
      'big5',
      'euc-kr',
    ],
    defaultValue: 'auto',
    apply: _live,
    target: MpvProperty('sub-codepage'),
    sourceItems: ['4 | Text encoding'],
  ),
  const SettingDef(
    id: 'subtitles.border',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 10.0,
    step: 0.5,
    unit: 'px',
    defaultValue: '2.5',
    apply: _live,
    target: MpvProperty('sub-border-size'),
    sourceItems: ['4 | Adv: border/shadow/background'],
  ),
  const SettingDef(
    id: 'subtitles.shadow',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 10.0,
    step: 0.5,
    unit: 'px',
    defaultValue: '0',
    apply: _live,
    target: MpvProperty('sub-shadow-offset'),
    sourceItems: ['4 | Adv: border/shadow/background'],
  ),
  const SettingDef(
    id: 'subtitles.background',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: MpvProperty('sub-back-color'),
    sourceItems: ['4 | Adv: border/shadow/background'],
  ),
  const SettingDef(
    id: 'subtitles.delay',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _number,
    min: -10.0,
    max: 10.0,
    step: 0.1,
    unit: 's',
    defaultValue: '0',
    apply: _live,
    target: MpvProperty('sub-delay'),
    sourceItems: ['4 | Adv: delay'],
  ),
  const SettingDef(
    id: 'subtitles.forcedBehaviour',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _choice,
    choices: ['Auto', 'Always', 'Never'],
    defaultValue: 'Auto',
    target: AppBehaviour('forced subtitle selection'),
    sourceItems: ['4 | Adv: forced-subtitle behaviour'],
  ),
  const SettingDef(
    id: 'subtitles.assStyling',
    section: SettingSection.subtitles,
    tier: _adv,
    kind: _choice,
    choices: ['Embedded', 'Override', 'Hybrid'],
    defaultValue: 'Embedded',
    apply: _live,
    target: MpvProperty('sub-ass-override'),
    sourceItems: ['4 | Adv: ASS/SSA styling (Embedded / Override / Hybrid)'],
  ),

  // 5. Display (items shared with Video are defined above)
  const SettingDef(
    id: 'display.monitor',
    section: SettingSection.display,
    kind: _text,
    defaultValue: '',
    requires: SettingCapability.multipleDisplays,
    target: PlatformCall('selectDisplay'),
    sourceItems: ['5 | Display/monitor selection'],
  ),
  const SettingDef(
    id: 'display.fullscreenMode',
    section: SettingSection.display,
    kind: _choice,
    choices: ['Windowed', 'Fullscreen'],
    defaultValue: 'Windowed',
    apply: _live,
    requires: SettingCapability.desktopWindow,
    target: PlatformCall('windowMode'),
    sourceItems: ['5 | Fullscreen mode'],
  ),
  const SettingDef(
    id: 'display.refreshRate',
    section: SettingSection.display,
    tier: _adv,
    kind: _choice,
    choices: [
      'auto',
      '23.976',
      '24',
      '25',
      '29.97',
      '30',
      '50',
      '59.94',
      '60',
      '120',
    ],
    defaultValue: 'auto',
    requires: SettingCapability.refreshRateControl,
    target: PlatformCall('matchDisplay'),
    sourceItems: ['5 | Adv: refresh rate'],
  ),
  const SettingDef(
    id: 'display.hdrOutputMode',
    section: SettingSection.display,
    tier: _adv,
    kind: _choice,
    choices: ['Auto', 'SDR', 'HDR10', 'Dolby Vision'],
    defaultValue: 'Auto',
    requires: SettingCapability.hdrOutput,
    target: PlatformCall('hdrOutput'),
    sourceItems: ['5 | Adv: HDR output mode'],
  ),
  const SettingDef(
    id: 'display.calibration',
    section: SettingSection.display,
    tier: _adv,
    kind: _text,
    defaultValue: '',
    target: MpvProperty('video-zoom, video-pan-x, video-pan-y'),
    sourceItems: ['5 | Adv: screen calibration / overscan'],
  ),

  // 6. Streaming & Network
  const SettingDef(
    id: 'streaming.quality',
    section: SettingSection.streaming,
    kind: _choice,
    choices: ['Auto', 'Original', '20 Mbps', '8 Mbps', '4 Mbps', '2 Mbps'],
    defaultValue: 'Auto',
    target: TransportOption('bandwidthLimit'),
    sourceItems: ['6 | Streaming quality (Auto / Original / bandwidth limits)'],
  ),
  const SettingDef(
    id: 'streaming.protocol',
    section: SettingSection.streaming,
    kind: _choice,
    choices: ['Auto', 'HTTP', 'Torrent'],
    defaultValue: 'Auto',
    target: AppBehaviour('preferred source protocol'),
    sourceItems: ['6 | Preferred protocol (Auto)'],
  ),
  const SettingDef(
    id: 'streaming.cacheSizeLimit',
    section: SettingSection.streaming,
    kind: _choice,
    choices: ['Auto', '2 GB', '5 GB', '10 GB', '20 GB'],
    defaultValue: 'Auto',
    target: TransportOption('cacheSizeLimit'),
    sourceItems: ['6 | Cache size limit (Auto / 2 / 5 / 10 / 20 GB)'],
  ),
  const SettingDef(
    id: 'streaming.bufferSize',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 1024.0,
    step: 16.0,
    unit: 'MB',
    defaultValue: '0',
    target: MpvProperty('demuxer-max-bytes'),
    sourceItems: ['6 | Adv: buffer size'],
  ),
  const SettingDef(
    id: 'streaming.prebuffer',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 120.0,
    step: 5.0,
    unit: 's',
    defaultValue: '0',
    target: MpvProperty('cache-pause-wait'),
    sourceItems: ['6 | Adv: pre-buffer duration'],
  ),
  const SettingDef(
    id: 'streaming.maxHttpConnections',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 16.0,
    step: 1.0,
    unit: 'connections',
    defaultValue: '0',
    target: TransportOption('maxConnectionPerServer'),
    sourceItems: ['6 | Adv: max HTTP connections'],
  ),
  const SettingDef(
    id: 'streaming.connectionTimeout',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 120.0,
    step: 5.0,
    unit: 's',
    defaultValue: '0',
    target: TransportOption('connectTimeout'),
    sourceItems: ['6 | Adv: connection timeout / retry count'],
  ),
  const SettingDef(
    id: 'streaming.retryCount',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 10.0,
    step: 1.0,
    unit: 'retries',
    defaultValue: '0',
    target: TransportOption('retryCount'),
    sourceItems: ['6 | Adv: connection timeout / retry count'],
  ),
  const SettingDef(
    id: 'streaming.proxy',
    section: SettingSection.streaming,
    tier: _adv,
    kind: _text,
    defaultValue: '',
    target: TransportOption('proxy'),
    sourceItems: ['6 | Adv: DNS / proxy'],
  ),
  const SettingDef(
    id: 'streaming.userAgent',
    section: SettingSection.streaming,
    tier: _exp,
    kind: _text,
    defaultValue: '',
    target: TransportOption('userAgent'),
    sourceItems: ['6 | Exp: user-agent / custom HTTP headers / TLS options'],
  ),
  const SettingDef(
    id: 'streaming.headers',
    section: SettingSection.streaming,
    tier: _exp,
    kind: _text,
    defaultValue: '',
    target: TransportOption('headers'),
    sourceItems: ['6 | Exp: user-agent / custom HTTP headers / TLS options'],
  ),
  const SettingDef(
    id: 'streaming.tls',
    section: SettingSection.streaming,
    tier: _exp,
    kind: _choice,
    choices: ['Verify', "Don't verify"],
    defaultValue: 'Verify',
    target: TransportOption('tls'),
    sourceItems: ['6 | Exp: user-agent / custom HTTP headers / TLS options'],
  ),

  // 7. Downloads & Torrent
  const SettingDef(
    id: 'downloads.bandwidthLimit',
    section: SettingSection.downloads,
    kind: _number,
    min: 0.0,
    max: 100000.0,
    step: 250.0,
    unit: 'KB/s',
    defaultValue: '0',
    apply: _live,
    target: TransportOption('maxOverallDownloadLimit'),
    sourceItems: ['7 | Bandwidth limit'],
  ),
  const SettingDef(
    id: 'downloads.torrentDownLimit',
    section: SettingSection.downloads,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 100000.0,
    step: 250.0,
    unit: 'KB/s',
    defaultValue: '0',
    apply: _live,
    target: TransportOption('downloadRateLimit'),
    sourceItems: ['7 | Adv: torrent up/down limits'],
  ),
  const SettingDef(
    id: 'downloads.torrentUpLimit',
    section: SettingSection.downloads,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 100000.0,
    step: 250.0,
    unit: 'KB/s',
    defaultValue: '0',
    apply: _live,
    target: TransportOption('uploadRateLimit'),
    sourceItems: ['7 | Adv: torrent up/down limits'],
  ),
  const SettingDef(
    id: 'downloads.connectionLimit',
    section: SettingSection.downloads,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 2000.0,
    step: 10.0,
    unit: 'connections',
    defaultValue: '0',
    apply: _live,
    target: TransportOption('connectionsLimit'),
    sourceItems: ['7 | Adv: connection/peer limits'],
  ),
  const SettingDef(
    id: 'downloads.peerLimit',
    section: SettingSection.downloads,
    tier: _adv,
    kind: _number,
    min: 0.0,
    max: 500.0,
    step: 10.0,
    unit: 'peers',
    defaultValue: '0',
    target: TransportOption('peerLimit'),
    sourceItems: ['7 | Adv: connection/peer limits'],
  ),
  const SettingDef(
    id: 'downloads.seeding',
    section: SettingSection.downloads,
    tier: _adv,
    kind: _choice,
    choices: ['Off', 'ratio', 'duration'],
    defaultValue: 'Off',
    apply: _live,
    target: TransportOption('seedAfterCompletion'),
    sourceItems: ['7 | Adv: seed after completion (Off / ratio / duration)'],
  ),
  const SettingDef(
    id: 'downloads.tracker',
    section: SettingSection.downloads,
    tier: _exp,
    kind: _text,
    defaultValue: '',
    target: TransportOption('tracker'),
    sourceItems: ['7 | Exp: piece cache / tracker / DHT / PEX'],
  ),
  const SettingDef(
    id: 'downloads.dht',
    section: SettingSection.downloads,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'true',
    target: TransportOption('dht'),
    sourceItems: ['7 | Exp: piece cache / tracker / DHT / PEX'],
  ),
  const SettingDef(
    id: 'downloads.pex',
    section: SettingSection.downloads,
    tier: _exp,
    kind: _toggle,
    defaultValue: 'true',
    target: TransportOption('pex'),
    sourceItems: ['7 | Exp: piece cache / tracker / DHT / PEX'],
  ),

  // 8. Languages & Tracks (language items shared with Audio/Subtitles above)
  const SettingDef(
    id: 'languages.preferOriginalAudio',
    section: SettingSection.languages,
    kind: _toggle,
    defaultValue: 'false',
    target: AppBehaviour('track selection: original audio'),
    sourceItems: ['8 | Prefer original audio'],
  ),
  const SettingDef(
    id: 'languages.preferForcedSubtitles',
    section: SettingSection.languages,
    kind: _toggle,
    defaultValue: 'true',
    target: AppBehaviour('track selection: forced subtitles'),
    sourceItems: ['8 | Prefer forced subtitles'],
  ),
  const SettingDef(
    id: 'languages.preferBestAudio',
    section: SettingSection.languages,
    tier: _adv,
    kind: _list,
    choices: ['Atmos', 'lossless', 'highest-channel'],
    defaultValue: '',
    target: AppBehaviour('track selection: audio quality preference'),
    sourceItems: ['8 | Adv: prefer Atmos / lossless / highest-channel track'],
  ),
  const SettingDef(
    id: 'languages.trackPriority',
    section: SettingSection.languages,
    tier: _adv,
    kind: _text,
    defaultValue: '',
    target: AppBehaviour('track selection: priority rules'),
    sourceItems: ['8 | Adv: track-selection priority rules'],
  ),

  // 9. Performance (hardware acceleration shared with Video above)
  const SettingDef(
    id: 'performance.mode',
    section: SettingSection.performance,
    kind: _choice,
    choices: ['Auto', 'Battery saver', 'Quality'],
    defaultValue: 'Auto',
    target: AppBehaviour('performance preset'),
    sourceItems: ['9 | Performance mode (Auto / Battery saver / Quality)'],
  ),
  const SettingDef(
    id: 'performance.gpuQuality',
    section: SettingSection.performance,
    tier: _adv,
    kind: _choice,
    choices: ['Auto', 'Fast', 'High'],
    defaultValue: 'Auto',
    apply: _live,
    target: MpvProperty('profile'),
    sourceItems: ['9 | Adv: GPU rendering quality'],
  ),
  const SettingDef(
    id: 'performance.backgroundPreload',
    section: SettingSection.performance,
    tier: _adv,
    kind: _toggle,
    defaultValue: 'false',
    apply: _live,
    target: AppBehaviour('preload next episode'),
    sourceItems: ['9 | Adv: background preloading'],
  ),
  const SettingDef(
    id: 'performance.decoderThreads',
    section: SettingSection.performance,
    tier: _exp,
    kind: _number,
    min: 0.0,
    max: 32.0,
    step: 1.0,
    unit: 'threads',
    defaultValue: '0',
    apply: SettingApply.restart,
    target: MpvProperty('vd-lavc-threads'),
    sourceItems: ['9 | Exp: decoder threads / GPU context / mpv overrides'],
  ),

  // 10. Advanced
  const SettingDef(
    id: 'advanced.diagnostics',
    section: SettingSection.advanced,
    tier: _adv,
    kind: SettingKind.page,
    defaultValue: '',
    apply: _live,
    target: AppBehaviour('read-only live playback diagnostics page'),
    sourceItems: [
      '10 | Developer playback info: codec/decoder diagnostics, current video/audio format, dropped frames, bitrate, buffer state, HDR metadata, audio output mode, passthrough status',
    ],
  ),
  const SettingDef(
    id: 'advanced.customMpvOptions',
    section: SettingSection.advanced,
    tier: _adv,
    kind: _text,
    defaultValue: '',
    target: MpvProperty('custom options'),
    sourceItems: ['10 | Custom mpv options field'],
  ),
]);

/// The definition for [id]; throws [ArgumentError] when unknown.
SettingDef settingById(String id) => settingDefs.firstWhere(
  (d) => d.id == id,
  orElse: () => throw ArgumentError.value(id, 'id', 'unknown setting'),
);

/// Error shown beside the priority field; an empty list uses the default order.
String? trackPriorityError(String value) {
  for (final part in value.split(',')) {
    final token = part.trim();
    if (token.isEmpty && value.trim().isEmpty) return null;
    if (const {
      'original',
      'atmos',
      'lossless',
      'channels',
      'default',
    }.contains(token)) {
      continue;
    }
    if (RegExp(r'^lang:[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$').hasMatch(token)) {
      continue;
    }
    return 'Invalid rule "$token". Use lang:<code>, original, atmos, lossless, channels or default.';
  }
  return null;
}
