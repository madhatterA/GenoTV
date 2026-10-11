import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'caption_layout.dart';
import 'caption_style.dart';

/// Extra bottom clearance from `SubtitleAdjustments.bottomMarginFraction`
/// (research/Rivulet/Rivulet/Views/Player/Subtitles/SubtitleAdjustments.swift:111),
/// a fraction of the PICTURE height so a letterboxed cue sits on the image,
/// not in the black bar.
const double _bottomMarginFraction = 0.06;

/// `SubtitleAdjustments.railTopFromScreenBottom`
/// (SubtitleAdjustments.swift:99): the rail's top edge measured from the
/// bottom of the screen, `PlayerRailView.railHeight`(260) + bottom inset(84).
const double _railTopFromScreenBottom = 344;

/// `CaptionOverlayView.Metrics.sideSafeFraction`
/// (research/Rivulet/Rivulet/Views/Player/UIKit/CaptionOverlayView.swift:231):
/// no-go zone at each side of the PICTURE.
const double _sideSafeFraction = 0.05;

/// `CaptionOverlayView.Metrics.defaultBandSideInset`
/// (CaptionOverlayView.swift:208): horizontal room the default band leaves
/// itself so a long caption wraps inside the picture.
const double _defaultBandSideInset = 120.0;

/// `CaptionOverlayView.Metrics.cueSpacing` (CaptionOverlayView.swift:204):
/// gap between distinct simultaneous cues in the default band.
const double _cueSpacing = 4.0;

/// `CaptionOverlayView.Metrics.sizeLadder`'s default-scale rung
/// (CaptionOverlayView.swift:138): caption point size as a fraction of the
/// PRESENTATION height at `fontScale == 1.0`.
const double _fontHeightFraction = 0.0428;

/// `CaptionOverlayView.Metrics.liftDuration` (CaptionOverlayView.swift:239):
/// the rail-driven lift's duration, matching the chrome's own 0.25s fade.
const Duration kCaptionLiftDuration = Duration(milliseconds: 250);

/// Renders the cues active at [sourceTime], placed relative to the
/// aspect-fit rectangle of [videoSize] within the layer's own bounds — never
/// the raw viewport (CaptionOverlayView.swift:452-455). Never intercepts
/// focus or hit-testing (CaptionOverlayView.swift:265's
/// `isUserInteractionEnabled = false`); when [announceForAccessibility] is
/// on, exposes one combined semantics label instead of per-cue labels.
class CaptionLayer extends StatelessWidget {
  const CaptionLayer({
    required this.cues,
    required this.sourceTime,
    this.videoSize = Size.zero,
    this.chromeVisible = false,
    this.style = CaptionStyle.fallback,
    this.reducedMotion = false,
    this.announceForAccessibility = false,
    this.liftDuration = kCaptionLiftDuration,
    super.key,
  });

  /// Full cue set (not just the active ones); [activeCaptionCues] resolves
  /// delay/dedupe/timing internally.
  final List<CaptionCue> cues;

  final Duration sourceTime;

  /// `Size.zero` means unknown — the aspect-fit rect then falls back to the
  /// layer's full bounds, matching `videoRect(in:)`'s guard
  /// (CaptionOverlayView.swift:318-320).
  final Size videoSize;

  /// True while the player rail/chrome is visible; lifts the default band
  /// clear of it (SubtitleAdjustments.controlsFloor, SubtitleAdjustments.swift:
  /// 116-118).
  final bool chromeVisible;

  final CaptionStyle style;

  /// Snaps the chrome-avoidance lift instead of animating it
  /// (`MediaQuery.disableAnimations`, this Part's established convention —
  /// see ArtworkView's `heroCrossfade` handling in `components/artwork.dart`).
  final bool reducedMotion;

  /// When true, exposes a single combined semantics label for the active
  /// cues (caller-gated caption announcements — phase step 6). The layer
  /// stays excluded from focus/hit-testing either way.
  final bool announceForAccessibility;

  final Duration liftDuration;

