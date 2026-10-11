import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../states/loading_view.dart';
import '../states/state_views.dart';

import '../detail/movie_detail_presentation.dart' show CastMember;
import '../theme/rivulet_tokens.dart';

/// Info tab: description, technical stats (monospaced values), and a
/// read-only summary of the current track list.
///
/// Source: `evidence/part-04-rivulet/infuse-ref/tvos/IMG_8307.jpg` — Info
/// tab glass card with poster, title, synopsis, tech line.
class InfoPanel extends StatelessWidget {
  const InfoPanel({
    required this.description,
    required this.info,
    required this.tracks,
    this.audioOutput,
    super.key,
  });

  final String? description;
  final MediaInfo info;
  final TrackList tracks;

  /// Plain-text audio path for the playing track; null/empty hides the row.
  final ValueListenable<String?>? audioOutput;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ListView(
      key: const ValueKey<String>('info-panel-list'),
      children: <Widget>[
        if (description case final description? when description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppText(
              description,
              key: const ValueKey<String>('info-description'),
              style: tokens.typeStyles.body,
            ),
          ),
        for (final group in mediaInfoGroups(
          AppStrings.of(context),
          info,
        )) ...<Widget>[
          AppText(group.title, style: tokens.typeStyles.label),
          const SizedBox(height: 6),
          for (final row in group.rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 96,
                    child: AppText(row.$1, style: tokens.typeStyles.caption),
                  ),
                  Expanded(
                    child: AppText(row.$2, style: tokens.typeStyles.body),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
        ],
        ValueListenableBuilder<String?>(
          valueListenable: audioOutput ?? _none,
          builder: (context, line, _) => line == null || line.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppText(
                    AppStrings.of(context).player_audioOutput(line),
                    key: const ValueKey<String>('info-audio-output'),
                    style: tokens.typeStyles.body,
                  ),
                ),
        ),
        AppText(
          AppStrings.of(context).player_tracks,
          style: tokens.typeStyles.label,
        ),
        const SizedBox(height: 6),
        _TrackSummaryRow(
          label: AppStrings.of(context).player_video,
          tracks: tracks.video,
        ),
        _TrackSummaryRow(
          label: AppStrings.of(context).player_audio,
          tracks: tracks.audio,
        ),
        _TrackSummaryRow(
          label: AppStrings.of(context).player_subtitles,
          tracks: tracks.subtitle,
        ),
      ],
    );
  }
}

final ValueNotifier<String?> _none = ValueNotifier<String?>(null);

/// A titled group of label/value rows; empty groups are not built.
typedef InfoGroup = ({String title, List<(String, String)> rows});

