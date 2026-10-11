import '../l10n_gen/app_strings.dart';
import '../l10n/formatters.dart';

import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Bottom-left in-progress info bar + top-trailing/bottom-left watch-state
/// badges, composited over an [ArtworkView]. Renders nothing when there is
/// nothing to show, so callers can always mount it unconditionally.
///
/// Priority ladder (mirrors `PosterCell.swift:499-525`'s
/// `configureWatchedBadge`, "Shows: unwatched count pill ... or
/// fully-watched glyph. Movies/episodes: the glyph shows only when watched
/// AND not in progress"):
///  1. [unwatchedCount] > 0 → top-trailing count pill.
///  2. [watched] → bottom-left rewatch glyph.
///  3. `0 < progress < 1` (after clamping) → bottom play icon + progress
///     capsule (`MediaProgressInfoBar.swift`).
///  4. Nothing.
class ProgressOverlay extends StatelessWidget {
  const ProgressOverlay({
    this.progress,
    this.watched = false,
    this.unwatchedCount,
    this.infoText,
    super.key,
  });

  /// 0.0-1.0 continue-watching fraction. Malformed input (NaN, negative,
  /// or > 1) is clamped rather than crashing; a clamped value outside
  /// `(0, 1)` renders nothing, matching `PosterCell.swift:481`'s
  /// `progress > 0, progress < 1` guard.
  final double? progress;

  final bool watched;

  /// Unwatched-episode count for a show row. `<= 0` is treated as absent.
  final int? unwatchedCount;

  /// `MediaProgressInfoBar.swift:97-107`'s trailing info text — e.g.
  /// `"S1, E2 • 35m"` — shown beside the progress capsule only while the
  /// capsule itself renders (`0 < progress < 1`). Null renders no text,
  /// matching the bar's icon+capsule-only layout when there's nothing to
  /// say beyond the fraction.
  final String? infoText;

  double? get _clampedProgress {
    final p = progress;
    if (p == null || p.isNaN) return null;
    return p.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final unwatched = unwatchedCount ?? 0;

    if (unwatched > 0) {
      return Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Semantics(
            label: AppStrings.of(context).badge_unwatchedEpisodes(
              unwatched,
              formatCount(context, unwatched),
            ),
            excludeSemantics: true,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: AppText(
                formatCount(context, unwatched),
                style: TextStyle(
                  color: colors.onAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (watched) {
      return Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 15),
          child: Semantics(
            label: AppStrings.of(context).common_watched,
            excludeSemantics: true,
            child: Icon(
              PhosphorIconsRegular.arrowCounterClockwise,
              color: colors.textPrimary,
              size: 20,
            ),
          ),
        ),
      );
    }

    final fraction = _clampedProgress;
    if (fraction == null || fraction <= 0 || fraction >= 1) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 15),
        child: Semantics(
          label: AppStrings.of(context)
              .badge_progress(formatCount(context, (fraction * 100).round())),
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // `MediaProgressInfoBar.swift:47-48`: 22pt play glyph.
              Icon(
                PhosphorIconsRegular.play,
                color: colors.textPrimary,
                size: 22,
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textPrimary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.textPrimary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              if (infoText != null) ...[
                const SizedBox(width: 10),
                // `MediaProgressInfoBar.swift:65-66`: 20pt medium info text.
                AppText(
                  infoText!,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