  @override
  Widget build(BuildContext context) {
    final active = activeCaptionCues(cues, sourceTime);
    final sanitizedStyle = style.sanitized();

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final rect = videoRectFor(viewport, videoSize);
        final pointSize =
            rect.height * _fontHeightFraction * sanitizedStyle.fontScale;
        final floor = _captionFloor(rect, viewport, chromeVisible);
        final safeInsetX = rect.width * _sideSafeFraction;

        final unplaced = <CaptionTextCue>[];
        final placed = <CaptionCue>[];
        for (final cue in active) {
          if (cue.placement == null && cue is CaptionTextCue) {
            unplaced.add(cue);
          } else {
            placed.add(cue);
          }
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            if (unplaced.isNotEmpty)
              Positioned.fromRect(
                rect: rect,
                child: _AnimatedFloorPadding(
                  floor: floor,
                  duration: reducedMotion ? Duration.zero : liftDuration,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: _defaultBandSideInset,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < unplaced.length; i++) ...[
                            if (i > 0) const SizedBox(height: _cueSpacing),
                            _CaptionBox(
                              cue: unplaced[i],
                              style: sanitizedStyle,
                              pointSize: pointSize,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            for (final cue in placed)
              if (cue is CaptionImageCue)
                Positioned.fromRect(
                  rect: Rect.fromLTWH(
                    rect.left + cue.position.left * rect.width,
                    rect.top + cue.position.top * rect.height,
                    cue.position.width * rect.width,
                    cue.position.height * rect.height,
                  ),
                  child: Image(image: cue.image, fit: BoxFit.fill),
                )
              else
                Positioned.fromRect(
                  rect: rect,
                  child: _PlacedCue(
                    cue: cue as CaptionTextCue,
                    style: sanitizedStyle,
                    pointSize: pointSize,
                    floor: floor,
                    safeInsetX: safeInsetX,
                    rectSize: rect.size,
                  ),
                ),
          ],
        );
      },
    );

    if (announceForAccessibility && active.isNotEmpty) {
      content = Semantics(
        container: true,
        label: active
            .whereType<CaptionTextCue>()
            .map((c) => c.runs.map((r) => r.text).join())
            .where((s) => s.isNotEmpty)
            .join('\n'),
        excludeSemantics: true,
        child: content,
      );
    } else {
      content = ExcludeSemantics(child: content);
    }

    return IgnorePointer(child: content);
  }
}

/// The lowest a caption may sit, as a distance from the bottom of the
/// container. Ports `CaptionOverlayView.placementFloor`
/// (CaptionOverlayView.swift:342-350).
double _captionFloor(Rect videoRect, Size viewportSize, bool chromeVisible) {
  final letterbox = math.max(0.0, viewportSize.height - videoRect.bottom);
  var base = letterbox + videoRect.height * _bottomMarginFraction;
  if (chromeVisible) {
    final controlsFloor =
        _railTopFromScreenBottom + videoRect.height * _bottomMarginFraction;
    base = math.max(base, controlsFloor);
  }
  return base;
}

/// Animates [floor] under [duration], or snaps to it when [duration] is
/// zero (reduced motion) — CaptionOverlayView.swift:563-571's
/// `setControlsVisible(_:animated:)`.
class _AnimatedFloorPadding extends StatelessWidget {
  const _AnimatedFloorPadding({
    required this.floor,
    required this.duration,
    required this.child,
  });

  final double floor;
  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedPadding(
    duration: duration,
    curve: Curves.easeInOut,
    padding: EdgeInsets.only(bottom: floor),
    child: child,
  );
}

/// One cue the source positioned itself, against the PICTURE
/// (CaptionOverlayView.swift:452-556). A fine [CaptionPlacement.dx]/[dy]
/// wins; otherwise the cue rests at its anchor's safe-area edge, and the
/// shared [floor] still clamps a bottom-row cue (CaptionOverlayView.swift:
/// 339-341's "placed cues obey it too").
class _PlacedCue extends StatelessWidget {
  const _PlacedCue({
    required this.cue,
    required this.style,
    required this.pointSize,
    required this.floor,
    required this.safeInsetX,
    required this.rectSize,
  });

  final CaptionTextCue cue;
  final CaptionStyle style;
  final double pointSize;
  final double floor;
  final double safeInsetX;
  final Size rectSize;

