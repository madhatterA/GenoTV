import 'package:contracts/contracts.dart';
import 'package:flutter/foundation.dart';

enum TitleKind { movie, tv }

enum TitleBase { discover, person, search, trending }

enum TitlePersonRole { cast, crew }

enum TitleSort { popularity, rating, releaseDate, title }

@immutable
class TitleQuery {
  TitleQuery({
    required this.kind,
    this.base = TitleBase.discover,
    this.personId,
    this.personRole = TitlePersonRole.cast,
    String searchText = '',
    List<int> genreIds = const [],
    List<int> keywordIds = const [],
    this.countryCode,
    this.yearFrom,
    this.yearTo,
    this.sort = TitleSort.popularity,
  }) : searchText = searchText.trim(),
       genreIds = List.unmodifiable(genreIds.toSet().toList()..sort()),
       keywordIds = List.unmodifiable(keywordIds.toSet().toList()..sort()) {
    if (base == TitleBase.person && (personId == null || personId! <= 0)) {
      throw ArgumentError('Person id must be positive');
    }
    if (base == TitleBase.search && this.searchText.isEmpty) {
      throw ArgumentError('Search text must not be empty');
    }
    if ([...genreIds, ...keywordIds].any((id) => id <= 0)) {
      throw ArgumentError('Genre ids must be positive');
    }
    if (countryCode != null && !RegExp(r'^[A-Z]{2}$').hasMatch(countryCode!)) {
      throw ArgumentError('Country must be an ISO two-letter code');
    }
    final current = DateTime.now().year;
    if ((yearFrom != null && (yearFrom! < 1900 || yearFrom! > current)) ||
        (yearTo != null && (yearTo! < 1900 || yearTo! > current)) ||
        (yearFrom != null && yearTo != null && yearFrom! > yearTo!)) {
      throw ArgumentError('Invalid year range');
    }
  }
  final TitleKind kind;
  final TitleBase base;
  final int? personId;
  final TitlePersonRole personRole;
  final String searchText;
  final List<int> genreIds;
  final List<int> keywordIds;
  final String? countryCode;
  final int? yearFrom, yearTo;
  final TitleSort sort;
  TitleQuery copyWith({
    TitleKind? kind,
    TitleBase? base,
    int? personId,
    TitlePersonRole? personRole,
    String? searchText,
    List<int>? genreIds,
    List<int>? keywordIds,
    String? countryCode,
    int? yearFrom,
    int? yearTo,
    TitleSort? sort,
    bool clearCountry = false,
    bool clearYears = false,
  }) => TitleQuery(
    kind: kind ?? this.kind,
    base: base ?? this.base,
    personId: personId ?? this.personId,
    personRole: personRole ?? this.personRole,
    searchText: searchText ?? this.searchText,
    genreIds: genreIds ?? this.genreIds,
    keywordIds: keywordIds ?? this.keywordIds,
    countryCode: clearCountry ? null : countryCode ?? this.countryCode,
    yearFrom: clearYears ? null : yearFrom ?? this.yearFrom,
    yearTo: clearYears ? null : yearTo ?? this.yearTo,
    sort: sort ?? this.sort,
  );
  @override
  bool operator ==(Object other) =>
      other is TitleQuery &&
      kind == other.kind &&
      base == other.base &&
      personId == other.personId &&
      personRole == other.personRole &&
      searchText == other.searchText &&
      listEquals(genreIds, other.genreIds) &&
      listEquals(keywordIds, other.keywordIds) &&
      countryCode == other.countryCode &&
      yearFrom == other.yearFrom &&
      yearTo == other.yearTo &&
      sort == other.sort;
  @override
  int get hashCode => Object.hash(
    kind,
    base,
    personId,
    personRole,
    searchText,
    Object.hashAll(genreIds),
    Object.hashAll(keywordIds),
    countryCode,
    yearFrom,
    yearTo,
    sort,
  );
}

@immutable
class TitleFilterOption<T> {
  const TitleFilterOption(this.value, this.label);
  final T value;
  final String label;
}

@immutable
class TitleMetadata {
  TitleMetadata({
    this.popularity = 0,
    this.rating = 0,
    this.voteCount = 0,
    this.releaseDate,
    List<int> genreIds = const [],
    List<String> countryCodes = const [],
  }) : genreIds = List.unmodifiable(genreIds),
       countryCodes = List.unmodifiable(countryCodes);
  final double popularity, rating;
  final int voteCount;
  final DateTime? releaseDate;
  final List<int> genreIds;
  final List<String> countryCodes;
}

class TitlePage {
  TitlePage({
    required List<MediaItem> items,
    this.nextPage,
    Map<String, TitleMetadata> metadata = const {},
  }) : items = List.unmodifiable(items),
       metadata = Map.unmodifiable(metadata);
  final List<MediaItem> items;
  final int? nextPage;
  final Map<String, TitleMetadata> metadata;
}

typedef TitlePageSource = Future<TitlePage> Function(
  TitleQuery query,
  int page,
);
List<MediaItem> sortTitles(
  List<MediaItem> items,
  TitleQuery query,
  Map<String, TitleMetadata> metadata,
) {
  final result = List<MediaItem>.of(items);
  final positions = {
    for (var index = 0; index < items.length; index++) items[index].id: index,
  };
  result.sort((a, b) {
    final ma = metadata[a.id], mb = metadata[b.id];
    final comparison = switch (query.sort) {
      TitleSort.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      TitleSort.popularity => (mb?.popularity ?? 0).compareTo(
        ma?.popularity ?? 0,
      ),
      TitleSort.rating => (mb?.rating ?? 0).compareTo(ma?.rating ?? 0),
      TitleSort.releaseDate =>
        (mb?.releaseDate?.millisecondsSinceEpoch ?? 0).compareTo(
          ma?.releaseDate?.millisecondsSinceEpoch ?? 0,
        ),
    };
    return comparison != 0
        ? comparison
        : positions[a.id]!.compareTo(positions[b.id]!);
  });
  return result;
}
