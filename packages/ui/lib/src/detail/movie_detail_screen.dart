import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../components/ambient_background.dart';
import '../focus/focus_memory.dart';
import '../navigation/page_entry_focus.dart';
import '../navigation/page_back_button.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'detail_hero.dart';
import 'detail_sections.dart';
import 'movie_detail_presentation.dart';

/// Movie detail (DESIGN_SPEC §8.5): the [DetailHero], then the People,
/// "More like this" and other sections, in one scroll.
///
/// Scroll position is kept across rebuilds via [PageStorageKey] (Flutter's
/// standard mechanism: "PageStorageKey persists the widget state in storage
/// after the widget is destroyed and restores state when recreated" —
/// flutter/website `ui/adaptive-responsive/best-practices.md`, Context7
/// `/flutter/website`), keyed by item id so a different item gets a fresh
/// scroll position while the same item's re-render (e.g. a playback-return
/// refresh) keeps it.
///
/// Playback-return refresh (step 5): this widget is a single [StatefulWidget]
/// whose focus nodes and [FocusMemory] live in [State] — feeding it an
/// updated [MovieDetailPresentation] (same item id, new progress/watch
/// flags) only runs `build` again; it never remounts the page or moves
/// focus, because nothing here is keyed by presentation content.
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({
    required this.presentation,
    this.onPlay,
    this.onToggleWatched,
    this.onToggleWatchlist,
    this.onInfo,
    this.onRelatedTap,
    this.onTrailerTap,
    this.onLinkTap,
    this.onCastTap,
    super.key,
  });

  final MovieDetailPresentation presentation;

  /// Null disables/dims/unfocuses the Play action (step 3).
  final VoidCallback? onPlay;
  final VoidCallback? onToggleWatched;
  final VoidCallback? onToggleWatchlist;
  final VoidCallback? onInfo;
  final ValueChanged<MediaItem>? onRelatedTap;
  final ValueChanged<MediaItem>? onTrailerTap;
  final ValueChanged<DetailLink>? onLinkTap;
  final ValueChanged<CastMember>? onCastTap;

  @override
  State<MovieDetailScreen> createState() => MovieDetailScreenState();
}

/// Public so tests can assert the *same* [State] instance survives a
/// presentation update (proof the page was not recreated).
class MovieDetailScreenState extends State<MovieDetailScreen> {
  final FocusMemory _memory = FocusMemory();
  final FocusNode _playFocusNode = FocusNode(debugLabel: 'detail-play');

  /// Recorded by [_handlePlay] right before opening the player — step 5:
  /// "records item ID and current focus".
  String? recordedItemId;
  FocusNode? recordedFocusNode;

  PageEntry? _entry;

  @override
  void initState() {
    super.initState();
    _entry = PageEntryFocus.register(context, _playFocusNode);
  }

  @override
  void dispose() {
    _entry?.release(_playFocusNode);
    _playFocusNode.dispose();
    super.dispose();
  }

  void _handlePlay() {
    recordedItemId = widget.presentation.item.id;
    recordedFocusNode = FocusManager.instance.primaryFocus;
    widget.onPlay!();
  }

  @override
  Widget build(BuildContext context) {
    final presentation = widget.presentation;
    final trailer = presentation.trailers.firstOrNull;
    final formFactor = AdaptiveBehavior.of(context).formFactor;

    return PopOnEscape(
      child: AmbientBackground(
        key: const ValueKey<String>('detail-page'),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: CustomScrollView(
                key: PageStorageKey<String>(
                  'detail-scroll-${presentation.item.id}',
                ),
                slivers: <Widget>[
                  SliverToBoxAdapter(
                    child: DetailHero(
                      presentation: presentation,
                      playFocusNode: _playFocusNode,
                      onPlay: widget.onPlay == null ? null : _handlePlay,
                      onTrailer: trailer == null || widget.onTrailerTap == null
                          ? null
                          : () => widget.onTrailerTap!(trailer),
                      onLinkTap: widget.onLinkTap,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: RivuletSpacing.rowGap(formFactor),
                        bottom: RivuletSpacing.s48,
                      ),
                      child: DetailSections(
                        presentation: presentation,
                        memory: _memory,
                        onRelatedTap: widget.onRelatedTap,
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
