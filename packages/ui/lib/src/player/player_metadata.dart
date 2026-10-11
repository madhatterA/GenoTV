import '../l10n/app_text.dart';

import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

/// Rail metadata block: eyebrow, title, and a meta row (rating chip, runtime,
/// divider, audio). Wraps/truncates in place — never displaces the action
/// buttons — by owning its own width via `Expanded`/`Flexible` at the call
/// site, and letting the title ellipsize past one line.
///
/// Source: `research/Rivulet/Rivulet/Views/Player/UIKit/PlayerRailView.swift`
/// — eyebrow 23pt medium at 66% (`:95-96`), title 38pt bold (`:98-99`),
/// meta row spacing 14 (`:118`), rating chip 17pt, height 28, min width 58,
/// border 28% (`:102-108,154-155`), runtime/audio 20pt at 55% (`:110-113`).
/// Compact (iOS) geometry from `RivuletiOS/Player/IOSPlayerChrome.swift`:
/// eyebrow 13/17, title 20/28 (`:91,97`), spacing 3/5 (`:88`).
class PlayerMetadata extends StatelessWidget {
  const PlayerMetadata({
    required this.title,
    this.eyebrow,
    this.rating,
    this.runtime,
    this.audio,
    this.compact = false,
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? rating;
  final String? runtime;
  final String? audio;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final hasMeta = rating != null || runtime != null || audio != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (eyebrow case final eyebrow? when eyebrow.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: AppText.content(
              eyebrow,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 13 : 23,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.66),
              ),
            ),
          ),
        AppText.content(
          title,
          key: const ValueKey<String>('rail-title'),
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? 20 : 38,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        if (!compact && hasMeta)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _MetaRow(
              rating: rating,
              runtime: runtime,
              audio: audio,
              colors: colors,
            ),
          ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.rating,
    required this.runtime,
    required this.audio,
    required this.colors,
  });

  final String? rating;
  final String? runtime;
  final String? audio;
  final RivuletColors colors;

  @override
  Widget build(BuildContext context) {
    final metaStyle = TextStyle(
      fontSize: 20,
      color: Colors.white.withValues(alpha: 0.55),
    );
    final showDivider = runtime != null && audio != null;
    // `Wrap`, not `Row`: at large text scales (2x accessibility text) the
    // chip+runtime+divider+audio group can exceed the metadata column's
    // width (the title above it already ellipsizes past that width, but a
    // `Row(mainAxisSize.min)` has no such escape and overflows instead of
    // shrinking) — wrapping to a second line keeps every meta item visible
    // without ever displacing the action buttons (Step 2: "Wrap/truncate
    // without displacing controls").
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        if (rating case final rating?) ...<Widget>[
          _RatingChip(rating: rating),
          const SizedBox(width: 14),
        ],
        if (runtime case final runtime?) ...<Widget>[
          AppText(runtime, style: metaStyle),
          const SizedBox(width: 14),
        ],
        if (showDivider) ...<Widget>[
          AppText(
            '·',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 20,
            ),
          ),
          const SizedBox(width: 14),
        ],
        if (audio case final audio?) AppText(audio, style: metaStyle),
      ],
    );
  }
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final String rating;

  @override
  Widget build(BuildContext context) => Container(
    key: const ValueKey<String>('rail-rating-chip'),
    height: 28,
    constraints: const BoxConstraints(minWidth: 58),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
      borderRadius: BorderRadius.circular(6),
    ),
    // `widthFactor: 1` is load-bearing: `Wrap` hands each child
    // `BoxConstraints(maxWidth: <the wrap's own bounded width>)`, not an
    // unbounded one, and a bare `Align`/`Center` (no `widthFactor`) fills
    // its incoming max width whenever that width is finite — stretching
    // this into a full-width bar instead of a small chip
    // (`Container.alignment` has the exact same problem, since it is the
    // same `Align`). `widthFactor: 1` makes it hug the text's own width
    // (still clamped up to `minWidth: 58` by the `ConstrainedBox` above);
    // height stays centered because the Container's own `height: 28` is
    // already tight regardless. Caught by reading the TV golden
    // (`test/goldens/player_rail_tv_1920.png`) directly, per the brief.
    child: Align(
      widthFactor: 1,
      child: AppText(
        rating,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w500,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    ),
  );
}
