import 'package:intl/intl.dart';

import '../l10n/app_text.dart';
import '../l10n_gen/app_strings.dart';
import '../platform/adaptive_behavior.dart';
import '../components/app_row.dart';
import '../navigation/page_top_inset.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../components/ambient_background.dart';
import '../navigation/app_page_route.dart';
import '../navigation/page_back_button.dart';
import '../navigation/page_entry_focus.dart';
import '../theme/rivulet_tokens.dart';
import 'diagnostics_screen.dart';
import 'settings_catalog.dart';
import 'settings_controls.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

const List<int> _skipForwardSeconds = <int>[10, 30, 60];

/// The Settings screen, built from [settingDefs]: ten sections, Basic /
/// Advanced / Expert visibility, every value persisted through [settings].
///
/// [available] holds the capabilities this platform has; a setting that
/// requires one that is absent is never shown.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.settings,
    required this.capabilities,
    required this.available,
    this.playbackDiagnostics = const <String, String>{},
    this.liveDiagnostics,
    this.audioDevices = const <AudioDevice>[],
    this.displayChoices = const <String, String>{},
    this.displayChoicesListenable,
    this.settingNotes = const <String, String>{},
    this.onClearCache,
    this.providersPage,
    this.section,
    this.logDirectory,
    super.key,
  });

  final SettingSection? section;

  /// Shown on the diagnostics page so the log files can be found.
  final String? logDirectory;
  final AppSettings settings;
  final CapabilityReport capabilities;
  final Set<SettingCapability> available;
  final Map<String, String> playbackDiagnostics;

  /// Live playback rows; when set, the diagnostics page follows them.
  final ValueListenable<Map<String, String>>? liveDiagnostics;
  final List<AudioDevice> audioDevices;
  final Map<String, String> displayChoices;
  final ValueListenable<Map<String, String>>? displayChoicesListenable;
  final Map<String, String> settingNotes;

  /// Deletes the cached data of streams that are not open and returns the
  /// bytes freed. Without it the Clear cache row is not shown.
  final Future<int> Function()? onClearCache;

  /// Settings → Providers (accounts, sign-in, Buy); listed first when set.
  final WidgetBuilder? providersPage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppSettings get _settings => widget.settings;

  Map<String, String> get _displayChoices =>
      widget.displayChoicesListenable?.value ?? widget.displayChoices;

  final FocusNode _firstSection = FocusNode(debugLabel: 'first-section');
  PageEntry? _entry;

  @override
  void initState() {
    super.initState();
    widget.displayChoicesListenable?.addListener(_refresh);
    if (widget.section == null) {
      _entry = PageEntryFocus.register(context, _firstSection);
    }
  }

  @override
  void didUpdateWidget(covariant SettingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayChoicesListenable != widget.displayChoicesListenable) {
      oldWidget.displayChoicesListenable?.removeListener(_refresh);
      widget.displayChoicesListenable?.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _entry?.release(_firstSection);
    _firstSection.dispose();
    widget.displayChoicesListenable?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _setAdvanced(bool value) async {
    await _settings.setShowAdvanced(value);
    _refresh();
  }

  Future<void> _setExpert(bool value) async {
    await _settings.setShowExpert(value);
    _refresh();
  }

  void _openDiagnostics() => pushAndRestoreFocus<void>(
    Navigator.of(context),
    AppPageRoute<void>(
      builder: (_) => DiagnosticsScreen(
        report: widget.capabilities,
        playbackDiagnostics: widget.playbackDiagnostics,
        live: widget.liveDiagnostics,
        logDirectory: widget.logDirectory,
      ),
    ),
  );

  /// Settings that predate the schema and keep their storage keys.
  List<Widget> _legacyRows(SettingSection section) {
    switch (section) {
      case SettingSection.playback:
        return <Widget>[
          SettingChoiceRow(
            key: const ValueKey<String>('skip-forward-setting'),
            title: AppStrings.of(context).settings_skipForward,
            value: _settings.skipForward.inSeconds.toString(),
            options: <String>[for (final s in _skipForwardSeconds) '$s'],
            labelOf: (v) => AppStrings.of(context).settings_seconds(
              NumberFormat(
                '0',
                AppStrings.of(context).localeName,
              ).format(int.parse(v)),
            ),
            onChanged: (v) async {
              await _settings.setSkipForward(Duration(seconds: int.parse(v)));
              _refresh();
            },
          ),
        ];
      case SettingSection.advanced:
        return <Widget>[
          if (_settings.showAdvanced)
            SettingToggleRow(
              key: const ValueKey<String>('verbose-logging-switch'),
              title: AppStrings.of(context).settings_verboseLogging,
              value: _settings.verboseLogging,
              onChanged: (v) async {
                await _settings.setVerboseLogging(v);
                _refresh();
              },
            ),
        ];
      default:
        return const <Widget>[];
    }
  }

  String? _settingNote(SettingDef def) {
    if (widget.settingNotes.containsKey(def.id)) {
      return widget.settingNotes[def.id];
    }
    if (def.id == 'audio.outputDevice' || def.id == 'audio.passthroughDevice') {
      final saved = _settings.values.read<String>(def);
      if (saved.isNotEmpty &&
          saved != 'Auto' &&
          !widget.audioDevices.any((device) => device.id == saved)) {
        return AppStrings.of(context).settings_deviceUnavailable;
      }
    }
    if (def.id == 'audio.passthrough' &&
        _settings.values.read<String>(def) == 'Enabled' &&
        !<String>['dolbyDigital', 'ddPlus', 'dts', 'trueHd', 'dtsHd'].any(
          (id) =>
              _settings.values.read<String>(
                settingById('audio.receiver.$id'),
              ) ==
              'Enabled',
        )) {
      return AppStrings.of(context).settings_noReceiverFormats;
    }
    return null;
  }

  List<Widget> _rows(SettingSection section) {
    final strings = AppStrings.of(context);
    final windows = widget.capabilities.diagnostics['os'] == 'windows';
    final fixed =
        _settings.values.read<String>(settingById('audio.outputMode')) ==
        'Fixed';
    final stereo =
        _settings.values.read<String>(settingById('audio.speakerLayout')) ==
        'Stereo';
    final iec = widget.capabilities.diagnostics['audioPcmIsIec958'] == 'true';
    final passthrough = widget.capabilities.audioPassthrough && !fixed;
    final selected = _settings.values.read<String>(
      settingById('audio.outputDevice'),
    );
    final selectedExists = widget.audioDevices.any((d) => d.id == selected);
    final passthroughIds =
        widget.capabilities.diagnostics['audioPassthroughDevices']
            ?.split('\n')
            .toSet() ??
        <String>{};
    return <Widget>[
      ..._legacyRows(section),
      for (final def in visibleSettings(
        section,
        os: widget.capabilities.diagnostics['os'],
        showAdvanced: _settings.showAdvanced,
        showExpert: _settings.showExpert,
        available: windows && fixed
            ? widget.available.difference({SettingCapability.audioPassthrough})
            : widget.available,
        passthroughFormats: switch (widget.capabilities.diagnostics['os']) {
          'android' || 'windows' => widget.capabilities.passthroughFormats,
          // Kodi macOS 1.5.2: the E-AC3 tick box is hidden (darwin.xml).
          'macos' =>
            widget.capabilities.passthroughFormats
                .where((format) => format != 'eac3')
                .toList(),
          _ => null,
        },
      ))
        if (!windows ||
            (def.id != 'audio.passthroughDevice' || passthrough) &&
                (def.id != 'audio.stereoUpmix' ||
                    widget.capabilities.audioPassthrough ||
                    !stereo) &&
                (def.id != 'audio.speakerLayout' || !iec) &&
                (def.id != 'audio.sampleRate' || fixed || iec) &&
                (def.id != 'audio.ac3Transcode' ||
                    (stereo || iec) &&
                        _settings.values.read<String>(
                              settingById('audio.receiver.dolbyDigital'),
                            ) !=
                            'Disabled'))
          SettingRow(
            key: ValueKey<String>('setting-${def.id}'),
            def: def,
            values: _settings.values,
            onChanged: _refresh,
            onOpenPage: _openDiagnostics,
            choices:
                def.id == 'display.refreshRate' &&
                    widget.capabilities.diagnostics['os'] == 'android'
                ? <String, String>{
                    'auto': AppStrings.of(context).common_auto,
                    for (final rate
                        in (widget
                                    .capabilities
                                    .diagnostics['display.refreshRates'] ??
                                '')
                            .split(','))
                      if (double.tryParse(rate) case final value?
                          when value.isFinite && value > 0)
                        rate: choiceLabel(def, rate, strings),
                  }
                : def.id == 'display.monitor' && _displayChoices.isNotEmpty
                ? _displayChoices
                : def.id == 'audio.outputDevice' ||
                      def.id == 'audio.passthroughDevice'
                ? <String, String>{
                    'Auto': AppStrings.of(context).common_auto,
                    for (final device in widget.audioDevices)
                      if (!windows ||
                          def.id != 'audio.passthroughDevice' ||
                          passthroughIds.contains(device.id))
                        device.id: device.name,
                  }
                : def.id == 'audio.sampleRate' &&
                      const {
                        'android',
                        'ios',
                        'windows',
                      }.contains(widget.capabilities.diagnostics['os'])
                ? <String, String>{
                    'Auto': AppStrings.of(context).common_auto,
                    for (final device in widget.audioDevices)
                      if (device.id == selected ||
                          (!selectedExists && device.isCurrent))
                        for (final rate in device.supportedSampleRates)
                          '$rate': choiceLabel(def, '$rate', strings),
                  }
                : null,
            note: _settingNote(def),
          ),
      if (section == SettingSection.streaming && widget.onClearCache != null)
        SettingActionRow(
          key: const ValueKey<String>('clear-cache'),
          title: AppStrings.of(context).settings_clearCache,
          run: () async => _freed(await widget.onClearCache!(), strings),
        ),
    ];
  }

  static String _freed(int bytes, AppStrings strings) {
    const mib = 1024 * 1024;
    if (bytes < mib) return strings.settings_nothingToClear;
    if (bytes < 1024 * mib) {
      return strings.settings_freedMb(
        NumberFormat('0', strings.localeName).format((bytes / mib).round()),
      );
    }
    return strings.settings_freedGb(
      NumberFormat('0.0', strings.localeName).format(bytes / (1024 * mib)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      for (final section in SettingSection.values)
        if (section != SettingSection.advanced || _settings.showAdvanced)
          section,
    ];
    final profile = AdaptiveBehavior.of(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    final gutter = RivuletSpacing.gutter(profile.formFactor);
    final gap = RivuletSpacing.rowGap(profile.formFactor);
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            FocusTraversalGroup(
              policy: ReadingOrderTraversalPolicy(),
              child: SingleChildScrollView(
                key: widget.section == null
                    ? const ValueKey<String>('settings-root-scroll')
                    : ValueKey<String>('detail-${widget.section!.name}'),
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  pageTopInsetOf(context),
                  gutter,
                  gutter,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sizes.settingsContentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText(
                          widget.section == null
                              ? AppStrings.of(context).common_settings
                              : sectionInfo(
                                  AppStrings.of(context),
                                )[widget.section]!.$1,
                          style: RivuletTokens.of(context).typeStyles.title,
                        ),
                        SizedBox(height: gap),
                        widget.section == null
                            ? _sectionList(sections)
                            : _detail(widget.section!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (widget.section != null) const PageBackButton(),
          ],
        ),
      ),
    );
  }

  /// One row of the top-level list (same look as the section rows below).
  Widget _sectionRow({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onActivate,
    FocusNode? focusNode,
  }) => AppRow(
    key: key,
    focusNode: focusNode,
    label: label,
    icon: icon,
    caret: true,
    onActivate: onActivate,
  );

  Widget _sectionList(List<SettingSection> sections) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppRowGroup(
        children: [
          if (widget.providersPage case final page?)
            _sectionRow(
              key: const ValueKey<String>('section-providers'),
              focusNode: _firstSection,
              label: AppStrings.of(context).settings_providers,
              icon: PhosphorIconsRegular.plugs,
              onActivate: () => pushAndRestoreFocus<void>(
                Navigator.of(context),
                AppPageRoute<void>(builder: page),
              ),
            ),
          for (final section in sections)
            _sectionRow(
              key: ValueKey<String>('section-${section.name}'),
              focusNode:
                  widget.providersPage == null && section == sections.first
                  ? _firstSection
                  : null,
              label: sectionInfo(AppStrings.of(context))[section]!.$1,
              icon: sectionInfo(AppStrings.of(context))[section]!.$2,
              onActivate: () => pushAndRestoreFocus<void>(
                Navigator.of(context),
                AppPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    settings: widget.settings,
                    capabilities: widget.capabilities,
                    available: widget.available,
                    playbackDiagnostics: widget.playbackDiagnostics,
                    liveDiagnostics: widget.liveDiagnostics,
                    logDirectory: widget.logDirectory,
                    audioDevices: widget.audioDevices,
                    displayChoices: widget.displayChoices,
                    displayChoicesListenable: widget.displayChoicesListenable,
                    settingNotes: widget.settingNotes,
                    onClearCache: widget.onClearCache,
                    section: section,
                  ),
                ),
              ),
            ),
        ],
      ),
      SizedBox(
        height: RivuletSpacing.rowGap(AdaptiveBehavior.of(context).formFactor),
      ),
      AppRowGroup(
        children: [
          _languageRow(),
          SettingToggleRow(
            key: const ValueKey<String>('advanced-toggle'),
            title: AppStrings.of(context).settings_advancedSettings,
            value: _settings.showAdvanced,
            onChanged: _setAdvanced,
          ),
          if (_settings.showAdvanced)
            SettingToggleRow(
              key: const ValueKey<String>('expert-toggle'),
              title: AppStrings.of(context).settings_expert,
              value: _settings.showExpert,
              onChanged: _setExpert,
            ),
          _sectionRow(
            key: const ValueKey<String>('diagnostics-row'),
            label: AppStrings.of(context).settings_diagnostics,
            icon: PhosphorIconsRegular.info,
            onActivate: _openDiagnostics,
          ),
        ],
      ),
    ],
  );

  Widget _languageRow() {
    final strings = AppStrings.of(context);
    return SettingChoiceRow(
      key: const ValueKey<String>('setting-app.language'),
      title: strings.settings_language_title,
      value: _settings.language,
      options: appLanguageSetting.choices,
      labelOf: (code) => switch (code) {
        'en' => strings.settings_language_en,
        'fa' => strings.settings_language_fa,
        _ => strings.settings_language_system,
      },
      onChanged: (code) async {
        await _settings.setLanguage(code);
        _refresh();
      },
    );
  }

  Widget _detail(SettingSection section) =>
      AppRowGroup(children: _rows(section));
}
