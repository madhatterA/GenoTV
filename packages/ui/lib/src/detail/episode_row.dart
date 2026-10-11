import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../browse/poster_card.dart' show ProgressBar;
import '../components/app_icon_button.dart';
import '../components/artwork.dart';
import '../components/tinted_surface.dart';
import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'series_view_model.dart';

/// One episode (DESIGN_SPEC §8.5): a [TintedSurface] row with the 16:9
/// thumbnail (a 3 px `accent` bar along its bottom for a partly watched
/// episode), the title, the length and, on desktop and TV, a two-line
/// overview. Select plays it. On desktop a `play` icon shows at the right
/// while the pointer is over the row or it has focus; when [onShowDetails]
/// is set an info button opens the episode's details.
class EpisodeRow extends StatefulWidget {
  const EpisodeRow({
    required this.episode,
    required this.onPlay,
    this.onShowDetails,
    this.onFocused,
    super.key,
  });

  /// Thumbnail width per form factor (DESIGN_SPEC §8.5).
  static double thumbWidthOf(FormFactor formFactor) => switch (formFactor) {
    FormFactor.phone => 160,
    FormFactor.desktop => 240,
    FormFactor.tv => 220,
  };

  final SeriesEpisode episode;
  final VoidCallback onPlay;
  final VoidCallback? onShowDetails;

  /// Called when the row (or its info button) takes focus.
  final VoidCallback? onFocused;

  @override
  State<EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<EpisodeRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final formFactor = sizes.formFactor;
    final phone = formFactor == FormFactor.phone;
    final thumbWidth = EpisodeRow.thumbWidthOf(formFactor);
    final thumbHeight = thumbWidth * 9 / 16;
    final progress = episode.progress;
    final playIcon = formFactor == FormFactor.desktop && (_hovered || _focused);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        includeSemantics: false,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused) widget.onFocused?.call();
        },
        child: FocusableAction(
          onActivate: widget.onPlay,
          semanticLabel: episode.title,
          focusRadius: BorderRadius.circular(RivuletRadius.medium),
          child: TintedSurface(
            key: ValueKey<String>(
              'episode-row-${episode.season}-${episode.episode}',
            ),
            padding: const EdgeInsets.all(RivuletSpacing.s8),
            child: Row(
              children: <Widget>[
                SizedBox(
                  key: const ValueKey<String>('episode-thumb'),
                  width: thumbWidth,
                  height: thumbHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(RivuletRadius.medium),
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        if (episode.still == null)
                          ColoredBox(
                            color: tokens.colors.tintFill,
                            child: Center(
                              child: AppText(
                                formatCount(context, episode.episode),
                                style: styles.title.copyWith(
                                  color: tokens.colors.textTertiary,
                                ),
                              ),
                            ),
                          )
                        else
                          ArtworkView(
                            requestId: episode.still.toString(),
                            provider: ArtworkResolverScope.of(context)(
                              episode.still.toString(),
                            ),
                            aspect: thumbWidth / thumbHeight,
                            fallbackKind: MediaKind.episode,
                          ),
                        if (progress != null && progress > 0 && progress < 1)
                          ProgressBar(fraction: progress),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: RivuletSpacing.s12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppText(
                        AppStrings.of(context).episode_title(
                          formatCount(context, episode.episode),
                          _nameOf(episode.title),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: styles.label,
                      ),
                      AppText(
                        AppStrings.of(context).episode_minutes(
                          formatCount(context, episode.duration.inMinutes),
                        ),
                        style: styles.caption.copyWith(
                          color: tokens.colors.textSecondary,
                        ),
                      ),
                      if (!phone && episode.description.isNotEmpty)
                        AppText.content(
                          episode.description,
                          paragraph: true,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: styles.caption.copyWith(
                            color: tokens.colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (formFactor == FormFactor.desktop)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: RivuletSpacing.s12,
                    ),
                    child: Opacity(
                      opacity: playIcon ? 1 : 0,
                      child: Icon(
                        PhosphorIconsFill.play,
                        size: sizes.iconGlyph,
                        color: tokens.colors.textPrimary,
                      ),
                    ),
                  ),
                if (widget.onShowDetails != null)
                  AppIconButton(
                    key: ValueKey<String>(
                      'episode-details-${episode.season}-${episode.episode}',
                    ),
                    icon: PhosphorIconsRegular.info,
                    semanticLabel: AppStrings.of(context).episode_details,
                    onActivate: widget.onShowDetails,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The episode title arrives as "S01E01 · Name"; the row shows "E1 · Name".
  static String _nameOf(String title) {
    final at = title.indexOf(' · ');
    return at < 0 ? title : title.substring(at + 3);
  }
}
