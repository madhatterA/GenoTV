import 'package:flutter/foundation.dart';

/// Immutable UI-only presentation values used by later chapters. These carry
/// display data and identifiers only — never a repository, controller, or
/// future. The composition root maps real data onto these later; this
/// package never imports a database, network client, or platform API to
/// populate them. See `PART.md`'s ownership boundary.

@immutable
final class UiMediaCard {
  const UiMediaCard({
    required this.id,
    required this.title,
    this.subtitle,
    this.artworkUrl,
    this.badgeLabel,
    this.watchedFraction,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? artworkUrl;
  final String? badgeLabel;

  /// 0.0-1.0 continue-watching progress, or null when not started/tracked.
  final double? watchedFraction;

  UiMediaCard copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? artworkUrl,
    String? badgeLabel,
    double? watchedFraction,
  }) => UiMediaCard(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    badgeLabel: badgeLabel ?? this.badgeLabel,
    watchedFraction: watchedFraction ?? this.watchedFraction,
  );

  @override
  bool operator ==(Object other) =>
      other is UiMediaCard &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.artworkUrl == artworkUrl &&
      other.badgeLabel == badgeLabel &&
      other.watchedFraction == watchedFraction;

  @override
  int get hashCode =>
      Object.hash(id, title, subtitle, artworkUrl, badgeLabel, watchedFraction);
}

@immutable
final class UiHeroItem {
  const UiHeroItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.logoUrl,
    this.backdropUrl,
    this.tagline,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? logoUrl;
  final String? backdropUrl;
  final String? tagline;

  UiHeroItem copyWith({
    String? id,
    String? title,
    String? subtitle,
    String? logoUrl,
    String? backdropUrl,
    String? tagline,
  }) => UiHeroItem(
    id: id ?? this.id,
    title: title ?? this.title,
    subtitle: subtitle ?? this.subtitle,
    logoUrl: logoUrl ?? this.logoUrl,
    backdropUrl: backdropUrl ?? this.backdropUrl,
    tagline: tagline ?? this.tagline,
  );

  @override
  bool operator ==(Object other) =>
      other is UiHeroItem &&
      other.id == id &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.logoUrl == logoUrl &&
      other.backdropUrl == backdropUrl &&
      other.tagline == tagline;

  @override
  int get hashCode =>
      Object.hash(id, title, subtitle, logoUrl, backdropUrl, tagline);
}

@immutable
final class UiShelf {
  const UiShelf({
    required this.id,
    required this.title,
    required this.cards,
    this.isContinueWatching = false,
  });

  final String id;
  final String title;
  final List<UiMediaCard> cards;
  final bool isContinueWatching;

  UiShelf copyWith({
    String? id,
    String? title,
    List<UiMediaCard>? cards,
    bool? isContinueWatching,
  }) => UiShelf(
    id: id ?? this.id,
    title: title ?? this.title,
    cards: cards ?? this.cards,
    isContinueWatching: isContinueWatching ?? this.isContinueWatching,
  );

  @override
  bool operator ==(Object other) =>
      other is UiShelf &&
      other.id == id &&
      other.title == title &&
      listEquals(other.cards, cards) &&
      other.isContinueWatching == isContinueWatching;

  @override
  int get hashCode =>
      Object.hash(id, title, Object.hashAll(cards), isContinueWatching);
}

@immutable
final class UiEpisode {
  const UiEpisode({
    required this.id,
    required this.seasonId,
    required this.index,
    required this.title,
    this.overview,
    this.artworkUrl,
    this.duration,
    this.watchedFraction,
  });

  final String id;
  final String seasonId;
  final int index;
  final String title;
  final String? overview;
  final String? artworkUrl;
  final Duration? duration;
  final double? watchedFraction;

  UiEpisode copyWith({
    String? id,
    String? seasonId,
    int? index,
    String? title,
    String? overview,
    String? artworkUrl,
    Duration? duration,
    double? watchedFraction,
  }) => UiEpisode(
    id: id ?? this.id,
    seasonId: seasonId ?? this.seasonId,
    index: index ?? this.index,
    title: title ?? this.title,
    overview: overview ?? this.overview,
    artworkUrl: artworkUrl ?? this.artworkUrl,
    duration: duration ?? this.duration,
    watchedFraction: watchedFraction ?? this.watchedFraction,
  );

