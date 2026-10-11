import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../components/artwork.dart';
import '../components/media_badges.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

/// The one title card used by every row and grid (DESIGN_SPEC §9.5): the art
/// with `medium` corners, then the title and year under it. A partly watched
/// title gets a 3 px `accent` bar at the bottom of the art. On TV the text
/// shows under the focused card only. The watched glyph and unwatched count
/// are `ProgressOverlay`, shared with `ContinueCard`.
class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.item,
    this.progress,
    this.watched = false,
    this.unwatchedCount,
    super.key,
  });

  final MediaItem item;
  final PlaybackProgress? progress;
  final bool watched;
  final int? unwatchedCount;

  /// Height of the text block under the art: the gap plus one `caption` line.
  /// A card is its art height plus this.
  static double captionBlockHeight(BuildContext context) {
    final style = RivuletTokens.of(context).typeStyles.caption;
    // Two lines: titles show in full, not cut with "…" (owner 2026-10-10).
    return RivuletSpacing.s8 +
        (MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height! *
                2)
            .ceilToDouble();
  }

  /// The title card's 3 px `accent` progress bar (partly watched titles).
  static double? fractionOf(PlaybackProgress? progress) {
    if (progress == null || progress.duration <= Duration.zero) return null;
    final fraction =
        progress.position.inMilliseconds / progress.duration.inMilliseconds;
    return fraction > 0 && fraction < 1 ? fraction : null;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final fraction = fractionOf(progress);
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final showCaption = !tv || (Focus.maybeOf(context)?.hasFocus ?? false);
    final artwork = item.artwork;
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RivuletRadius.medium),
              child: LayoutBuilder(
                builder: (context, constraints) => Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    // The card's own label already names the title.
                    ExcludeSemantics(
                      child: ArtworkView(
                        requestId: artwork?.toString() ?? 'no-artwork',
                        provider: artwork == null
                            ? null
                            : ArtworkResolverScope.of(context)(
                                artwork.toString(),
                              ),
                        aspect: constraints.maxWidth / constraints.maxHeight,
                        fallbackKind: item.kind,
                      ),
                    ),
                    ProgressOverlay(
                      watched: watched,
                      unwatchedCount: unwatchedCount,
                    ),
                    if (fraction != null) ProgressBar(fraction: fraction),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: captionBlockHeight(context),
            child: showCaption
                ? Padding(
                    padding: const EdgeInsets.only(top: RivuletSpacing.s8),
                    // The card's own Semantics label (FocusableCard) already
                    // names it.
                    child: ExcludeSemantics(
                      child: AppText.content(
                        item.title,
                        key: const ValueKey<String>('title-card-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.typeStyles.caption.copyWith(
                          color: tokens.colors.textPrimary,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// The 3 px `accent` bar along the bottom of a card's art (DESIGN_SPEC §9.5).
class ProgressBar extends StatelessWidget {
  const ProgressBar({required this.fraction, super.key});

  final double fraction;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.bottomLeft,
    child: FractionallySizedBox(
      widthFactor: fraction,
      child: SizedBox(
        height: 3,
        child: ColoredBox(color: RivuletTokens.of(context).colors.accent),
      ),
    ),
  );
}
