import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_icon_button.dart';
import '../components/app_text_button.dart';
import '../components/tinted_surface.dart';
import '../focus/focus_memory.dart';
import '../focus/focusable_card.dart';
import '../focus/row_focus_policy.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'continue_card.dart';
import 'media_context_menu.dart';
import 'poster_card.dart';

/// Card size, gap and gutter of a title row, from DESIGN_SPEC §4.3 and §4.5.
/// A card is the art plus the text block under it ([PosterCard]).
class RowMetrics {
  const RowMetrics._({
    required this.width,
    required this.artHeight,
    required this.height,
    required this.gap,
    required this.gutter,
  });

  factory RowMetrics.of(BuildContext context, {required bool continueRow}) {
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final artHeight = continueRow
        ? sizes.continueCardHeight
        : sizes.posterHeight;
    return RowMetrics._(
      width: continueRow ? sizes.continueCardWidth : sizes.posterWidth,
      artHeight: artHeight,
      height: artHeight + PosterCard.captionBlockHeight(context),
      gap: RivuletSpacing.itemGap(formFactor),
      gutter: RivuletSpacing.gutter(formFactor),
    );
  }

  final double width;
  final double artHeight;

  /// Art plus text block.
  final double height;
  final double gap;
  final double gutter;

  /// Distance between two cards' left edges.
  double get pitch => width + gap;
}

/// Height of a row's header line: the `headline` line, at least a hit target
/// on a phone where "See all" sits in it.
double rowHeaderHeight(BuildContext context) {
  final style = RivuletTokens.of(context).typeStyles.headline;
  final line =
      (MediaQuery.textScalerOf(context).scale(style.fontSize!) * style.height!)
          .ceilToDouble();
  final sizes = AdaptiveBehavior.sizesOf(context);
  return sizes.formFactor == FormFactor.phone
      ? math.max(line, sizes.minHitTarget!)
      : line;
}

class MediaRow extends StatefulWidget {
  const MediaRow({
    required this.title,
    required this.items,
    required this.memory,
    required this.onFocused,
    this.progress = const <String, PlaybackProgress>{},
    this.onBuild,
    this.onItemTap,
    this.onSeeAll,
    this.rowIndex = 0,
    super.key,
  });

  final String title;
  final List<MediaItem> items;
  final FocusMemory memory;
  final ValueChanged<MediaItem> onFocused;
  final Map<String, PlaybackProgress> progress;
  final VoidCallback? onBuild;
  final ValueChanged<MediaItem>? onItemTap;
  final VoidCallback? onSeeAll;

  /// Position of the row on its page; names the contract keys
  /// `row-<rowIndex>-item-<i>`, `row-<rowIndex>-see-all` and
  /// `row-<rowIndex>-arrow-left/right`.
  final int rowIndex;

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scroll = ScrollController();
  bool _hovered = false;

  /// A scrolled-away row keeps its cards, so Up/Down can land on the item it
  /// last had focused (DESIGN_SPEC §6.4 rule 2).
  @override
  bool get wantKeepAlive => true;

