import 'package:intl/intl.dart';

import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';
import '../settings/settings_catalog.dart';
import '../focus/tv_text_entry.dart';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/focus_button.dart';
import '../components/orb_loader.dart';
import '../theme/rivulet_tokens.dart';
import 'info_insights_panels.dart';
import 'panel_row.dart';
import 'track_panel.dart';
import 'player_state_views.dart';

/// Current per-video choices; the player screen keeps them across panel dismissal.
class PlayerOptionValues {
  PlayerOptionValues({
    this.subtitleDelay = 0,
    this.audioDelay = 0,
    this.subtitleScale = 1,
    this.subtitlePosition = 100,
    this.aspect = 'Auto',
    this.fill = false,
    Object? video,
  }) : video = video ?? Object();
  final Object video;
  final int subtitleDelay;
  final int audioDelay;
  final double subtitleScale;
  final int subtitlePosition;
  final String aspect;
  final bool fill;

  PlayerOptionValues copyWith({
    int? subtitleDelay,
    int? audioDelay,
    double? subtitleScale,
    int? subtitlePosition,
    String? aspect,
    bool? fill,
  }) => PlayerOptionValues(
    subtitleDelay: subtitleDelay ?? this.subtitleDelay,
    audioDelay: audioDelay ?? this.audioDelay,
    subtitleScale: subtitleScale ?? this.subtitleScale,
    subtitlePosition: subtitlePosition ?? this.subtitlePosition,
    aspect: aspect ?? this.aspect,
    fill: fill ?? this.fill,
    video: video,
  );
}

/// Only the source name is needed by the approved source-list stub.
class SubtitleSource {
  const SubtitleSource(this.name);
  final String name;
}

/// One online subtitle offered in the Subtitles → Download list.
class UiSubtitleResult {
  const UiSubtitleResult({
    required this.id,
    required this.service,
    required this.language,
    required this.release,
    required this.uploader,
    required this.hearingImpaired,
  });
  final String id;
  final String service;
  final String language;
  final String release;
  final String uploader;
  final bool hearingImpaired;
}

/// What a subtitle search found; [notSignedIn] are service names to sign in to.
class UiSubtitleSearch {
  const UiSubtitleSearch(this.results, this.notSignedIn);
  final List<UiSubtitleResult> results;
  final List<String> notSignedIn;
}

class SubtitleSourcesPanel extends StatelessWidget {
  const SubtitleSourcesPanel({
    required this.sources,
    required this.onBack,
    super.key,
  });
  final List<SubtitleSource> sources;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      FocusButton(
        key: const ValueKey('subtitle-sources-back'),
        variant: FocusButtonVariant.row,
        label: AppStrings.of(context).player_backToSubtitles,
        onActivate: onBack,
      ),
      Expanded(
        child: ListView(
          children: [
            if (sources.isEmpty)
              AppText(AppStrings.of(context).player_noSubtitleSources)
            else
              for (final source in sources) AppText(source.name),
          ],
        ),
      ),
    ],
  );
}

/// The message for an online-subtitle failure (en + fa); anything that is not
/// a provider failure falls through to the player's own messages.
String subtitleFailureMessage(AppFailure failure, AppStrings strings) =>
    switch (failure.code) {
      'provider.auth_required' => strings.player_subtitleAuthFailed,
      'provider.quota_reached' => strings.player_subtitleQuotaReached,
      'provider.network' ||
      'provider.unavailable' ||
      'provider.invalid_response' => strings.player_subtitleServiceDown,
      'provider.not_found' => strings.player_noSubtitlesFound,
      _ => playerFailureMessage(failure, strings),
    };

/// Search results for the playing title; tap one to download and load it.
class OnlineSubtitlesPanel extends StatefulWidget {
  const OnlineSubtitlesPanel({
    required this.search,
    required this.onPick,
    required this.onBack,
    super.key,
  });
  final Future<UiSubtitleSearch> Function() search;
  final Future<void> Function(UiSubtitleResult) onPick;
  final VoidCallback onBack;

  @override
  State<OnlineSubtitlesPanel> createState() => _OnlineSubtitlesPanelState();
}

class _OnlineSubtitlesPanelState extends State<OnlineSubtitlesPanel> {
  late final Future<UiSubtitleSearch> _search = widget.search();
  bool _busy = false;
  String? _failure;

  static const _names = {'fa': 'فارسی', 'en': 'English'};

