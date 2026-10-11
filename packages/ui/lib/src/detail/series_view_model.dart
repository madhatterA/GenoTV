import 'package:flutter/foundation.dart';
import 'package:contracts/contracts.dart';

class SeriesEpisode {
  const SeriesEpisode({
    required this.season,
    required this.episode,
    required this.title,
    required this.duration,
    required this.description,
    this.still,
    this.progress,
  });

  final int season;
  final int episode;
  final String title;
  final Duration duration;
  final String description;
  final Uri? still;

  /// Watched fraction (0-1) of a partly watched episode; null otherwise.
  final double? progress;
}

class SeriesSeason {
  const SeriesSeason({
    required this.number,
    required this.title,
    required this.episodes,
  });

  final int number;
  final String title;
  final List<SeriesEpisode> episodes;
}

class SeriesViewModel extends ChangeNotifier {
  SeriesViewModel({
    required List<SeriesSeason> seasons,
    this.nextUpRepository,
    this.seriesId,
  }) : seasons = List<SeriesSeason>.unmodifiable(seasons),
       _selectedSeason = seasons.isEmpty ? null : seasons.first.number,
       assert(
         nextUpRepository == null || seriesId != null,
         'seriesId is required when nextUpRepository is provided',
       );

  final List<SeriesSeason> seasons;
  final NextUpRepository? nextUpRepository;
  final String? seriesId;
  int? _selectedSeason;
  SeriesEpisode? _focusedEpisode;
  SeriesEpisode? _nextUp;

  int? get selectedSeason => _selectedSeason;
  SeriesEpisode? get focusedEpisode => _focusedEpisode;
  SeriesEpisode? get nextUp => _nextUp;
  SeriesSeason? get season => seasons.cast<SeriesSeason?>().firstWhere(
    (value) => value?.number == _selectedSeason,
    orElse: () => null,
  );

  void selectSeason(int number) {
    if (_selectedSeason == number) return;
    _selectedSeason = number;
    _focusedEpisode = season?.episodes.firstOrNull;
    notifyListeners();
  }

  void focusEpisode(SeriesEpisode episode) {
    if (_focusedEpisode == episode) return;
    _focusedEpisode = episode;
    notifyListeners();
  }

  Future<void> loadNextUp() async {
    final repository = nextUpRepository;
    final id = seriesId;
    if (repository == null || id == null) return;
    final entry = await repository.forSeries(id);
    _nextUp = entry == null ? null : _episode(entry.season, entry.episode);
    notifyListeners();
  }

  Future<void> setNextUp(SeriesEpisode episode, {String? mediaId}) async {
    _nextUp = episode;
    notifyListeners();
    final repository = nextUpRepository;
    final id = seriesId;
    if (repository == null || id == null) return;
    await repository.set(
      NextUpEntry(
        seriesId: id,
        mediaId: mediaId ?? '$id-s${episode.season}e${episode.episode}',
        season: episode.season,
        episode: episode.episode,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> clearNextUp() async {
    _nextUp = null;
    notifyListeners();
    final repository = nextUpRepository;
    final id = seriesId;
    if (repository == null || id == null) return;
    await repository.clear(id);
  }

  SeriesEpisode? _episode(int season, int episode) => seasons
      .firstWhere(
        (value) => value.number == season,
        orElse: () => const SeriesSeason(number: -1, title: '', episodes: []),
      )
      .episodes
      .cast<SeriesEpisode?>()
      .firstWhere((value) => value?.episode == episode, orElse: () => null);
}
