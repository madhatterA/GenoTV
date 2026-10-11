import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../components/ambient_background.dart';
import '../components/app_chip.dart';
import '../focus/focus_memory.dart';
import '../navigation/page_entry_focus.dart';
import '../navigation/page_back_button.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'detail_hero.dart';
import 'detail_sections.dart';
import 'episode_row.dart';
import 'movie_detail_presentation.dart';
import 'season_selector.dart';
import 'series_view_model.dart';

/// Series detail (DESIGN_SPEC §8.5): the [DetailHero], the season chips, the
/// selected season's episode rows, then People and the other sections, in
/// one scroll. Choosing a season swaps the rows in place.
class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    required this.presentation,
    required this.viewModel,
    required this.onPlay,
    this.onShowEpisodeDetails,
    this.onToggleWatched,
    this.onToggleWatchlist,
    this.onInfo,
    this.onTrailerTap,
    this.onLinkTap,
    this.onCastTap,
    super.key,
  });

  final MovieDetailPresentation presentation;
  final SeriesViewModel viewModel;
  final ValueChanged<SeriesEpisode> onPlay;
  final ValueChanged<SeriesEpisode>? onShowEpisodeDetails;

  /// Null disables/dims/unfocuses the action, same contract as
  /// `MovieDetailScreen` (`movie_detail_screen.dart:39-42`) — series detail
  /// shares the same resting-state rule, not a series-specific dim.
  final VoidCallback? onToggleWatched;
  final VoidCallback? onToggleWatchlist;
  final VoidCallback? onInfo;
  final ValueChanged<MediaItem>? onTrailerTap;
  final ValueChanged<DetailLink>? onLinkTap;
  final ValueChanged<CastMember>? onCastTap;

  @override
  State<SeriesDetailScreen> createState() => SeriesDetailScreenState();
}

class SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final FocusMemory _detailMemory = FocusMemory();
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'detail-play');
  PageEntry? _entry;
  final FocusNode _chipsNode = FocusNode(
    debugLabel: 'season-chips',
    canRequestFocus: false,
    skipTraversal: true,
  );

  /// The playback-return refresh record: item id, so a refreshed
  /// [presentation]/[viewModel] never loses the season the user was on.
  String? recordedItemId;

  @override
  void initState() {
    super.initState();
    _entry = PageEntryFocus.register(context, _playFocusNode);
    widget.viewModel.loadNextUp();
  }

  @override
  void dispose() {
    _entry?.release(_playFocusNode);
    _playFocusNode.dispose();
    _chipsNode.dispose();
    super.dispose();
  }

  /// Down from the hero's buttons enters the season chips on the selected
  /// chip, not on whichever chip lies under the button.
  KeyEventResult _enterChips(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    final selected = _chipsNode.descendants.where(
      (d) =>
          d.canRequestFocus &&
          d.context?.findAncestorWidgetOfExactType<AppChip>()?.selected == true,
    );
    if (selected.isEmpty) return KeyEventResult.ignored;
    selected.first.requestFocus();
    return KeyEventResult.handled;
  }

  void _handlePlayTop() {
    recordedItemId = widget.presentation.item.id;
    final target =
        widget.viewModel.nextUp ??
        widget.viewModel.season?.episodes.firstOrNull;
    if (target != null) widget.onPlay(target);
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final gutter = RivuletSpacing.gutter(formFactor);
    final rowGap = RivuletSpacing.rowGap(formFactor);
    final trailer = presentation.trailers.firstOrNull;

    return PopOnEscape(
      child: AmbientBackground(
        key: const ValueKey<String>('series-detail-page'),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomScrollView(
                key: PageStorageKey<String>(
                  'series-detail-scroll-${presentation.item.id}',
                ),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: Focus(
                      canRequestFocus: false,
                      skipTraversal: true,
                      includeSemantics: false,
                      onKeyEvent: _enterChips,
                      child: DetailHero(
                        presentation: presentation,
                        playFocusNode: _playFocusNode,
                        onPlay: _handlePlayTop,
                        onTrailer:
                            trailer == null || widget.onTrailerTap == null
                            ? null
                            : () => widget.onTrailerTap!(trailer),
                        onLinkTap: widget.onLinkTap,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(child: SizedBox(height: rowGap)),
                  ListenableBuilder(
                    listenable: widget.viewModel,
                    builder: (_, _) => SliverMainAxisGroup(
                      slivers: <Widget>[
                        SliverToBoxAdapter(
                          child: SeasonSelector(
                            seasons: widget.viewModel.seasons,
                            selected: widget.viewModel.selectedSeason,
                            onSelected: widget.viewModel.selectSeason,
                            padding: EdgeInsets.symmetric(horizontal: gutter),
                            groupNode: _chipsNode,
                          ),
                        ),
                        const SliverToBoxAdapter(
                          child: SizedBox(height: RivuletSpacing.s12),
                        ),
                        _EpisodeList(
                          season: widget.viewModel.season,
                          gutter: gutter,
                          onFocused: widget.viewModel.focusEpisode,
                          onPlay: widget.onPlay,
                          onShowDetails: widget.onShowEpisodeDetails,
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: rowGap,
                        bottom: RivuletSpacing.s48,
                      ),
                      child: DetailSections(
                        presentation: presentation,
                        memory: _detailMemory,
                        onTrailerTap: widget.onTrailerTap,
                        onLinkTap: widget.onLinkTap,
                        onCastTap: widget.onCastTap,
                        onToggleWatched: widget.onToggleWatched,
                        onToggleWatchlist: widget.onToggleWatchlist,
                        onInfo: widget.onInfo,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Positioned(top: 0, left: 0, child: PageBackButton()),
          ],
        ),
      ),
    );
  }
}

/// The selected season's episodes, built as they scroll into view.
class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.season,
    required this.gutter,
    required this.onFocused,
    required this.onPlay,
    required this.onShowDetails,
  });

  final SeriesSeason? season;
  final double gutter;
  final ValueChanged<SeriesEpisode> onFocused;
  final ValueChanged<SeriesEpisode> onPlay;
  final ValueChanged<SeriesEpisode>? onShowDetails;

  @override
  Widget build(BuildContext context) {
    final episodes = season?.episodes ?? const <SeriesEpisode>[];
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      sliver: SliverList.separated(
        key: ValueKey<String>('episodes-${season?.number}'),
        itemCount: episodes.length,
        separatorBuilder: (_, _) => const SizedBox(height: RivuletSpacing.s8),
        itemBuilder: (_, index) {
          final episode = episodes[index];
          return EpisodeRow(
            key: ValueKey<String>('episode-$index'),
            episode: episode,
            onFocused: () => onFocused(episode),
            onPlay: () {
              onFocused(episode);
              onPlay(episode);
            },
            onShowDetails: onShowDetails == null
                ? null
                : () => onShowDetails!(episode),
          );
        },
      ),
    );
  }
}