/// File and Streams groups for [info]. Unknown values are omitted.
List<InfoGroup> mediaInfoGroups(AppStrings strings, MediaInfo info) {
  String join(Iterable<String?> parts) => parts.whereType<String>().join(' · ');
  String number(double value, int digits) =>
      value.toStringAsFixed(digits).replaceFirst(RegExp(r'\.?0+$'), '');
  String? size(int? bytes) => bytes == null || bytes <= 0
      ? null
      : bytes >= 1 << 30
      ? '${number(bytes / (1 << 30), 2)} GB'
      : '${number(bytes / (1 << 20), 1)} MB';
  String? length(Duration? d) {
    if (d == null || d <= Duration.zero) return null;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$sec' : '${d.inMinutes}:$sec';
  }

  final transfer = info.colorTransfer;
  final hdr = transfer == null
      ? null
      : switch (transfer) {
          'pq' => 'HDR10',
          'hlg' => 'HLG',
          _ => 'SDR',
        };
  final layout = info.audioChannelLayout?.replaceAll(RegExp(r'\(.*\)'), '');
  final sampleRate = info.audioSampleRate;
  final video = join([
    info.videoCodec?.toUpperCase(),
    if (info.width != null && info.height != null)
      '${info.width}×${info.height}',
    if (info.frameRate case final fps?) '${number(fps, 3)} fps',
    if (info.bitDepth case final depth?) '$depth-bit',
    hdr,
  ]);
  final audio = join([
    info.audioCodec?.toUpperCase(),
    layout ?? (info.audioChannels == null ? null : '${info.audioChannels} ch'),
    if (sampleRate != null) '${number(sampleRate / 1000, 1)} kHz',
  ]);
  final file = <(String, String)>[
    if (info.container case final c? when c.isNotEmpty)
      (strings.player_infoFormat, c.toUpperCase()),
    if (size(info.fileSizeBytes) case final v?) (strings.player_infoSize, v),
    if (length(info.duration) case final v?) (strings.player_infoLength, v),
    if (info.bitrate case final b? when b > 0)
      (strings.player_infoBitrate, '${number(b / 1e6, 1)} Mb/s'),
  ];
  final streams = <(String, String)>[
    if (video.isNotEmpty) (strings.player_infoVideo, video),
    if (audio.isNotEmpty) (strings.player_infoAudio, audio),
    if (info.subtitleFormat case final f? when f.isNotEmpty)
      (strings.player_infoSubtitle, f),
  ];
  return [
    if (file.isNotEmpty) (title: strings.player_infoFile, rows: file),
    if (streams.isNotEmpty) (title: strings.player_infoStreams, rows: streams),
  ];
}

class _TrackSummaryRow extends StatelessWidget {
  const _TrackSummaryRow({required this.label, required this.tracks});

  final String label;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final summary = tracks.isEmpty
        ? AppStrings.of(context).settings_none
        : tracks
              .map(
                (track) => <String?>[
                  track.title,
                  track.language,
                  track.codec,
                ].whereType<String>().join(' '),
              )
              .join(
                AppStrings.of(context).localeName == 'fa' ? '\u060c ' : ', ',
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 96,
            child: AppText(label, style: tokens.typeStyles.caption),
          ),
          Expanded(child: AppText(summary, style: tokens.typeStyles.body)),
        ],
      ),
    );
  }
}

/// Cast/trivia/filmography display data. `contracts`/`content_sources` own
/// no such model (Part 06, "intentionally empty" per `CLAUDE.md`). `CastMember`
/// is reused from `../detail/movie_detail_presentation.dart` (already this
/// Part's own value type for the same shape); `FilmographyEntry` below is
/// the same pattern for the one shape that doesn't already exist.
class FilmographyEntry {
  const FilmographyEntry({required this.title, this.year, this.artwork});

  final String title;
  final int? year;
  final Uri? artwork;
}

enum InsightsTab { cast, trivia, filmography }

/// Loads and shows cast/trivia/filmography for [mediaId]. Every async load
/// is token-guarded: a result for a request that is no longer the latest
/// (tab switched, or [mediaId] changed, while it was in flight) is dropped
/// instead of overwriting a newer one (phase pitfall: "A stale insights
/// result must not replace a newer tab/item").
class InsightsPanel extends StatefulWidget {
  const InsightsPanel({
    required this.mediaId,
    required this.loadCast,
    required this.loadTrivia,
    required this.loadFilmography,
    super.key,
  });

  final String mediaId;
  final Future<List<CastMember>> Function(String mediaId) loadCast;
  final Future<List<String>> Function(String mediaId) loadTrivia;
  final Future<List<FilmographyEntry>> Function(String mediaId) loadFilmography;

  @override
  State<InsightsPanel> createState() => _InsightsPanelState();
}

class _InsightsPanelState extends State<InsightsPanel> {
  InsightsTab _tab = InsightsTab.cast;
  int _requestGeneration = 0;