  String get title => widget.title;
  List<MediaItem> get items => widget.items;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Left/Right stay on the row and never wrap or leave it (DESIGN_SPEC §6.4
  /// rule 1); TV has its own fixed-focus handling (ch02 p04).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent ||
        AdaptiveBehavior.of(context).formFactor == FormFactor.tv) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => TraversalDirection.left,
      LogicalKeyboardKey.arrowRight => TraversalDirection.right,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    FocusManager.instance.primaryFocus?.focusInDirection(direction);
    return KeyEventResult.handled;
  }

  void _page(double direction, double viewport, double poster) {
    final target = (_scroll.offset + direction * (viewport - poster)).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    scrollPositionTo(
      _scroll.position,
      target,
      duration: effectiveDuration(context, RivuletMotion.base),
      curve: RivuletMotion.easeOut,
    );
  }

  Widget _arrow({
    required Key key,
    required bool left,
    required double viewport,
    required double poster,
    required double top,
  }) => Positioned(
    top: top,
    left: left ? RivuletSpacing.s8 : null,
    right: left ? null : RivuletSpacing.s8,
    child: AppIconButton(
      key: key,
      overMedia: true,
      icon: left
          ? PhosphorIconsRegular.caretLeft
          : PhosphorIconsRegular.caretRight,
      semanticLabel: left
          ? AppStrings.of(context).row_scrollLeft
          : AppStrings.of(context).row_scrollRight,
      onActivate: () => _page(left ? -1 : 1, viewport, poster),
    ),
  );

  List<Widget> _arrows(double viewport, double poster, double height) {
    final top = (height - AdaptiveBehavior.sizesOf(context).iconButton) / 2;
    return <Widget>[
      Positioned.fill(
        child: ListenableBuilder(
          listenable: _scroll,
          builder: (context, _) => Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              if (_scroll.hasClients && _scroll.offset > 0)
                _arrow(
                  key: ValueKey<String>('row-${widget.rowIndex}-arrow-left'),
                  left: true,
                  viewport: viewport,
                  poster: poster,
                  top: top,
                ),
              if (_scroll.hasClients &&
                  _scroll.offset < _scroll.position.maxScrollExtent)
                _arrow(
                  key: ValueKey<String>('row-${widget.rowIndex}-arrow-right'),
                  left: false,
                  viewport: viewport,
                  poster: poster,
                  top: top,
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// TV fixed-focus (DESIGN_SPEC §6.4 rule 8): the focused card goes to the
  /// row's first slot, `fast`/easeOut; the end of the row clamps.
  VoidCallback? _fixedFocus(String id, double pitch) {
    if (!(AdaptiveBehavior.of(context).formFactor == FormFactor.tv)) {
      return null;
    }
    return () {
      if (!_scroll.hasClients) return;
      final policy = RowFocusPolicy(<String>[
        for (final item in items) item.id,
        'see-all',
      ])..select(id);
      scrollPositionTo(
        _scroll.position,
        policy
            .targetScrollOffset(pitch)
            .clamp(0.0, _scroll.position.maxScrollExtent),
        duration: effectiveDuration(context, RivuletMotion.fast),
        curve: RivuletMotion.easeOut,
      );
    };
  }

  Widget _card(
    MediaItem item,
    int index,
    RowMetrics metrics, {
    required bool continueRow,
  }) {
    return FocusableCard(
      surfaceId: title,
      itemId: item.id,
      memory: widget.memory,
      focusKey: ValueKey<String>('row-${widget.rowIndex}-item-$index'),
      semanticLabel: item.title,
      width: metrics.width,
      height: metrics.height,
      revealAncestors:
          !(AdaptiveBehavior.of(context).formFactor == FormFactor.tv),
      onFixedFocus: _fixedFocus(item.id, metrics.pitch),
      onFocused: () => widget.onFocused(item),
      onTap: () => widget.onItemTap?.call(item),
      onSecondaryTap: widget.onItemTap == null
          ? null
          : (point) => showMediaDetailsMenu(
              context: context,
              anchor: point,
              onDetails: () => widget.onItemTap!(item),
            ),
      child: continueRow
          ? ContinueCard(item: item, progress: widget.progress[item.id])
          : PosterCard(item: item, progress: widget.progress[item.id]),
    );
  }

  /// The last card of a row on desktop and TV (DESIGN_SPEC §8.1).
  Widget _seeAllCard(RowMetrics metrics) {
    final tokens = RivuletTokens.of(context);
    return FocusableCard(
      surfaceId: title,
      itemId: 'see-all',
      memory: widget.memory,
      focusKey: ValueKey<String>('row-${widget.rowIndex}-see-all'),
      semanticLabel: AppStrings.of(context).common_seeAll,
      width: metrics.width,
      height: metrics.artHeight,
      revealAncestors:
          !(AdaptiveBehavior.of(context).formFactor == FormFactor.tv),
      onFixedFocus: _fixedFocus('see-all', metrics.pitch),
      onTap: widget.onSeeAll,
      child: TintedSurface(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                PhosphorIconsRegular.caretRight,
                size: 26,
                color: tokens.colors.textPrimary,
              ),
              const SizedBox(height: RivuletSpacing.s8),
              AppText(
                AppStrings.of(context).common_seeAll,
                style: tokens.typeStyles.label,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final onBuild = widget.onBuild;
    final onSeeAll = widget.onSeeAll;
    onBuild?.call();
    final tokens = RivuletTokens.of(context);
    final continueRow = title == 'Continue watching';
    final formFactor = AdaptiveBehavior.of(context).formFactor;
    final metrics = RowMetrics.of(context, continueRow: continueRow);
    final header = rowHeaderHeight(context);
    final phone = formFactor == FormFactor.phone;
    final endCard = onSeeAll != null && !phone;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: _onKey,
      onFocusChange: (focused) {
        if (!focused ||
            !(AdaptiveBehavior.of(context).formFactor == FormFactor.tv)) {
          return;
        }
        FocusableCard.revealSection(context);
      },
      child: SizedBox(
        height: header + RivuletSpacing.s12 + metrics.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: header,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: metrics.gutter),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: AppText(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.typeStyles.headline,
                      ),
                    ),
                    if (onSeeAll != null && phone)
                      AppTextButton(
                        key: ValueKey('see-all-$title'),
                        label: AppStrings.of(context).common_seeAll,
                        onActivate: onSeeAll,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: RivuletSpacing.s12),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: LayoutBuilder(
                  builder: (context, constraints) => Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      // Taller than the row slot by the focus room on both
                      // sides, so a focused card's growth and ring are never
                      // clipped by the list viewport.
                      Positioned(
                        top: -FocusableCard.glowInset,
                        bottom: -FocusableCard.glowInset,
                        left: 0,
                        right: 0,
                        child: ListView.builder(
                          controller: _scroll,
                          scrollDirection: Axis.horizontal,
                          itemCount: items.length + (endCard ? 1 : 0),
                          itemExtent: metrics.pitch,
                          scrollCacheExtent: ScrollCacheExtent.pixels(
                            metrics.pitch,
                          ),
                          addAutomaticKeepAlives: true,
                          padding: EdgeInsets.symmetric(
                            horizontal: metrics.gutter,
                            vertical: FocusableCard.glowInset,
                          ),
                          itemBuilder: (context, index) => Padding(
                            padding: EdgeInsets.only(right: metrics.gap),
                            // Top-aligned so the card keeps its own height
                            // instead of stretching to the taller viewport.
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: index == items.length
                                  ? _seeAllCard(metrics)
                                  : _card(
                                      items[index],
                                      index,
                                      metrics,
                                      continueRow: continueRow,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      if (_hovered &&
                          AdaptiveBehavior.of(context).inputMode ==
                              InputMode.pointer)
                        ..._arrows(
                          constraints.maxWidth,
                          metrics.width,
                          metrics.artHeight,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
