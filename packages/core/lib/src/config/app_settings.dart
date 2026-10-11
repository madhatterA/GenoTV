import '../logging/app_logger.dart';
import 'settings_schema.dart';
import 'settings_store.dart';
import 'settings_values.dart';

/// A language offered for the preferred audio/subtitle settings. [aliases] are
/// the tags tracks carry for it (ISO 639-1 and both 639-2 forms).
class PlayerLanguage {
  const PlayerLanguage(this.code, this.name, this.aliases);

  final String code;
  final String name;
  final Set<String> aliases;

  bool matches(String? tag) =>
      tag != null &&
      aliases.contains(tag.toLowerCase().split(RegExp('[-_]')).first);
}

const List<PlayerLanguage> playerLanguages = <PlayerLanguage>[
  PlayerLanguage('en', 'English', {'en', 'eng'}),
  PlayerLanguage('fa', 'Persian', {'fa', 'fas', 'per'}),
  PlayerLanguage('ar', 'Arabic', {'ar', 'ara'}),
  PlayerLanguage('fr', 'French', {'fr', 'fra', 'fre'}),
  PlayerLanguage('de', 'German', {'de', 'deu', 'ger'}),
  PlayerLanguage('es', 'Spanish', {'es', 'spa'}),
  PlayerLanguage('tr', 'Turkish', {'tr', 'tur'}),
  PlayerLanguage('ru', 'Russian', {'ru', 'rus'}),
  PlayerLanguage('ja', 'Japanese', {'ja', 'jpn'}),
  PlayerLanguage('ko', 'Korean', {'ko', 'kor'}),
  PlayerLanguage('zh', 'Chinese', {'zh', 'zho', 'chi'}),
];

/// Subtitle size names and their font multipliers (shared with the player's
/// Subtitles → Size choice).
const Map<String, double> subtitleSizes = <String, double>{
  'Small': 0.75,
  'Normal': 1.0,
  'Large': 1.25,
  'Extra large': 1.5,
};

/// Stored keys of removed settings; dropped silently on load.
const List<String> retiredSettingKeys = <String>[
  'video.deinterlace',
  'video.sdrToHdr',
  'video.hwdecDevice',
  'performance.gpuContext',
  'performance.maxDecoderResolution',
  'performance.mpvOverrides',
  'streaming.dns',
  'downloads.location',
  'downloads.concurrent',
  'downloads.sequential',
  'downloads.httpConnections',
  'downloads.pieceCache',
];

/// Typed accessors over a [SettingsStore]. Only the keys Part 01 knows are
/// needed exist here — other Parts add their own keys in their own Phases
/// using the same store.
///
/// No credentials: source credentials and player preferences live in a
/// separate secure settings boundary owned by Part 06
/// (`research/ui/interaction-notes/README.md`), not designed yet.
class AppSettings {
  AppSettings(this._store, {AppLogger? logger})
    : _values = SettingsValues(_store, logger: logger);

  final SettingsStore _store;
  final SettingsValues _values;

  static const String _keyLastVolume = 'playback.lastVolume';
  static const String _keySkipForward = 'playback.skipForwardSeconds';
  static const String _keyVerboseLogging = 'diagnostics.verboseLogging';
  static const String _keyShowAdvanced = 'settings.ui.showAdvanced';
  static const String _keyShowExpert = 'settings.ui.showExpert';

  Future<void> load() async {
    await _store.load();
    // Settings the bundled engine cannot honour were removed (ENGINE_UNSUPPORTED.md).
    for (final key in retiredSettingKeys) {
      if (_store.read(key) != null) await _store.delete(key);
    }
    const key = 'subtitles.hearingImpaired';
    final old = _store.read(key);
    if (old == 'true' || old == 'false') {
      await _store.write(key, old == 'true' ? 'Prefer' : 'No preference');
    }
  }

  /// Typed read/write of every [settingDefs] value (the Settings screen).
  SettingsValues get values => _values;

  /// Settings screen "Advanced Settings" toggle.
  bool get showAdvanced => _store.read(_keyShowAdvanced) == 'true';
  Future<void> setShowAdvanced(bool value) =>
      _store.write(_keyShowAdvanced, value.toString());

  /// Settings screen "Expert" toggle (only offered while Advanced is on).
  bool get showExpert => _store.read(_keyShowExpert) == 'true';
  Future<void> setShowExpert(bool value) =>
      _store.write(_keyShowExpert, value.toString());

  double get lastVolume =>
      double.tryParse(_store.read(_keyLastVolume) ?? '') ?? 1.0;
  Future<void> setLastVolume(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'must be between 0.0 and 1.0');
    }
    return _store.write(_keyLastVolume, value.toString());
  }

  Duration get skipForward =>
      Duration(seconds: int.tryParse(_store.read(_keySkipForward) ?? '') ?? 30);

  Future<void> setSkipForward(Duration value) {
    if (value <= Duration.zero) {
      throw ArgumentError.value(value, 'value', 'must be positive');
    }
    return _store.write(_keySkipForward, value.inSeconds.toString());
  }

  /// `system`, `en` or `fa`.
  String get language => _values.read<String>(appLanguageSetting);
  Future<void> setLanguage(String code) =>
      _values.write(appLanguageSetting, code);

  bool get verboseLogging => _store.read(_keyVerboseLogging) == 'true';
  Future<void> setVerboseLogging(bool value) =>
      _store.write(_keyVerboseLogging, value.toString());

  /// Language code from [playerLanguages]; null = original/first track.
  String? get preferredAudioLanguage =>
      _language(preferredAudioLanguageSetting);
  Future<void> setPreferredAudioLanguage(String? code) =>
      _writeLanguage(preferredAudioLanguageSetting, code);

  /// Language code or forced_only (Kodi default); null = subtitles Off.
  String? get preferredSubtitleLanguage =>
      _language(preferredSubtitleLanguageSetting);
  Future<void> setPreferredSubtitleLanguage(String? code) =>
      _values.write(preferredSubtitleLanguageSetting, code ?? '');

  /// A key of [subtitleSizes].
  String get defaultSubtitleSize =>
      _values.read<String>(defaultSubtitleSizeSetting);

  Future<void> setDefaultSubtitleSize(String size) =>
      _values.write(defaultSubtitleSizeSetting, size);

  String? _language(SettingDef def) {
    final code = _values.read<String>(def);
    return code.isEmpty ? null : code;
  }

  Future<void> _writeLanguage(SettingDef def, String? code) =>
      code == null ? _values.reset(def) : _values.write(def, code);
}
