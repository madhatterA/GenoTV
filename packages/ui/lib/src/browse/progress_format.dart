/// Shared formatting for `MediaProgressInfoBar.swift`-style info text:
/// season/episode label plus a remaining-or-runtime string.
///
/// `MediaProgressInfoBar.swift:97-118` builds `"S{n}, E{n}"` from numeric
/// `parentIndex`/`index` fields the persisted `MediaItem` contract (Part 01,
/// `packages/contracts/lib/src/media/media_item.dart`) does not carry —
/// only a pre-joined `subtitle` string like `"S02E04 · Sample Episode"`.
/// Adding season/episode numbers to the shared contract is its own
/// cross-Part request (`CLAUDE.md` "Part isolation"), so this parses the
/// existing `subtitle` when it matches the `SxxEyy` shape and falls back to
/// using it verbatim otherwise (decisions.md, Phase 02 Decision 1).
final RegExp _seasonEpisodePattern = RegExp(r'^S(\d+)E(\d+)');

/// Returns the `"S{n}, E{n}"` prefix parsed out of [subtitle], or null if it
/// doesn't match the pattern this app writes for episode subtitles.
String? seasonEpisodeLabel(String? subtitle) {
  if (subtitle == null) return null;
  final match = _seasonEpisodePattern.firstMatch(subtitle);
  if (match == null) return null;
  final season = int.parse(match.group(1)!);
  final episode = int.parse(match.group(2)!);
  return 'S$season, E$episode';
}

/// `"1h 7m"` / `"35m"` — `MediaProgressInfoBar.swift:108-109`'s
/// remaining/duration formatting. A duration under one minute is omitted
/// (returns null) per phase step 4 ("values under one minute are omitted").
String? formatRemaining(Duration? remaining) {
  if (remaining == null) return null;
  final totalMinutes = remaining.inMinutes;
  if (totalMinutes < 1) return null;
  final hours = totalMinutes ~/ 60;
  final minutes = totalMinutes % 60;
  if (hours <= 0) return '${minutes}m';
  if (minutes <= 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Builds the full `MediaProgressInfoBar` text — `"S1, E2 • 35m"` — from an
/// item's subtitle and its remaining time (duration minus position). Joins
/// only the parts that are present; returns null if neither is.
String? progressInfoText({
  required String? subtitle,
  required Duration? remaining,
}) {
  final parts = <String>[
    ?seasonEpisodeLabel(subtitle),
    ?formatRemaining(remaining),
  ];
  return parts.isEmpty ? null : parts.join(' • ');
}
