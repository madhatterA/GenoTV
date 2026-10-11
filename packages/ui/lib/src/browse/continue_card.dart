import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../components/artwork.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'poster_card.dart';

/// Continue-watching card (DESIGN_SPEC §9.5): 16:9 art with `medium` corners
/// and a 3 px `accent` progress bar at its bottom, the title under it. No
/// blur and no plate. On TV the title shows under the focused card only.
class ContinueCard extends StatelessWidget {
  const ContinueCard({required this.item, this.progress, super.key});

  final MediaItem item;
  final PlaybackProgress? progress;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final fraction = PosterCard.fractionOf(progress);
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
                    if (fraction != null) ProgressBar(fraction: fraction),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: PosterCard.captionBlockHeight(context),
            child: showCaption
                ? Padding(
                    padding: const EdgeInsets.only(top: RivuletSpacing.s8),
                    child: ExcludeSemantics(
                      child: AppText.content(
                        item.title,
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
