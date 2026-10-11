import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;

import '../focus/focus_memory.dart';
import '../focus/focusable_card.dart';
import '../focus/row_focus_policy.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'continue_card.dart';
import 'media_context_menu.dart';
import 'media_row.dart' show RowMetrics, rowHeaderHeight;
import 'poster_card.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Fixed-pitch shelf row of title cards (DESIGN_SPEC §8.1, §9.5). Owns its
/// own horizontal [ScrollController] and an id-keyed [FocusNode] map so
/// append/removal never recreates a surviving item's focus or scroll
/// position. Card size, gap and gutter come from [RowMetrics].
class MediaShelf extends StatefulWidget {
  const MediaShelf({
    required this.title,
    required this.items,
    required this.memory,
    required this.onFocused,
    this.isContinueRow = false,
    this.surfaceId,
    this.progress = const <String, PlaybackProgress>{},
    this.watched = const <String>{},
    this.unwatchedCounts = const <String, int>{},
    this.onItemTap,
    this.onLoadMore,
    this.onRemove,
    this.autofocus = true,
    this.firstFocusNode,
    this.keyPrefix,
    super.key,
  });

  /// Names each card's contract key `<keyPrefix>-item-<i>`; none without it.
  final String? keyPrefix;

  final String title;
  final List<MediaItem> items;
  final FocusMemory memory;
  final ValueChanged<MediaItem> onFocused;

  /// Whether this row grabs keyboard focus on mount. A page with several
  /// shelves stacked (e.g. search's grouped results — Rivulet's `searchGrid`
  /// sections use this same row layout, `PlexHomeViewController.swift:2112`)
  /// sets this `false` on every row but the first.
  final bool autofocus;

  /// External [FocusNode] for the row's first tile, so a caller elsewhere on
  /// the page (a search field's arrow-down handoff) can target it directly
  /// — same contract as `MediaGrid.firstFocusNode`.
  final FocusNode? firstFocusNode;

  /// Continue Watching uses [ContinueCard] (16:9) and its pitch; every other
  /// shelf uses [PosterCard] (2:3) and the poster pitch.
  final bool isContinueRow;

  /// Focus-memory surface key. Defaults to [title] (matches `MediaRow`'s
  /// existing convention).
  final String? surfaceId;
  final Map<String, PlaybackProgress> progress;
  final Set<String> watched;
  final Map<String, int> unwatchedCounts;

  /// Select / tap / physical Play-Pause on the focused tile.
  final ValueChanged<MediaItem>? onItemTap;

  /// Fired at most once per distinct item count, the first time focus or
  /// scroll lands within the final five loaded items (phase step 6).
  final VoidCallback? onLoadMore;

  /// Continue Watching removal. Optimistic: the tile disappears
  /// immediately; a `false`/thrown result restores it at its original
  /// index and refocuses it (phase step 5).
  final Future<bool> Function(MediaItem item)? onRemove;

  @override
  State<MediaShelf> createState() => _MediaShelfState();
}

class _MediaShelfState extends State<MediaShelf> {
  late List<MediaItem> _items = List<MediaItem>.of(widget.items);
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  late final RowFocusPolicy _policy = RowFocusPolicy(
    _items.map((i) => i.id).toList(),
  );
  final ScrollController _scroll = ScrollController();
  int? _paginatedAtCount;

  String get _surfaceId => widget.surfaceId ?? widget.title;

