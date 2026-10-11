import 'package:flutter/material.dart';

/// Text edge treatment. Ports `CaptionStyle.Edge`
/// (research/Rivulet/RivuletCore/Playback/CaptionAppearance.swift:54-60).
enum CaptionEdgeStyle { none, dropShadow, raised, depressed, uniform }

/// Caption appearance snapshot. Ports `CaptionStyle`
/// (research/Rivulet/RivuletCore/Playback/CaptionAppearance.swift:13-83).
///
/// Every field has a safe default (`CaptionStyle.default`, same file:72-83)
/// so a caller that supplies nothing, or invalid data, still renders a
/// readable caption instead of an empty/crashed one — see [sanitized].
@immutable
class CaptionStyle {
  const CaptionStyle({
    this.foreground = Colors.white,
    this.foregroundOpacity = 1.0,
    this.background = Colors.black,
    this.backgroundOpacity = 0.75,
    this.fontScale = 1.0,
    this.fontFamily,
    this.edge = CaptionEdgeStyle.dropShadow,
  });

  /// Text/foreground color. CaptionAppearance.swift:16.
  final Color foreground;

  /// Opacity of the text itself (0...1). CaptionAppearance.swift:28.
  final double foregroundOpacity;

  /// Character-cell background color. CaptionAppearance.swift:31.
  final Color background;

  /// Opacity of the character-cell background (0...1). CaptionAppearance.swift:34.
  final double backgroundOpacity;

  /// Font size multiplier, clamped 0.25-4.0 by `CaptionAppearance.fontScale`
  /// (CaptionAppearance.swift:135-138). CaptionAppearance.swift:38.
  final double fontScale;

  /// System caption font family. `null` falls back to the default caption
  /// font (CaptionAppearance.swift:65-70's `.systemFont` fallback).
  final String? fontFamily;

  /// Text edge (shadow/raised/etc.) style. CaptionAppearance.swift:52.
  final CaptionEdgeStyle edge;

  static const CaptionStyle fallback = CaptionStyle();

  /// A version of this style with every numeric field clamped to a safe,
  /// renderable range, matching `CaptionAppearance.fontScale`'s 0.25-4.0
  /// clamp (CaptionAppearance.swift:137) and MediaAccessibility's implicit
  /// 0...1 opacity contract. Invalid/NaN/negative input never blanks the
  /// caption or throws — it falls back to the matching `default` field.
  CaptionStyle sanitized() => CaptionStyle(
    foreground: foreground,
    foregroundOpacity: foregroundOpacity.isFinite
        ? foregroundOpacity.clamp(0.0, 1.0)
        : 1.0,
    background: background,
    backgroundOpacity: backgroundOpacity.isFinite
        ? backgroundOpacity.clamp(0.0, 1.0)
        : 0.75,
    fontScale: (fontScale.isFinite && fontScale > 0)
        ? fontScale.clamp(0.25, 4.0)
        : 1.0,
    fontFamily: fontFamily,
    edge: edge,
  );

  /// Edge-treatment text decorations independent of edge style, matching
  /// `CaptionBoxView.applyEdge` (CaptionOverlayView.swift:741-788): a
  /// drop shadow is a soft offset shadow; raised/depressed are a hard
  /// 1-shadow emboss in opposite directions; uniform is a stroke handled by
  /// the caller (Flutter has no attributed-string negative stroke width, so
  /// [CaptionLayer] paints it as a `Text.strokeWidth`-style outline via two
  /// stacked [Text] widgets); none paints nothing extra.
  List<Shadow> edgeShadows(double pointSize) {
    final depth = (pointSize * 0.04).clamp(1.0, double.infinity);
    return switch (edge) {
      CaptionEdgeStyle.none || CaptionEdgeStyle.uniform => const <Shadow>[],
      CaptionEdgeStyle.dropShadow => [
        Shadow(
          color: Colors.black.withValues(alpha: 0.85),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
      ],
      CaptionEdgeStyle.raised => [
        Shadow(
          color: Colors.black.withValues(alpha: 0.9),
          offset: Offset(depth, depth),
        ),
      ],
      CaptionEdgeStyle.depressed => [
        Shadow(
          color: Colors.black.withValues(alpha: 0.9),
          offset: Offset(-depth, -depth),
        ),
      ],
    };
  }
}
