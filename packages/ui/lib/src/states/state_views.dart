import '../l10n_gen/app_strings.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../accessibility/ui_accessibility.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_text_button.dart';
import '../components/tinted_surface.dart';

enum SkeletonLayout { posters, rows, detail, player }

/// Placeholder blocks (DESIGN_SPEC §9.10): `tintFill`, `medium` radius, one
/// opacity pulse (0.55 to 1, 900 ms, reversing) on the whole skeleton. TV and
/// reduced motion: static, no ticker.
class StateSkeleton extends StatelessWidget {
  const StateSkeleton({
    this.label,
    this.layout = SkeletonLayout.posters,
    super.key,
  });

  final String? label;
  final SkeletonLayout layout;

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    final opaque = UiAccessibility.opaqueOf(context);
    final still =
        AdaptiveBehavior.of(context).formFactor == FormFactor.tv ||
        MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      label:
          label ??
          context
              .dependOnInheritedWidgetOfExactType<UiAccessibility>()
              ?.labels
              .loading ??
          AppStrings.of(context).state_loading,
      child: ExcludeFocus(
        child: ExcludeSemantics(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : 400.0;
              Widget block(double width, double height) => Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: opaque ? colors.textTertiary : colors.tintFill,
                  borderRadius: BorderRadius.circular(RivuletRadius.medium),
                  border: opaque ? Border.all(color: colors.textPrimary) : null,
                ),
              );
              final usable = math.max(0.0, width - 2 * RivuletSpacing.s24);
              final posterWidth = math.min(220.0, usable);
              final content = switch (layout) {
                SkeletonLayout.posters => Wrap(
                  spacing: RivuletSpacing.s12,
                  runSpacing: RivuletSpacing.s12,
                  children: List.generate(
                    math.max(
                      1,
                      (usable / (posterWidth + RivuletSpacing.s12)).floor(),
                    ),
                    (_) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        block(posterWidth, posterWidth * 1.5),
                        const SizedBox(height: RivuletSpacing.s12),
                        block(math.min(160, posterWidth), 14),
                        const SizedBox(height: RivuletSpacing.s8),
                        block(math.min(100, posterWidth), 12),
                      ],
                    ),
                  ),
                ),
                SkeletonLayout.rows => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: RivuletSpacing.s12,
                        ),
                        child: block(usable, 44),
                      ),
                  ],
                ),
                SkeletonLayout.detail => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    block(usable, usable * 9 / 16),
                    const SizedBox(height: RivuletSpacing.s12),
                    block(usable * 0.6, 14),
                    const SizedBox(height: RivuletSpacing.s12),
                    block(usable, 44),
                  ],
                ),
                SkeletonLayout.player => block(usable, 44),
              };
              final scroll = SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(RivuletSpacing.s24),
                  child: content,
                ),
              );
              return still
                  ? scroll
                  : RepaintBoundary(
                      child: scroll
                          .animate(onPlay: (c) => c.repeat(reverse: true))
                          .fade(begin: 0.55, end: 1, duration: 900.ms),
                    );
            },
          ),
        ),
      ),
    );
  }
}

/// A recoverable notification beside retained content; never requests focus.
class PartialStateBanner extends StatelessWidget {
  const PartialStateBanner({
    required this.message,
    this.onRetry,
    this.onDismiss,
    super.key,
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final labels = context
        .dependOnInheritedWidgetOfExactType<UiAccessibility>()
        ?.labels;
    final tokens = RivuletTokens.of(context);
    return TintedSurface(
      radius: RivuletRadius.small,
      padding: const EdgeInsets.all(RivuletSpacing.s16),
      child: Row(
        children: [
          Icon(PhosphorIconsRegular.info, color: tokens.colors.textSecondary),
          const SizedBox(width: RivuletSpacing.s12),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: AppText(message, style: tokens.typeStyles.caption),
            ),
          ),
          if (onRetry != null)
            AppTextButton(
              label: (labels?.retry ?? strings.common_retry),
              onActivate: onRetry,
            ),
          if (onDismiss != null)
            AppTextButton(
              label: (labels?.dismiss ?? strings.common_dismiss),
              onActivate: onDismiss,
            ),
        ],
      ),
    );
  }
}