  @override
  void didUpdateWidget(MediaShelf old) {
    super.didUpdateWidget(old);
    if (widget.items == old.items) return;
    setState(() {
      _items = List<MediaItem>.of(widget.items);
      _policy.updateItems(_items.map((i) => i.id).toList());
      _focusNodes.removeWhere((id, node) {
        final stillPresent = _items.any((item) => item.id == id);
        if (!stillPresent) node.dispose();
        return !stillPresent;
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  FocusNode _focusNodeFor(String id) {
    if (widget.firstFocusNode != null &&
        _items.isNotEmpty &&
        id == _items.first.id) {
      return widget.firstFocusNode!;
    }
    return _focusNodes.putIfAbsent(id, () => FocusNode(debugLabel: id));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final metrics = RowMetrics.of(context, continueRow: widget.isContinueRow);
    // An empty title means the caller renders its own heading above the
    // shelf (search's grouped results, which need the heading excluded
    // from focus traversal in a way this row's own title never is) —
    // the shelf then contributes no header band of its own.
    final showHeader = widget.title.isNotEmpty;
    final header = showHeader ? rowHeaderHeight(context) : 0.0;
    return Focus(
      // Only a shelf that grabs focus on mount is a focus stop itself.
      canRequestFocus: widget.autofocus,
      autofocus: widget.autofocus,
      onKeyEvent: _onKeyEvent,
      onFocusChange: (focused) {
        if (focused && tv) FocusableCard.revealSection(context);
      },
      child: SizedBox(
        height: (showHeader ? header + RivuletSpacing.s12 : 0) + metrics.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showHeader) ...<Widget>[
              SizedBox(
                height: header,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: metrics.gutter),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AppText(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tokens.typeStyles.headline,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: RivuletSpacing.s12),
            ],
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Positioned(
                    top: -FocusableCard.glowInset,
                    bottom: -FocusableCard.glowInset,
                    left: 0,
                    right: 0,
                    child: ListView.builder(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      itemCount: _items.length,
                      itemExtent: metrics.pitch,
                      padding: EdgeInsets.symmetric(
                        horizontal: metrics.gutter,
                        vertical: FocusableCard.glowInset,
                      ),
                      // Keyed reconciliation: an item removed from the middle
                      // moves its surviving neighbors' Elements (and their
                      // FocusableCard state) by key instead of by position,
                      // so an unrelated removal never disposes/recreates a
                      // surviving tile's focus.
                      findChildIndexCallback: (key) {
                        final id = (key as _TileKey).id;
                        final index = _items.indexWhere(
                          (item) => item.id == id,
                        );
                        return index == -1 ? null : index;
                      },
                      itemBuilder: (context, index) =>
                          _tile(context, _items[index], index, metrics),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    MediaItem item,
    int index,
    RowMetrics metrics,
  ) {
    return Padding(
      // Distinct key type from `FocusableCard`'s own internal
      // `ValueKey<String>(itemId)` (on its GestureDetector), so `find.byKey`
      // in tests can address one or the other unambiguously.
      key: _TileKey(item.id),
      padding: EdgeInsets.only(right: metrics.gap),
      child: Align(
        alignment: Alignment.topLeft,
        child: GestureDetector(
          onLongPress: () => _openContextMenu(context, item, null),
          child: FocusableCard(
            surfaceId: _surfaceId,
            itemId: item.id,
            memory: widget.memory,
            focusNode: _focusNodeFor(item.id),
            revealAncestors:
                !(AdaptiveBehavior.of(context).formFactor == FormFactor.tv),
            focusKey: widget.keyPrefix == null
                ? null
                : ValueKey<String>('${widget.keyPrefix}-item-$index'),
            onSecondaryTap: (point) => _openContextMenu(context, item, point),
            semanticLabel: item.title,
            width: metrics.width,
            height: metrics.height,
            onFixedFocus:
                (AdaptiveBehavior.of(context).formFactor == FormFactor.tv)
                ? () => _fixFocus(item.id, metrics.pitch)
                : null,
            onFocused: () => _handleFocus(item),
            onTap: () => widget.onItemTap?.call(item),
            child: widget.isContinueRow
                ? ContinueCard(item: item, progress: widget.progress[item.id])
                : PosterCard(
                    item: item,
                    progress: widget.progress[item.id],
                    watched: widget.watched.contains(item.id),
                    unwatchedCount: widget.unwatchedCounts[item.id],
                  ),
          ),
        ),
      ),
    );
  }

  /// TV fixed-focus (DESIGN_SPEC §6.4 rule 8): the focused tile goes to the
  /// row's first slot, `fast`/easeOut; the end of the row clamps.
  void _fixFocus(String id, double pitch) {
    if (!_scroll.hasClients) return;
    final policy = RowFocusPolicy(_items.map((i) => i.id).toList())..select(id);
    scrollPositionTo(
      _scroll.position,
      policy
          .targetScrollOffset(pitch)
          .clamp(0.0, _scroll.position.maxScrollExtent),
      duration: effectiveDuration(context, RivuletMotion.fast),
      curve: RivuletMotion.easeOut,
    );
  }

  void _handleFocus(MediaItem item) {
    // A tile mid-removal can still report a stray focus-change notification
    // as its FocusNode detaches from the tree (`_removeOptimistically`
    // already dropped it from `_items`/`_policy`); ignore it rather than
    // asserting on a stale id.
    if (!_items.any((i) => i.id == item.id)) return;
    _policy.select(item.id);
    widget.onFocused(item);
    final index = _items.indexWhere((i) => i.id == item.id);
    if (widget.onLoadMore != null &&
        _items.isNotEmpty &&
        index >= _items.length - 5 &&
        _paginatedAtCount != _items.length) {
      _paginatedAtCount = _items.length;
      widget.onLoadMore!();
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.mediaPlayPause) {
      final id = _policy.selectedId;
      final item = id == null
          ? null
          : _items.firstWhere((i) => i.id == id, orElse: () => _items.first);
      if (item == null) return KeyEventResult.ignored;
      widget.onItemTap?.call(item);
      return KeyEventResult.handled;
    }
    // TV directional movement steps exactly one item pitch at a time
    // (phase step 1) via `RowFocusPolicy.moveFocus` rather than any
    // geometric scroll math.
    final forward = event.logicalKey == LogicalKeyboardKey.arrowRight;
    final backward = event.logicalKey == LogicalKeyboardKey.arrowLeft;
    if (!forward && !backward) return KeyEventResult.ignored;
    if (!_policy.moveFocus(forward)) return KeyEventResult.ignored;
    final nextId = _policy.selectedId;
    if (nextId == null) return KeyEventResult.ignored;
    _focusNodeFor(nextId).requestFocus();
    return KeyEventResult.handled;
  }

  Future<void> _openContextMenu(
    BuildContext context,
    MediaItem item,
    Offset? anchor,
  ) {
    final focusNode = _focusNodeFor(item.id);
    final actions = <MediaContextAction>[
      if (widget.isContinueRow && widget.onRemove != null)
        MediaContextAction(
          label: AppStrings.of(context).shelf_removeContinue,
          icon: PhosphorIconsRegular.x,
          onSelected: () => _removeOptimistically(item),
        ),
    ];
    if (actions.isEmpty) return Future<void>.value();
    return showMediaContextMenu(
      context: context,
      actions: actions,
      returnFocusTo: focusNode,
      anchor: anchor,
    );
  }

  Future<void> _removeOptimistically(MediaItem item) async {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index == -1) return;
    setState(() {
      _items.removeAt(index);
      _policy.updateItems(_items.map((i) => i.id).toList());
    });
    try {
      final succeeded = await widget.onRemove!(item);
      if (!succeeded && mounted) _restore(item, index);
    } catch (_) {
      if (mounted) _restore(item, index);
      rethrow;
    }
  }

  void _restore(MediaItem item, int index) {
    setState(() => _items.insert(index.clamp(0, _items.length), item));
    _policy.updateItems(_items.map((i) => i.id).toList());
    _focusNodeFor(item.id).requestFocus();
  }
}

class _TileKey extends LocalKey {
  const _TileKey(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is _TileKey && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