  @override
  bool operator ==(Object other) =>
      other is UiEpisode &&
      other.id == id &&
      other.seasonId == seasonId &&
      other.index == index &&
      other.title == title &&
      other.overview == overview &&
      other.artworkUrl == artworkUrl &&
      other.duration == duration &&
      other.watchedFraction == watchedFraction;

  @override
  int get hashCode => Object.hash(
    id,
    seasonId,
    index,
    title,
    overview,
    artworkUrl,
    duration,
    watchedFraction,
  );
}

@immutable
final class UiSeason {
  const UiSeason({
    required this.id,
    required this.seriesId,
    required this.index,
    required this.title,
    required this.episodeIds,
  });

  final String id;
  final String seriesId;
  final int index;
  final String title;
  final List<String> episodeIds;

  UiSeason copyWith({
    String? id,
    String? seriesId,
    int? index,
    String? title,
    List<String>? episodeIds,
  }) => UiSeason(
    id: id ?? this.id,
    seriesId: seriesId ?? this.seriesId,
    index: index ?? this.index,
    title: title ?? this.title,
    episodeIds: episodeIds ?? this.episodeIds,
  );

  @override
  bool operator ==(Object other) =>
      other is UiSeason &&
      other.id == id &&
      other.seriesId == seriesId &&
      other.index == index &&
      other.title == title &&
      listEquals(other.episodeIds, episodeIds);

  @override
  int get hashCode =>
      Object.hash(id, seriesId, index, title, Object.hashAll(episodeIds));
}

@immutable
final class UiPerson {
  const UiPerson({
    required this.id,
    required this.name,
    this.role,
    this.photoUrl,
  });

  final String id;
  final String name;
  final String? role;
  final String? photoUrl;

  UiPerson copyWith({
    String? id,
    String? name,
    String? role,
    String? photoUrl,
  }) => UiPerson(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    photoUrl: photoUrl ?? this.photoUrl,
  );

  @override
  bool operator ==(Object other) =>
      other is UiPerson &&
      other.id == id &&
      other.name == name &&
      other.role == role &&
      other.photoUrl == photoUrl;

  @override
  int get hashCode => Object.hash(id, name, role, photoUrl);
}

@immutable
final class UiChapter {
  const UiChapter({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final Duration start;
  final Duration end;

  UiChapter copyWith({
    String? id,
    String? title,
    Duration? start,
    Duration? end,
  }) => UiChapter(
    id: id ?? this.id,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  @override
  bool operator ==(Object other) =>
      other is UiChapter &&
      other.id == id &&
      other.title == title &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, title, start, end);
}

/// intro / credits / commercial, per the player progress rail marker colors
/// (pinned in ch03-p04, not here).
enum UiMarkerKind { intro, credits, commercial }

@immutable
final class UiMarker {
  const UiMarker({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
  });

  final String id;
  final UiMarkerKind kind;
  final Duration start;
  final Duration end;

  UiMarker copyWith({
    String? id,
    UiMarkerKind? kind,
    Duration? start,
    Duration? end,
  }) => UiMarker(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    start: start ?? this.start,
    end: end ?? this.end,
  );

  @override
  bool operator ==(Object other) =>
      other is UiMarker &&
      other.id == id &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, kind, start, end);
}

@immutable
final class UiTrackOption {
  const UiTrackOption({
    required this.id,
    required this.label,
    required this.isAudio,
    this.isSelected = false,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final bool isAudio;
  final bool isSelected;
  final bool isDefault;

  UiTrackOption copyWith({
    String? id,
    String? label,
    bool? isAudio,
    bool? isSelected,
    bool? isDefault,
  }) => UiTrackOption(
    id: id ?? this.id,
    label: label ?? this.label,
    isAudio: isAudio ?? this.isAudio,
    isSelected: isSelected ?? this.isSelected,
    isDefault: isDefault ?? this.isDefault,
  );

  @override
  bool operator ==(Object other) =>
      other is UiTrackOption &&
      other.id == id &&
      other.label == label &&
      other.isAudio == isAudio &&
      other.isSelected == isSelected &&
      other.isDefault == isDefault;

  @override
  int get hashCode => Object.hash(id, label, isAudio, isSelected, isDefault);
}