  List<CastMember>? _cast;
  List<String>? _trivia;
  List<FilmographyEntry>? _filmography;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant InsightsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId != widget.mediaId) {
      _cast = null;
      _trivia = null;
      _filmography = null;
      _load();
    }
  }

  bool _hasData(InsightsTab tab) => switch (tab) {
    InsightsTab.cast => _cast != null,
    InsightsTab.trivia => _trivia != null,
    InsightsTab.filmography => _filmography != null,
  };

  void _load() {
    if (_hasData(_tab)) return;
    final generation = ++_requestGeneration;
    final mediaId = widget.mediaId;
    final tab = _tab;
    setState(() {
      _loading = true;
      _error = null;
    });
    final future = switch (tab) {
      InsightsTab.cast => widget.loadCast(mediaId),
      InsightsTab.trivia => widget.loadTrivia(mediaId),
      InsightsTab.filmography => widget.loadFilmography(mediaId),
    };
    future.then(
      (result) {
        // Stale-result guard: only the most recent request for the current
        // (mediaId, tab) pair is allowed to land.
        if (!mounted ||
            generation != _requestGeneration ||
            mediaId != widget.mediaId ||
            tab != _tab) {
          return;
        }
        setState(() {
          _loading = false;
          switch (tab) {
            case InsightsTab.cast:
              _cast = result as List<CastMember>;
            case InsightsTab.trivia:
              _trivia = result as List<String>;
            case InsightsTab.filmography:
              _filmography = result as List<FilmographyEntry>;
          }
        });
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted ||
            generation != _requestGeneration ||
            mediaId != widget.mediaId ||
            tab != _tab) {
          return;
        }
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      },
    );
  }

  void _selectTab(InsightsTab tab) {
    if (tab == _tab) return;
    setState(() => _tab = tab);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            for (final tab in InsightsTab.values)
              _TabLabel(
                key: ValueKey<String>('insights-tab-${tab.name}'),
                label: switch (tab) {
                  InsightsTab.cast => AppStrings.of(context).player_castTab,
                  InsightsTab.trivia => AppStrings.of(context).player_triviaTab,
                  InsightsTab.filmography => AppStrings.of(
                    context,
                  ).player_filmographyTab,
                },
                selected: tab == _tab,
                onTap: () => _selectTab(tab),
                tokens: tokens,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: _buildBody(tokens)),
      ],
    );
  }

  Widget _buildBody(RivuletTokens tokens) {
    if (_loading && !_hasData(_tab)) {
      return const LoadingView(
        key: ValueKey<String>('insights-loading'),
        layout: SkeletonLayout.rows,
      );
    }
    if (_error case final error?) {
      return Center(
        child: AppText(
          key: const ValueKey<String>('insights-error'),
          error,
          style: TextStyle(color: tokens.colors.danger),
        ),
      );
    }
    return switch (_tab) {
      InsightsTab.cast => ListView(
        key: const ValueKey<String>('insights-cast-list'),
        children: <Widget>[
          for (final member in _cast ?? const <CastMember>[])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppText.content(member.name, style: tokens.typeStyles.body),
                  if (member.role case final role?)
                    AppText.content(role, style: tokens.typeStyles.caption),
                ],
              ),
            ),
        ],
      ),
      InsightsTab.trivia => ListView(
        key: const ValueKey<String>('insights-trivia-list'),
        children: <Widget>[
          for (final item in _trivia ?? const <String>[])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: AppText.content(item, style: tokens.typeStyles.body),
            ),
        ],
      ),
      InsightsTab.filmography => ListView(
        key: const ValueKey<String>('insights-filmography-list'),
        children: <Widget>[
          for (final entry in _filmography ?? const <FilmographyEntry>[])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppText.content(entry.title, style: tokens.typeStyles.body),
                  if (entry.year case final year?)
                    AppText('$year', style: tokens.typeStyles.caption),
                ],
              ),
            ),
        ],
      ),
    };
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.tokens,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final RivuletTokens tokens;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.only(right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppText(
            label[0].toUpperCase() + label.substring(1),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected
                  ? tokens.colors.textPrimary
                  : tokens.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 2,
            width: 24,
            color: selected ? tokens.colors.textPrimary : Colors.transparent,
          ),
        ],
      ),
    ),
  );
}
