import 'package:flutter/material.dart';

/// Numpad-style coarse anchor for a cue with no fine position (teletext
/// through a demux, per `CaptionOverlayView.layoutPlaced`'s doc comment,
/// research/Rivulet/Rivulet/Views/Player/UIKit/CaptionOverlayView.swift:
/// 452-469). `null` (no [CaptionPlacement] at all) means the cue is
/// unplaced and joins the default bottom-stacking band.
enum CaptionAnchor {
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleCenter,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Where a cue's own source data placed it, resolved relative to the
/// aspect-fit VIDEO rectangle, never the raw viewport
/// (CaptionOverlayView.swift:452-455). A fine [dx]/[dy] (0...1, clamped)
/// wins over [anchor] when present, mirroring `layoutPlaced`'s "a fine
/// position wins; the band is the fallback" (CaptionOverlayView.swift:532).
@immutable
class CaptionPlacement {
  const CaptionPlacement({
    this.anchor = CaptionAnchor.bottomCenter,
    this.dx,
    this.dy,
  });

  final CaptionAnchor anchor;

  /// Fractional horizontal position (0 = left, 1 = right) within the video
  /// rect, or `null` to use [anchor]'s column.
  final double? dx;

  /// Fractional vertical position (0 = top, 1 = bottom) within the video
  /// rect, or `null` to use [anchor]'s row.
  final double? dy;

  bool get isLeftColumn => switch (anchor) {
    CaptionAnchor.topLeft ||
    CaptionAnchor.middleLeft ||
    CaptionAnchor.bottomLeft => true,
    _ => false,
  };

  bool get isRightColumn => switch (anchor) {
    CaptionAnchor.topRight ||
    CaptionAnchor.middleRight ||
    CaptionAnchor.bottomRight => true,
    _ => false,
  };

  @override
  bool operator ==(Object other) =>
      other is CaptionPlacement &&
      other.anchor == anchor &&
      other.dx == dx &&
      other.dy == dy;

  @override
  int get hashCode => Object.hash(anchor, dx, dy);
}

/// One styled run inside a text cue. Ports `AetherSubtitleCue.StyledRun`
/// (research/Rivulet/Rivulet/Views/Player/Aether/AetherSubtitleCue.swift,
/// consumed by CaptionOverlayView.swift:703-721).
@immutable
class CaptionTextRun {
  const CaptionTextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.color,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;

  /// `null` means "use the style's own foreground" — the run carries no
  /// color override, matching `attributedText`'s `contentColor` fallback
  /// (CaptionOverlayView.swift:710-712).
  final Color? color;

  @override
  bool operator ==(Object other) =>
      other is CaptionTextRun &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color;

  @override
  int get hashCode => Object.hash(text, bold, italic, underline, color);
}

/// Base type for one subtitle cue. Immutable value, matching
/// `AetherSubtitleCue`'s content-identity contract
/// (SubtitleModel.swift:103-121): two cues with equal [start]/[end] and
/// equal content are the SAME cue for dedupe purposes; two cues with equal
/// [start]/[end] but different content are DISTINCT and must both render.
@immutable
sealed class CaptionCue {
  const CaptionCue({
    required this.id,
    required this.start,
    required this.end,
    this.delay = Duration.zero,
    required this.sourceOrder,
    this.placement,
  });

  /// Caller-assigned identity (e.g. track index + cue index). Not itself
  /// part of the dedupe key — [contentKey] is — but useful for `Key`s.
  final Object id;

  final Duration start;
  final Duration end;

  /// Per-item display delay. Positive values shift display LATER
  /// (SubtitleModel.swift:29-31: "Positive delay displays later" per this
  /// phase's Decisions table; the effective time subtracts delay from the
  /// clock, which is equivalent to adding it to the cue's own window).
  final Duration delay;

  /// Source order, for deterministic sort among simultaneous cues
  /// (SubtitleModel.swift:166-167 sorts back to original array order).
  final int sourceOrder;

  /// `null` = unplaced (default bottom-stacking band).
  final CaptionPlacement? placement;

  Duration get effectiveStart => start + delay;
  Duration get effectiveEnd => end + delay;

  /// Full content identity used for dedupe — SubtitleModel.swift:104
  /// `(startTime, endTime, body)`. Placement and delay are part of it too,
  /// so a caller that legitimately supplies two cues with identical text
  /// but different placement is not conflated.
  Object get contentKey;
}

/// A text cue: plain text or a list of styled runs.
class CaptionTextCue extends CaptionCue {
  const CaptionTextCue({
    required super.id,
    required super.start,
    required super.end,
    super.delay,
    required super.sourceOrder,
    super.placement,
    required this.runs,
    this.textAlign,
  });

  final List<CaptionTextRun> runs;

  /// Explicit alignment; `null` derives from [placement] the way
  /// `lineAlignment(for:)` does (CaptionOverlayView.swift:443-450).
  final TextAlign? textAlign;

  @override
  Object get contentKey =>
      Object.hash(start, end, placement, Object.hashAll(runs));
}

/// An image (bitmap, e.g. PGS/DVB) cue, positioned as a fraction of the
/// video rect (CaptionOverlayView.swift:374-385).
class CaptionImageCue extends CaptionCue {
  const CaptionImageCue({
    required super.id,
    required super.start,
    required super.end,
    super.delay,
    required super.sourceOrder,
    required this.image,
    required this.position,
  }) : super(placement: null);

  final ImageProvider image;

  /// Fractional rect (0...1 each edge) within the aspect-fit video rect.
  final Rect position;

  @override
  Object get contentKey => Object.hash(start, end, image, position);
}

/// The aspect-fit rectangle of [video] centered within [viewport], mirroring
/// `CaptionOverlayView.videoRect(in:)` (CaptionOverlayView.swift:317-326).
/// Falls back to the full viewport when either size is degenerate/unknown.
Rect videoRectFor(Size viewport, Size video) {
  if (video.width <= 0 ||
      video.height <= 0 ||
      viewport.width <= 0 ||
      viewport.height <= 0) {
    return Rect.fromLTWH(0, 0, viewport.width, viewport.height);
  }
  final scale = (viewport.width / video.width < viewport.height / video.height)
      ? viewport.width / video.width
      : viewport.height / video.height;
  final w = video.width * scale;
  final h = video.height * scale;
  return Rect.fromLTWH(
    (viewport.width - w) / 2,
    (viewport.height - h) / 2,
    w,
    h,
  );
}

/// Applies per-cue [CaptionCue.delay], drops exact-duplicate cues (same
/// [CaptionCue.contentKey]), keeps distinct same-time cues, and returns the
/// set active at [sourceTime] sorted deterministically by source order then
/// placement. Ports `SubtitleModel.computeActiveCues`
/// (SubtitleModel.swift:124-168) at widget-layer granularity: a plain O(n)
/// filter rather than the engine's bounded binary-search walk, which is a
/// performance-only difference — this phase does not own the timed-cue feed.
List<CaptionCue> activeCaptionCues(List<CaptionCue> cues, Duration sourceTime) {
  final seen = <Object>{};
  final active = <CaptionCue>[];
  for (final cue in cues) {
    final s = cue.effectiveStart;
    final e = cue.effectiveEnd;
    if (s <= sourceTime && e >= sourceTime) {
      if (seen.add(cue.contentKey)) {
        active.add(cue);
      }
    }
  }
  active.sort((a, b) {
    final order = a.sourceOrder.compareTo(b.sourceOrder);
    if (order != 0) return order;
    return a.contentKey.hashCode.compareTo(b.contentKey.hashCode);
  });
  return active;
}
