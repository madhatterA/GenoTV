import 'dart:math' as math;

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../components/orb_loader.dart';
import '../focus/focus_memory.dart';
import '../focus/focusable_card.dart';
import '../focus/line_end_stop.dart';
import '../navigation/page_entry_focus.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'media_context_menu.dart';
import 'poster_card.dart';

class MediaGrid extends StatefulWidget {
  const MediaGrid({
    required this.items,
    required this.memory,
    required this.onFocused,
    this.focusedId,
    this.firstFocusNode,
    this.autofocus = true,
    this.onItemTap,
    this.onLoadMore,
    this.isLoadingMore = false,
    this.trailingTile,
    this.scrollController,
    this.shrinkWrap = false,
    this.pageEntry = false,
    this.header,
    super.key,
  });

  /// Scrolls with the grid, above its first line (a person page's portrait
  /// and Known for row).
  final Widget? header;

  /// Registers the first poster as the page's primary focus element
  /// (DESIGN_SPEC §6.4 rule 9).
  final bool pageEntry;

  final List<MediaItem> items;
  final FocusMemory memory;
  final ValueChanged<MediaItem> onFocused;
  final String? focusedId;
  final FocusNode? firstFocusNode;
  final bool autofocus;
  final ValueChanged<MediaItem>? onItemTap;

  /// Fired once per distinct item count when focus enters the final five
  /// items — same pagination contract as `MediaShelf.onLoadMore`
  /// (`phase-03` step 1: "cursor/loading state").
  final VoidCallback? onLoadMore;

  /// Shows the [OrbLoader] centred under the last line while a page is in
  /// flight (DESIGN_SPEC §9.9).
  final bool isLoadingMore;

  /// Replaces the loader under the last line (the retry of a failed page).
  final Widget? trailingTile;

  /// Caller-owned scroll controller, so scroll offset survives navigating
  /// away and back (`phase-03` step 2: "Keep ... scroll offset ... under
  /// the destination restoration bucket" — the caller's `State` object,
  /// which the app shell keeps alive offstage rather than disposing).
  final ScrollController? scrollController;

  /// True when embedded inside another scrollable (e.g. one section of
  /// `SearchScreen`'s grouped results list) — sizes to its content instead
  /// of expanding into an unbounded viewport, and defers scrolling to the
  /// ancestor.
  final bool shrinkWrap;

  @override
  State<MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<MediaGrid> {
  int? _paginatedAtCount;
  PageEntry? _entry;
  late final FocusNode _ownFirst = FocusNode(debugLabel: 'grid-first');
  late final FocusNode _first = widget.firstFocusNode ?? _ownFirst;

  @override
  void initState() {
    super.initState();
    if (widget.pageEntry) _entry = PageEntryFocus.register(context, _first);
  }

  @override
  void dispose() {
    _entry?.release(_first);
    _ownFirst.dispose();
    super.dispose();
  }

  void _handleFocused(MediaItem item) {
    widget.onFocused(item);
    final index = widget.items.indexWhere((i) => i.id == item.id);
    if (widget.onLoadMore != null &&
        widget.items.isNotEmpty &&
        index >= widget.items.length - 5 &&
        _paginatedAtCount != widget.items.length) {
      _paginatedAtCount = widget.items.length;
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) => _MediaGridView(
    items: widget.items,
    memory: widget.memory,
    focusedId: widget.focusedId,
    firstFocusNode: _first,
    autofocus: widget.autofocus,
    onItemTap: widget.onItemTap,
    onFocused: _handleFocused,
    isLoadingMore: widget.isLoadingMore,
    trailingTile: widget.trailingTile,
    scrollController: widget.scrollController,
    shrinkWrap: widget.shrinkWrap,
    header: widget.header,
  );
}

/// Sizing text under the loading skeleton; never readable.
const String _skeletonTitle = 'Placeholder film title';

/// Placeholder titles the first-page skeleton is drawn from.
final List<MediaItem> _placeholders = <MediaItem>[
  for (var i = 0; i < 12; i++)
    MediaItem(
      id: 'skeleton-grid-$i',
      title: _skeletonTitle,
      kind: MediaKind.movie,
      year: 2024,
    ),
];

/// The grid while its first page loads (DESIGN_SPEC §9.10): the real grid fed
/// 12 placeholder titles and drawn as bones, so the content replaces it with
/// no layout shift. Static on TV and with reduced motion.
class MediaGridSkeleton extends StatelessWidget {
  const MediaGridSkeleton({required this.memory, super.key});

  final FocusMemory memory;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final still = tv || MediaQuery.disableAnimationsOf(context);
    return ExcludeFocus(
      child: Skeletonizer(
        effect: still
            ? SolidColorEffect(color: colors.tintFill)
            : PulseEffect(
                from: colors.tintFill,
                to: colors.tintFillHover,
                duration: const Duration(milliseconds: 900),
              ),
        enableSwitchAnimation: !still,
        child: _MediaGridView(
          key: const ValueKey<String>('media-grid-skeleton'),
          items: _placeholders,
          memory: memory,
          onFocused: (_) {},
          autofocus: false,
        ),
      ),
    );
  }
}

class _MediaGridView extends StatelessWidget {
  const _MediaGridView({
    required this.items,
    required this.memory,
    required this.onFocused,
    this.focusedId,
    this.firstFocusNode,
    this.autofocus = true,
    this.onItemTap,
    this.isLoadingMore = false,
    this.trailingTile,
    this.scrollController,
    this.shrinkWrap = false,
    this.header,
    super.key,
  });

