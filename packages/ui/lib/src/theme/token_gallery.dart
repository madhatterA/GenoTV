import 'package:flutter/material.dart';

import '../platform/adaptive_behavior.dart';
import 'rivulet_tokens.dart';

/// Deterministic token/component sheet: no network, no clock. Renders the
/// palette, each geometry group at reference scale, each focus state, and
/// Latin plus Persian text samples. This is the widget `theme_test.dart`
/// takes goldens of at the four Part viewports.
class TokenGallery extends StatelessWidget {
  const TokenGallery({super.key});

  static const String _sample = 'فیلم ایرانی';

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final styles = tokens.typeStyles;
    final profile = AdaptiveBehavior.of(context);
    final swatches = <String, Color>{
      'bgBase': colors.bgBase,
      'surfaceRaised': colors.surfaceRaised,
      'textPrimary': colors.textPrimary,
      'textSecondary': colors.textSecondary,
      'accent': colors.accent,
      'danger': colors.danger,
      'scrim': colors.scrim,
      'tintFill': colors.tintFill,
      'tintFillOverMedia': colors.tintFillOverMedia,
    };
    return ColoredBox(
      color: colors.bgBase,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Rivulet token gallery', style: styles.title),
            Text(
              'form factor: ${profile.formFactor.name}',
              style: styles.caption,
            ),
            const SizedBox(height: 16),
            Text('Palette', style: styles.title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: swatches.entries
                  .map((entry) => _Swatch(label: entry.key, color: entry.value))
                  .toList(),
            ),
            const SizedBox(height: 24),
            Text('Typography', style: styles.title),
            Text(_sample, style: styles.display),
            Text(_sample, style: styles.title),
            Text(_sample, style: styles.body),
            Text(_sample, style: styles.label),
            Text(_sample, style: styles.caption),
            const SizedBox(height: 24),
            Text(
              'Poster shelf geometry (reference scale)',
              style: styles.title,
            ),
            const SizedBox(height: 8),
            _ShelfSample(
              tileWidth: tokens.geometry.posterWidth,
              tileHeight: tokens.geometry.posterHeight,
              gap: tokens.geometry.posterGap,
              count: tokens.geometry.shelfPosterCount,
              scale: 1,
              color: colors.surfaceRaised,
            ),
            const SizedBox(height: 16),
            Text(
              'Continue-watching shelf geometry (reference scale)',
              style: styles.title,
            ),
            const SizedBox(height: 8),
            _ShelfSample(
              tileWidth: tokens.geometry.cwWidth,
              tileHeight: tokens.geometry.cwHeight,
              gap: tokens.geometry.cwGap,
              count: tokens.geometry.shelfCwCount,
              scale: 1,
              color: colors.surfaceRaised,
            ),
            const SizedBox(height: 24),
            Text('Focus states', style: styles.title),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                _FocusSample(label: 'idle', scale: 1, colors: colors),
                _FocusSample(
                  label: 'focused ${tokens.focus.tileFocusScale}x',
                  scale: tokens.focus.tileFocusScale,
                  colors: colors,
                  focused: true,
                ),
                _FocusSample(
                  label: 'pressed ${tokens.focus.pressScale}x',
                  scale: tokens.focus.pressScale,
                  colors: colors,
                  focused: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 140,
    height: 56,
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white24),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        color: color.computeLuminance() > 0.45 ? Colors.black : Colors.white,
      ),
    ),
  );
}

class _ShelfSample extends StatelessWidget {
  const _ShelfSample({
    required this.tileWidth,
    required this.tileHeight,
    required this.gap,
    required this.count,
    required this.scale,
    required this.color,
  });

  final double tileWidth;
  final double tileHeight;
  final double gap;
  final int count;
  final double scale;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: tileHeight * scale,
    // Deterministic sheet, not a real shelf: scrolls horizontally instead of
    // reflowing so every viewport in the Test section renders the full tile
    // count without overflowing at the compact clamp.
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < count; i++) ...<Widget>[
            if (i > 0) SizedBox(width: gap * scale),
            Container(
              width: tileWidth * scale,
              height: tileHeight * scale,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _FocusSample extends StatelessWidget {
  const _FocusSample({
    required this.label,
    required this.scale,
    required this.colors,
    this.focused = false,
  });

  final String label;
  final double scale;
  final RivuletColors colors;
  final bool focused;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Transform.scale(
        scale: scale,
        child: Container(
          width: 96,
          height: 56,
          decoration: BoxDecoration(
            color: focused ? colors.surfaceRaised : colors.bgBase,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focused ? colors.accent : colors.textSecondary,
              width: focused ? 2 : 1,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.white70)),
    ],
  );
}