  Future<void> _pick(UiSubtitleResult result) async {
    if (_busy) return;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await widget.onPick(result);
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is AppFailure
              ? subtitleFailureMessage(error, strings)
              : strings.player_subtitleDownloadFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FocusButton(
          key: const ValueKey('subtitle-sources-back'),
          variant: FocusButtonVariant.row,
          label: strings.player_backToSubtitles,
          onActivate: widget.onBack,
        ),
        if (_failure != null) AppText(_failure!),
        Expanded(
          child: FutureBuilder<UiSubtitleSearch>(
            future: _search,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                final error = snapshot.error;
                return AppText(
                  error is AppFailure
                      ? subtitleFailureMessage(error, strings)
                      : strings.player_subtitleSearchFailed,
                );
              }
              final found = snapshot.data;
              if (found == null) return const Center(child: OrbLoader.small());
              return ListView(
                children: [
                  if (found.notSignedIn.isNotEmpty)
                    AppText(
                      strings.player_subtitleSignIn(
                        found.notSignedIn.join(', '),
                      ),
                    ),
                  if (found.results.isEmpty) AppText(strings.player_noSubtitlesFound),
                  for (final r in found.results)
                    FocusButton(
                      key: ValueKey('online-subtitle-${r.service}-${r.id}'),
                      variant: FocusButtonVariant.row,
                      enabled: !_busy,
                      label:
                          '${_names[r.language] ?? r.language.toUpperCase()} · '
                          '${r.release}${r.hearingImpaired ? ' · HI' : ''}'
                          ' · ${r.uploader.isEmpty ? r.service : r.uploader}',
                      onActivate: () => _pick(r),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Composes the existing player panels; never pauses or replaces the surface.
class PlayerBoxOptions extends StatefulWidget {
  const PlayerBoxOptions({
    required this.controller,
    required this.state,
    required this.dismiss,
    required this.options,
    required this.mediaInfo,
    this.audioOutput,
    this.subtitleSources = const [],
    this.onAddSubtitleFiles,
    this.onSearchSubtitles,
    this.onFetchSubtitle,
    super.key,
  });
  final Future<List<({String name, Uri uri})>> Function()? onAddSubtitleFiles;

  /// Online subtitles: search for the playing title, then fetch (download,
  /// unzip, stage) the chosen one. Both null keeps the old empty source list.
  final Future<UiSubtitleSearch> Function()? onSearchSubtitles;
  final Future<List<({String name, Uri uri})>> Function(UiSubtitleResult)?
  onFetchSubtitle;
  final PlaybackController controller;
  final PlaybackState state;
  final VoidCallback dismiss;
  final ValueNotifier<PlayerOptionValues> options;
  final MediaInfo mediaInfo;
  final ValueListenable<String?>? audioOutput;
  final List<SubtitleSource> subtitleSources;
  @override
  State<PlayerBoxOptions> createState() => _PlayerBoxOptionsState();
}

class _PlayerBoxOptionsState extends State<PlayerBoxOptions> {
  String _section = 'Subtitles';
  final TextEditingController _subtitleUri = TextEditingController();
  String? _failure;
  bool _busy = false;
  bool _sourcesOpen = false;

  @override
  void dispose() {
    _subtitleUri.dispose();
    super.dispose();
  }

  Future<void> _addSubtitle() async {
    final uri = Uri.tryParse(_subtitleUri.text.trim());
    if (uri == null ||
        !((uri.scheme == 'https' || uri.scheme == 'http') &&
                uri.host.isNotEmpty ||
            uri.scheme == 'file' &&
                uri.path.startsWith('/') &&
                uri.path.length > 1)) {
      setState(() => _failure = AppStrings.of(context).player_subtitleUriError);
      return;
    }
    await _run(() => widget.controller.addExternalSubtitle(uri));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final strings = AppStrings.of(context);
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is PlaybackFailure
              ? playerFailureMessage(error, strings)
              : strings.player_optionFailed(error.toString()),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choice(String key, String label, bool selected, VoidCallback action) {
    final tokens = RivuletTokens.of(context);
    return PanelRow(
      key: ValueKey(key),
      tokens: tokens,
      compact: true,
      selected: selected,
      onTap: _busy ? null : action,
      child: AppText(
        label,
        style: tokens.typeStyles.panelRow.copyWith(
          fontSize: 16,
          color: PanelRow.foregroundColor(tokens, selected: selected),
        ),
      ),
    );
  }

  Widget _choices(String label, List<Widget> choices) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppText(label, style: RivuletTokens.of(context).typeStyles.label),
      Wrap(
        spacing: 4,
        children: [for (final choice in choices) IntrinsicWidth(child: choice)],
      ),
    ],
  );

  Future<void> _apply(
    Future<void> Function() action,
    PlayerOptionValues Function(PlayerOptionValues) update,
  ) => _run(() async {
    final previous = widget.options.value;
    await action();
    // An open event can reset the video while the old command completes.
    if (identical(widget.options.value.video, previous.video)) {
      widget.options.value = update(widget.options.value);
    }
  });

  Widget _delay({required bool subtitle}) {
    final values = widget.options.value;
    final value = subtitle ? values.subtitleDelay : values.audioDelay;
    final step = subtitle ? 100 : 50;
    final limit = subtitle ? 10000 : 5000;
    final prefix = subtitle ? 'subtitle-delay' : 'audio-delay';
    Future<void> change(int next) => _apply(
      () => (subtitle
          ? widget.controller.setSubtitleDelay
          : widget.controller.setAudioDelay)(Duration(milliseconds: next)),
      (current) => subtitle
          ? current.copyWith(subtitleDelay: next)
          : current.copyWith(audioDelay: next),
    );
    return Row(
      children: [
        Expanded(
          child: AppText(
            AppStrings.of(context).player_delay(
              AppStrings.of(context).localeName == 'fa'
                  ? NumberFormat(
                      subtitle ? '0.0' : '0.00',
                      'fa',
                    ).format(value / 1000)
                  : (value / 1000).toStringAsFixed(subtitle ? 1 : 2),
            ),
          ),
        ),
        IconButton(
          key: ValueKey('$prefix-minus'),
          tooltip: subtitle
              ? AppStrings.of(context).player_decreaseSubtitleDelay
              : AppStrings.of(context).player_decreaseAudioDelay,
          onPressed: _busy || value <= -limit
              ? null
              : () => change(value - step),
          icon: const Icon(PhosphorIconsRegular.minus),
        ),
        IconButton(
          key: ValueKey('$prefix-plus'),
          tooltip: subtitle
              ? AppStrings.of(context).player_increaseSubtitleDelay
              : AppStrings.of(context).player_increaseAudioDelay,
          onPressed: _busy || value >= limit
              ? null
              : () => change(value + step),
          icon: const Icon(PhosphorIconsRegular.plus),
        ),
        _choice(
          '$prefix-reset',
          AppStrings.of(context).player_reset,
          false,
          () => change(0),
        ),
      ],
    );
  }

  List<Widget> _subtitleOptions() {
    final values = widget.options.value;
    return [
      _delay(subtitle: true),
      _choices(AppStrings.of(context).player_size, [
        for (final entry in subtitleSizes.entries)
          _choice(
            'subtitle-size-${entry.key}',
            choiceLabel(
              defaultSubtitleSizeSetting,
              entry.key,
              AppStrings.of(context),
            ),
            values.subtitleScale == entry.value,
            () => _apply(
              () => widget.controller.setSubtitleScale(entry.value),
              (current) => current.copyWith(subtitleScale: entry.value),
            ),
          ),
      ]),
      _choices(AppStrings.of(context).player_position, [
        for (final entry in const {'Bottom': 100, 'Raised': 85}.entries)
          _choice(
            'subtitle-position-${entry.key}',
            entry.key == 'Bottom'
                ? AppStrings.of(context).player_bottom
                : AppStrings.of(context).player_raised,
            values.subtitlePosition == entry.value,
            () => _apply(
              () => widget.controller.setSubtitlePosition(entry.value),
              (current) => current.copyWith(subtitlePosition: entry.value),
            ),
          ),
      ]),
      _choice(
        'download-subtitles',
        AppStrings.of(context).player_downloadSubtitles,
        false,
        () => setState(() => _sourcesOpen = true),
      ),
      TvTextEntry(
        builder: (_, tvReadOnly) => TextField(
          readOnly: tvReadOnly,
          key: const ValueKey('external-subtitle-uri'),
          controller: _subtitleUri,
          decoration: InputDecoration(
            labelText: AppStrings.of(context).player_subtitleUri,
            hintText: AppStrings.of(context).player_subtitleUriHint,
          ),
          onSubmitted: (_) => _addSubtitle(),
        ),
      ),
      FocusButton(
        variant: FocusButtonVariant.row,
        label: AppStrings.of(context).player_addExternalSubtitle,
        enabled: !_busy,
        onActivate: _addSubtitle,
      ),
    ];
  }

  Widget _videoOptions() {
    final values = widget.options.value;
    return ListView(
      children: [
        _choices(AppStrings.of(context).player_aspectRatio, [
          for (final ratio in ['Auto', '16:9', '4:3', '21:9', '2.39:1'])
            _choice(
              'aspect-$ratio',
              ratio == 'Auto' ? AppStrings.of(context).common_auto : ratio,
              values.aspect == ratio,
              () => _apply(
                () => widget.controller.setAspectRatio(
                  ratio == 'Auto' ? null : ratio,
                ),
                (current) => current.copyWith(aspect: ratio),
              ),
            ),
        ]),
        Row(
          children: [
            Expanded(child: AppText(AppStrings.of(context).player_fillScreen)),
            Semantics(
              label: AppStrings.of(context).player_fillScreen,
              child: Switch(
                key: const ValueKey('fill-screen'),
                value: values.fill,
                onChanged: _busy
                    ? null
                    : (fill) => _apply(
                        () => widget.controller.setFillScreen(fill),
                        (current) => current.copyWith(fill: fill),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ValueListenableBuilder<PlayerOptionValues>(
      valueListenable: widget.options,
      builder: (context, values, child) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final section in [
                  'Subtitles',
                  'Audio',
                  'Video',
                  'Playback',
                  'Info',
                ])
                  IntrinsicWidth(
                    child: Semantics(
                      selected: _section == section,
                      child: PanelRow(
                        key: ValueKey('options-section-$section'),
                        tokens: tokens,
                        compact: true,
                        selected: _section == section,
                        autofocus: section == 'Subtitles',
                        onTap: () => setState(() {
                          _section = section;
                          _sourcesOpen = false;
                          _failure = null;
                        }),
                        child: AppText(
                          switch (section) {
                            'Subtitles' => AppStrings.of(
                              context,
                            ).player_subtitles,
                            'Audio' => AppStrings.of(context).player_audio,
                            'Video' => AppStrings.of(context).player_video,
                            'Playback' => AppStrings.of(
                              context,
                            ).settings_playback_title,
                            _ => AppStrings.of(context).player_info,
                          },
                          maxLines: 1,
                          softWrap: false,
                          style: tokens.typeStyles.panelRow.copyWith(
                            fontSize: 16,
                            color: PanelRow.foregroundColor(
                              tokens,
                              selected: _section == section,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: RivuletSpacing.s12),
          Expanded(
            child: switch (_section) {
              'Subtitles' when _sourcesOpen && widget.onSearchSubtitles != null =>
                OnlineSubtitlesPanel(
                  search: widget.onSearchSubtitles!,
                  onPick: (result) async {
                    final strings = AppStrings.of(context);
                    final files = await widget.onFetchSubtitle!(result);
                    await addAndSelectSubtitles(
                      widget.controller,
                      files,
                      strings,
                    );
                    if (mounted) setState(() => _sourcesOpen = false);
                  },
                  onBack: () => setState(() => _sourcesOpen = false),
                ),
              'Subtitles' when _sourcesOpen => SubtitleSourcesPanel(
                sources: widget.subtitleSources,
                onBack: () => setState(() => _sourcesOpen = false),
              ),
              'Subtitles' || 'Audio' => ListView(
                key: ValueKey('options-list-$_section'),
                children: [
                  TrackPanel(
                    key: ValueKey(_section),
                    controller: widget.controller,
                    state: widget.state,
                    dismiss: widget.dismiss,
                    showHeadings: false,
                    compact: true,
                    embedded: true,
                    onAddSubtitleFiles: widget.onAddSubtitleFiles,
                    type: _section == 'Subtitles'
                        ? TrackType.subtitle
                        : TrackType.audio,
                  ),
                  if (_section == 'Subtitles')
                    ..._subtitleOptions()
                  else
                    _delay(subtitle: false),
                ],
              ),
              'Video' => _videoOptions(),
              'Playback' => ListView(
                children: [
                  AppText(
                    AppStrings.of(context).player_speed,
                    style: tokens.typeStyles.label,
                  ),
                  for (final rate in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0])
                    _choice(
                      'speed-$rate',
                      AppStrings.of(context).player_playbackRate(
                        AppStrings.of(context).localeName == 'fa'
                            ? NumberFormat('0.0#', 'fa').format(rate)
                            : rate.toString(),
                      ),
                      widget.state.rate == rate,
                      () => _run(() => widget.controller.setRate(rate)),
                    ),
                ],
              ),
              _ => InfoPanel(
                description: null,
                info: widget.mediaInfo,
                tracks: widget.state.tracks,
                audioOutput: widget.audioOutput,
              ),
            },
          ),
          if (_failure case final failure?)
            Semantics(
              liveRegion: true,
              child: AppText(
                failure,
                style: TextStyle(color: tokens.colors.danger),
              ),
            ),
        ],
      ),
    );
  }
}