  final Widget? header;
  final List<MediaItem> items;
  final FocusMemory memory;
  final ValueChanged<MediaItem> onFocused;
  final String? focusedId;
  final FocusNode? firstFocusNode;
  final bool autofocus;
  final ValueChanged<MediaItem>? onItemTap;
  final bool isLoadingMore;
  final Widget? trailingTile;
  final ScrollController? scrollController;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    final formFactor = sizes.formFactor;
    final gutter = RivuletSpacing.gutter(formFactor);
    final gap = RivuletSpacing.itemGap(formFactor);
    final captionHeight = PosterCard.captionBlockHeight(context);
    final isTv = (AdaptiveBehavior.of(context).formFactor == FormFactor.tv);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = sizes.columnsFor(constraints.maxWidth);
        // Cards share the line's spare width, so a poster is never narrower
        // than the row poster and keeps its 2:3 art.
        final cellWidth =
            (constraints.maxWidth - 2 * gutter - (columns - 1) * gap) / columns;
        final cellHeight = cellWidth * 1.5 + captionHeight;
        final room = FocusableCard.focusRoom(cellHeight);
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: CustomScrollView(
            key: const ValueKey<String>('media-grid'),
            controller: scrollController,
            shrinkWrap: shrinkWrap,
            physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
            slivers: <Widget>[
              if (header != null)
                SliverToBoxAdapter(child: FocusTraversalGroup(child: header!)),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, room, gutter, room),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: cellHeight,
                    crossAxisSpacing: gap,
                    mainAxisSpacing: gap,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = items[index];
                      final lineEnd =
                          index % columns == columns - 1 ||
                          index == items.length - 1;
                      return FocusTraversalOrder(
                        order: NumericFocusOrder(index.toDouble()),
                        child: LineEndStop(
                          active: lineEnd,
                          child: FocusableCard(
                            key: ValueKey<String>('grid-${item.id}'),
                            focusKey: ValueKey<String>('grid-item-$index'),
                            surfaceId: 'library',
                            itemId: item.id,
                            memory: memory,
                            focusNode: index == 0 ? firstFocusNode : null,
                            // TV lands on the grid itself; elsewhere the page
                            // entry (DESIGN_SPEC §6.4 rule 9) decides.
                            autofocus:
                                autofocus &&
                                isTv &&
                                (item.id == focusedId ||
                                    (focusedId == null && index == 0)),
                            semanticLabel: item.title,
                            width: double.infinity,
                            height: cellHeight,
                            onFocused: () => onFocused(item),
                            onTap: () => onItemTap?.call(item),
                            onSecondaryTap: onItemTap == null
                                ? null
                                : (point) => showMediaDetailsMenu(
                                    context: context,
                                    anchor: point,
                                    onDetails: () => onItemTap!(item),
                                  ),
                            child: PosterCard(item: item),
                          ),
                        ),
                      );
                    },
                    childCount: items.length,
                    addAutomaticKeepAlives: true,
                  ),
                ),
              ),
              if (trailingTile != null || isLoadingMore)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: math.max(room, RivuletSpacing.s32),
                    ),
                    child: Center(
                      child:
                          trailingTile ??
                          const OrbLoader.small(
                            key: ValueKey<String>('media-grid-loading-more'),
                          ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