  @override
  Widget build(BuildContext context) {
    final placement = cue.placement ?? const CaptionPlacement();
    final dx = placement.dx?.clamp(0.0, 1.0);
    final dy = placement.dy?.clamp(0.0, 1.0);

    // Fine position: named as the box's own alignment point, clamped inside
    // the picture's safe area on both axes; the shared floor still bounds
    // the vertical axis so a placed cue cannot sit under the rail.
    final safeInsetYFraction =
        floor / (rectSize.height == 0 ? 1 : rectSize.height);
    final x =
        dx ??
        (placement.isLeftColumn
            ? 0.1
            : placement.isRightColumn
            ? 0.9
            : 0.5);
    final y = (dy ?? _rowFractionFor(placement.anchor)).clamp(
      0.0,
      1.0 - safeInsetYFraction,
    );
    final clampedX = x.clamp(
      safeInsetX / (rectSize.width == 0 ? 1 : rectSize.width),
      1 - safeInsetX / (rectSize.width == 0 ? 1 : rectSize.width),
    );

    return Align(
      alignment: Alignment(clampedX * 2 - 1, y * 2 - 1),
      child: _CaptionBox(cue: cue, style: style, pointSize: pointSize),
    );
  }
}

double _rowFractionFor(CaptionAnchor anchor) => switch (anchor) {
  CaptionAnchor.topLeft ||
  CaptionAnchor.topCenter ||
  CaptionAnchor.topRight => 0.10,
  CaptionAnchor.middleLeft ||
  CaptionAnchor.middleCenter ||
  CaptionAnchor.middleRight => 0.5,
  CaptionAnchor.bottomLeft ||
  CaptionAnchor.bottomCenter ||
  CaptionAnchor.bottomRight => 0.94,
};

/// One cue in one rounded box, mirroring `CaptionBoxView`
/// (CaptionOverlayView.swift:583-835): background box for every edge style
/// except `uniform`, which draws a stroked outline instead
/// (CaptionOverlayView.swift:640-645, 758-763).
class _CaptionBox extends StatelessWidget {
  const _CaptionBox({
    required this.cue,
    required this.style,
    required this.pointSize,
  });

  final CaptionTextCue cue;
  final CaptionStyle style;
  final double pointSize;

  @override
  Widget build(BuildContext context) {
    final align = cue.textAlign ?? _textAlignFor(cue.placement);
    final span = TextSpan(
      children: [
        for (final run in cue.runs)
          TextSpan(
            text: run.text,
            style: TextStyle(
              fontSize: pointSize,
              fontFamily: style.fontFamily,
              fontWeight: run.bold ? FontWeight.bold : FontWeight.w500,
              fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
              decoration: run.underline
                  ? TextDecoration.underline
                  : TextDecoration.none,
              color: (run.color ?? style.foreground).withValues(
                alpha: style.foregroundOpacity,
              ),
              shadows: style.edge == CaptionEdgeStyle.uniform
                  ? null
                  : style.edgeShadows(pointSize),
            ),
          ),
      ],
    );

    final isUniform = style.edge == CaptionEdgeStyle.uniform;
    final padH = isUniform ? 0.0 : pointSize * 0.30;
    final padV = isUniform ? 0.0 : pointSize * 0.075;

    Widget text = Text.rich(span, textAlign: align, softWrap: true);
    if (isUniform) {
      // Simulated stroke: a black-stroked copy of the same text painted
      // behind the fill copy — Flutter's Text has no negative-stroke-width
      // attributed-string equivalent (CaptionOverlayView.swift:761's
      // `strokeWidth: -4`).
      final strokeSpan = TextSpan(
        children: [
          for (final run in cue.runs)
            TextSpan(
              text: run.text,
              style: TextStyle(
                fontSize: pointSize,
                fontFamily: style.fontFamily,
                fontWeight: run.bold ? FontWeight.bold : FontWeight.w500,
                fontStyle: run.italic ? FontStyle.italic : FontStyle.normal,
                foreground: Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = pointSize * 0.08
                  ..color = Colors.black,
              ),
            ),
        ],
      );
      text = Stack(
        children: [
          Text.rich(strokeSpan, textAlign: align, softWrap: true),
          Text.rich(span, textAlign: align, softWrap: true),
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUniform
            ? Colors.transparent
            : style.background.withValues(alpha: style.backgroundOpacity),
        borderRadius: BorderRadius.circular(pointSize * 0.25),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
        child: text,
      ),
    );
  }
}

TextAlign _textAlignFor(CaptionPlacement? placement) {
  if (placement == null) return TextAlign.center;
  if (placement.isLeftColumn) return TextAlign.left;
  if (placement.isRightColumn) return TextAlign.right;
  return TextAlign.center;
}
