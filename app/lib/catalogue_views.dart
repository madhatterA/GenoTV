import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:content_sources/content_sources.dart';
import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import 'title_grid_source.dart';

/// Trending catalogue titles plus the Liked (favourites) and Watched
/// (all watch history) rows.
class TmdbHomeView extends StatefulWidget {
  const TmdbHomeView({
    required this.catalogue,
    required this.onItemTap,
    required this.favourites,
    required this.progress,
    this.libraryChanged,
    this.retryDelay = const Duration(seconds: 5),
    this.logger,
    this.snapshot,
    super.key,
  });

  /// `home_snapshot.json` in the cache directory: the last browse rows, shown
  /// at once on launch and replaced when fresh data arrives. Personal rows
  /// (Liked, Watched) are never in it.
  final Future<File>? snapshot;

  final TmdbCatalogue catalogue;
  final FavouritesRepository favourites;
  final ProgressRepository progress;

  /// Fires when playback saved a position somewhere other than from Home
  /// (search, genres, a person page): Home is kept alive under its own
  /// Navigator and would otherwise show a stale Continue watching row.
  final Listenable? libraryChanged;
  final AppLogger? logger;

  /// How long a failed load waits before trying again on its own, so the
  /// page recovers by itself when the network comes back.
  final Duration retryDelay;
  final FutureOr<void> Function(BuildContext context, MediaItem item) onItemTap;

  @override
  State<TmdbHomeView> createState() => _TmdbHomeViewState();
}

class _TmdbHomeViewState extends State<TmdbHomeView> {
  final _outage = ConnectionOutageController();
  Future<HomeViewModel>? _loading;

  /// The model on screen. It stays alive while a page is pushed over Home.
  HomeViewModel? _loaded;
  late Future<HomeViewModel> _model = _load();
  Timer? _retry;

  void _onLibraryChanged() => unawaited(_refreshLibrary());

  @override
  void initState() {
    super.initState();
    widget.libraryChanged?.addListener(_onLibraryChanged);
  }

  /// A failed load schedules a quiet retry (the error stays on screen until
  /// one succeeds); the Retry button reloads immediately.
  Future<HomeViewModel> _load() =>
      _loading ??= _loadRows().whenComplete(() => _loading = null);

  Future<HomeViewModel> _loadRows() async {
    _retry?.cancel();
    // Slots in page order: trending movies, trending shows, Liked, Watched.
    // Every row is requested at once and appears when its own data arrives.
    final slots = List<List<HomeRow>?>.filled(5, null);
    final first = Completer<HomeViewModel>();
    final errors = <(Object, StackTrace)>[];
    var browseFailed = 0;
    var freshBrowse = 0;
    HomeViewModel? model;

    void surface(Object error, StackTrace stack) {
      widget.logger?.warn('Home row failed', error: error, stack: stack);
      if (!mounted) return;
      final network =
          error is ContentSourceFailure && error.code == 'provider.network';
      _outage.updateConnection(healthy: !network);
      if (network ||
          error is ContentSourceFailure &&
              error.code == 'provider.unavailable') {
        _retry?.cancel();
        _retry = Timer(widget.retryDelay, _quietRetry);
      }
    }

    void publish() {
      // Continue watching (slot 4) leads the page; the other slots keep their order.
      final rows = [...?slots[4], for (final slot in slots.take(4)) ...?slot];
      if (model != null) {
        if (mounted) model!.replaceRows(rows);
        return;
      }
      if (slots[0] == null && slots[1] == null) return;
      model = _loaded = HomeViewModel(
        rows: rows,
        heroArtwork: widget.catalogue.backdrops,
      );
      first.complete(model);
      for (final (error, stack) in errors) {
        surface(error, stack);
      }
    }

    void failed(int slot, Object error, StackTrace stack) {
      if (slot < 2) browseFailed++;
      if (!first.isCompleted && browseFailed == 2) {
        surface(error, stack);
        first.completeError(error, stack);
      } else if (model != null) {
        surface(error, stack);
      } else {
        errors.add((error, stack));
      }
    }

    void track(int slot, Future<List<HomeRow>> rows) => rows.then((value) {
      if (slot < 2) {
        freshBrowse++;
        if (mounted) _outage.updateConnection(healthy: errors.isEmpty);
      }
      slots[slot] = value;
      publish();
      if (freshBrowse == 2) {
        unawaited(_writeSnapshot([...slots[0]!, ...slots[1]!]));
      }
    }, onError: (Object e, StackTrace s) => failed(slot, e, s));

    track(
      0,
      _row(
        (s) => s.home_trendingMovies,
        MediaKind.movie,
        'trending',
      ).then((row) => [row]),
    );
    track(
      1,
      _row(
        (s) => s.home_trendingShows,
        MediaKind.episode,
        'trending',
      ).then((row) => [row]),
    );
    track(2, _likedRows());
    track(3, _watchedRows());
    track(4, _continueRows());
    unawaited(
      _readSnapshot().then((rows) {
        // Only while no fresh browse row has arrived yet.
        if (rows == null || freshBrowse > 0 || first.isCompleted) return;
        slots[0] = [rows[0]];
        slots[1] = [rows[1]];
        publish();
      }),
    );
    return first.future;
  }

  Future<File?> _snapshotFile() async {
    try {
      return await widget.snapshot;
    } catch (error, stack) {
      widget.logger?.warn('Home snapshot path', error: error, stack: stack);
      return null;
    }
  }

  Map<String, Object?> _itemJson(MediaItem item) => {
    'id': item.id,
    'title': item.title,
    'kind': item.kind.name,
    'artwork': item.artwork?.toString(),
    'year': item.year,
    'tmdbId': item.tmdbId,
    'imdbId': item.imdbId,
    'originalLanguage': item.originalLanguage,
    'backdrop': widget.catalogue.backdrops[item.id]?.toString(),
  };

  Future<void> _writeSnapshot(List<HomeRow> rows) async {
    final file = await _snapshotFile();
    if (file == null) return;
    try {
      await file.writeAsString(
        jsonEncode({
          'rows': [
            for (final row in rows) [for (final i in row.items) _itemJson(i)],
          ],
        }),
      );
    } catch (error, stack) {
      widget.logger?.warn('Home snapshot write', error: error, stack: stack);
    }
  }

  /// The saved [movies, shows] rows, or null when there is no usable file.
  Future<List<HomeRow>?> _readSnapshot() async {
    final file = await _snapshotFile();
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString()) as Map;
      final lists = (json['rows'] as List).cast<List>();
      final backdrops = <String, Uri>{};
      List<MediaItem> items(List raw) => [
        for (final m in raw.cast<Map>())
          () {
            final id = m['id'] as String;
            if (m['backdrop'] case final String b) backdrops[id] = Uri.parse(b);
            return MediaItem(
              id: id,
              title: m['title'] as String,
              kind: MediaKind.values.byName(m['kind'] as String),
              artwork: (m['artwork'] as String?) == null
                  ? null
                  : Uri.parse(m['artwork'] as String),
              year: m['year'] as int?,
              tmdbId: m['tmdbId'] as int?,
              imdbId: m['imdbId'] as String?,
              originalLanguage: m['originalLanguage'] as String?,
            );
          }(),
      ];
      final rows = [
        _rowOf((s) => s.home_trendingMovies, MediaKind.movie, items(lists[0])),
        _rowOf((s) => s.home_trendingShows, MediaKind.episode, items(lists[1])),
      ];
      widget.catalogue.backdrops.addAll(backdrops);
      return rows;
    } catch (error, stack) {
      widget.logger?.warn('Home snapshot read', error: error, stack: stack);
      return null;
    }
  }

  void _quietRetry() => _load().then((model) {
    if (mounted) {
      setState(() {
        _model = Future.value(model);
      });
    }
  }, onError: (Object _) {});

  Future<void> _reload() async {
    final model = await _load();
    if (mounted) setState(() => _model = Future.value(model));
  }

  @override
  void dispose() {
    widget.libraryChanged?.removeListener(_onLibraryChanged);
    _retry?.cancel();
    _outage.dispose();
    super.dispose();
  }

  Future<List<HomeRow>> _likedRows() async {
    final liked = await loadTmdbTitles(
      widget.catalogue,
      await widget.favourites.all(),
      logger: widget.logger,
    );
    return [
      if (liked.isNotEmpty)
        HomeRow(
          title: lookupAppStrings(const Locale('en')).common_liked,
          titleOf: (s) => s.common_liked,
          items: liked,
        ),
    ];
  }

  Future<List<HomeRow>> _watchedRows() async {
    final watched = await loadTmdbTitles(widget.catalogue, [
      for (final entry in await widget.progress.history()) entry.mediaId,
    ], logger: widget.logger);
    return [
      if (watched.isNotEmpty)
        HomeRow(
          title: lookupAppStrings(const Locale('en')).common_watched,
          titleOf: (s) => s.common_watched,
          items: watched,
        ),
    ];
  }

  Future<List<HomeRow>> _libraryRows() async => [
    for (final group in await Future.wait([
      _continueRows(),
      _likedRows(),
      _watchedRows(),
    ]))
      ...group,
  ];

  /// Saved progress of the Continue watching row, for the cards' bars.
  final Map<String, PlaybackProgress> _continueProgress =
      <String, PlaybackProgress>{};

  Future<List<HomeRow>> _continueRows() async {
    final saved = await widget.progress.continueWatching();
    final items = await loadTmdbTitles(widget.catalogue, [
      for (final entry in saved) entry.mediaId,
    ], logger: widget.logger);
    _continueProgress
      ..clear()
      ..addEntries(saved.map((e) => MapEntry(e.mediaId, e)));
    return [
      if (items.isNotEmpty)
        HomeRow(
          title: lookupAppStrings(const Locale('en')).common_continueWatching,
          titleOf: (s) => s.common_continueWatching,
          items: items,
          isContinue: true,
        ),
    ];
  }

  /// Takes the title off Continue watching by clearing its saved progress;
  /// [_undoRemove] puts the same record back.
  final Map<String, PlaybackProgress> _removed = <String, PlaybackProgress>{};

  Future<bool> _removeContinue(MediaItem item) async {
    final saved = await widget.progress.get(item.id);
    if (saved == null) return false;
    await widget.progress.clear(item.id);
    _removed[item.id] = saved;
    await _refreshLibrary();
    return true;
  }

  Future<bool> _undoRemove(MediaItem item) async {
    final saved = _removed.remove(item.id);
    if (saved == null) return false;
    await widget.progress.upsert(saved);
    await _refreshLibrary();
    return true;
  }

  Future<void> _refreshLibrary() async {
    final model = _loaded;
    if (!mounted || model == null) return;
    final library = await _libraryRows();
    if (!mounted || !identical(model, _loaded)) return;
    model.replaceRows([
      ...library.where((row) => row.isContinue),
      ...model.rows.where(
        (row) =>
            !row.isContinue && row.title != 'Liked' && row.title != 'Watched',
      ),
      ...library.where((row) => !row.isContinue),
    ]);
  }

  /// Home stays mounted under the pushed page; on return only the local
  /// Liked/Watched rows are re-read and swapped in, nothing is refetched.
  Future<void> _openItem(MediaItem item) async {
    await widget.onItemTap(context, item);
    final model = _loaded;
    if (!mounted || model == null) return;
    await _refreshLibrary();
  }

  Future<HomeRow> _row(
    String Function(AppStrings) title,
    MediaKind kind,
    String sort,
  ) async {
    final page = await widget.catalogue.browse(
      BrowseQuery(kind: kind, sort: sort, limit: 20),
    );
    return _rowOf(title, kind, page.items);
  }

  HomeRow _rowOf(
    String Function(AppStrings) title,
    MediaKind kind,
    List<MediaItem> items,
  ) => HomeRow(
    title: title(lookupAppStrings(const Locale('en'))),
    titleOf: title,
    items: items,
    query: TitleQuery(
      kind: kind == MediaKind.movie ? TitleKind.movie : TitleKind.tv,
      base: TitleBase.trending,
      sort: TitleSort.popularity,
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      ConnectionOutageBanner(controller: _outage, onRetry: _reload),
      Expanded(
        child: FutureBuilder<HomeViewModel>(
          future: _model,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingView(fullScreen: true);
            }
            if (snapshot.hasError) {
              return ErrorView(
                failure: switch (snapshot.error) {
                  final AppFailure failure => failure,
                  final error => UnexpectedFailure(
                    cause: error,
                    stack: snapshot.stackTrace,
                  ),
                },
                onRetry: () => _outage.retry(_reload),
                fullScreen: true,
              );
            }
            final home = HomeScreen(
              viewModel: snapshot.data!,
              onItemTap: _openItem,
              progress: _continueProgress,
              onRemove: _removeContinue,
              onUndoRemove: _undoRemove,
              onSeeAll: (row) => openTmdbGrid(
                context,
                catalogue: widget.catalogue,
                query: row.query!,
                title: row.titleIn(context),
                onItemTap: (item) => widget.onItemTap(context, item),
              ),
              logger: widget.logger,
            );
            final source = widget.catalogue;
            if (source is! FallbackTmdbCatalogue) return home;
            return Stack(
              children: [
                home,
                StreamBuilder<String>(
                  stream: source.changes,
                  builder: (context, _) => source.limited
                      ? Positioned(
                          top: 12,
                          left: 0,
                          right: 0,
                          child: IgnorePointer(
                            child: Center(
                              child: DecoratedBox(
                                key: const ValueKey('limited-mode-notice'),
                                decoration: BoxDecoration(
                                  color: const Color(0xCC000000),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    AppStrings.of(context).home_limitedMode,
                                    style: const TextStyle(
                                      color: Color(0xFFFFFFFF),
                                      fontSize: 13,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

/// Set by the composition: called when a movie's detail page opens and
/// when it closes (starts / stops loading every provider's sources).
({void Function(MediaItem movie) open, void Function(MediaItem movie) close})?
moviePageHooks;

/// Set by the composition: the plot in Persian for [details] (TMDB fa-IR,
/// MovieJavan, CCloud, then English). Used only when the app is in Farsi.
Future<String?> Function(TmdbDetails details)? persianPlotOf;

/// Loads TMDB details (+ seasons/episodes for a show) for [item] and pushes
/// the matching detail screen on [context]'s local Navigator. Movie -> Play
/// calls [onPlayMovie] with the enriched item; show -> Play (top action or
/// an episode row) calls [onPlayEpisode] with the enriched episode item and
/// the series' full episode list (what auto-play next walks).
Future<void> openTmdbDetail(
  BuildContext context, {
  required TmdbCatalogue catalogue,
  required MediaItem item,
  required void Function(BuildContext context, MediaItem movie) onPlayMovie,
  required void Function(
    BuildContext context,
    MediaItem episode,
    List<MediaItem> episodes,
  )
  onPlayEpisode,
  ProgressRepository? progress,
}) async {
  final navigator = Navigator.of(context);
  try {
    final farsi = Localizations.localeOf(context).languageCode == 'fa';
    final details = await catalogue.details(item);
    final plot = farsi ? await persianPlotOf?.call(details) : null;
    if (details.item.kind == MediaKind.movie) {
      moviePageHooks?.open(details.item);
      try {
        await pushAndRestoreFocus(
          navigator,
          AppPageRoute<void>(
            builder: (routeContext) => Material(
              child: MovieDetailScreen(
                presentation: _presentationOf(details, summary: plot),
                onPlay: () => onPlayMovie(routeContext, details.item),
                onCastTap: (member) => _openPerson(
                  routeContext,
                  catalogue,
                  member,
                  onPlayMovie,
                  onPlayEpisode,
                  progress,
                ),
                onLinkTap: (link) => _openFilter(
                  routeContext,
                  catalogue,
                  details,
                  link,
                  onPlayMovie,
                  onPlayEpisode,
                  progress,
                ),
              ),
            ),
          ),
        );
      } finally {
        moviePageHooks?.close(details.item);
      }
      return;
    }
    final seasons = await catalogue.seasons(details.item);
    final episodeLists = await Future.wait(
      seasons.map((season) => catalogue.episodes(details.item, season.number)),
    );
    final allEpisodes = episodeLists.expand((list) => list).toList();
    // Watched fraction of each episode, from the same store Continue
    // watching reads (keyed by the episode's media id).
    final fractions = <String, double>{
      if (progress != null)
        for (final episode in allEpisodes)
          if (await progress.get(episode.id) case final saved?)
            if (saved.duration > Duration.zero && !saved.completed)
              episode.id:
                  saved.position.inMilliseconds / saved.duration.inMilliseconds,
    };
    final viewModel = SeriesViewModel(
      seasons: <SeriesSeason>[
        for (var i = 0; i < seasons.length; i++)
          SeriesSeason(
            number: seasons[i].number,
            title: seasons[i].name,
            episodes: <SeriesEpisode>[
              for (final episode in episodeLists[i])
                _episodeOf(episode, fractions[episode.id]),
            ],
          ),
      ],
    );
    await pushAndRestoreFocus(
      navigator,
      AppPageRoute<void>(
        builder: (routeContext) => Material(
          child: SeriesDetailScreen(
            presentation: _presentationOf(details, summary: plot),
            onLinkTap: (link) => _openFilter(
              routeContext,
              catalogue,
              details,
              link,
              onPlayMovie,
              onPlayEpisode,
              progress,
            ),
            viewModel: viewModel,
            onCastTap: (member) => _openPerson(
              routeContext,
              catalogue,
              member,
              onPlayMovie,
              onPlayEpisode,
              progress,
            ),
            onPlay: (episode) {
              final match = allEpisodes.firstWhere(
                (item) =>
                    item.seasonNumber == episode.season &&
                    item.episodeNumber == episode.episode,
              );
              onPlayEpisode(routeContext, match, allEpisodes);
            },
          ),
        ),
      ),
    );
  } on AppFailure catch (failure) {
    if (!context.mounted) return;
    await showAppDialog<void>(
      context: context,
      builder: (_) => ErrorView(failure: failure),
    );
  }
}

MovieDetailPresentation _presentationOf(
  TmdbDetails details, {
  String? summary,
}) =>
    MovieDetailPresentation(
      item: details.item,
      poster: details.poster,
      year: details.item.year?.toString(),
      runtime: details.item.duration,
      imdbRating: details.ratings.imdb,
      rottenTomatoes: details.ratings.rottenTomatoes,
      tmdbRating: details.ratings.tmdb,
      genres: details.genres,
      links: [
        if (details.item.year case final year?)
          DetailLink(
            '$year',
            '$year',
            details.item.kind == MediaKind.movie
                ? 'primary_release_year'
                : 'first_air_date_year',
          ),
        for (final genre in details.genreIds)
          DetailLink(genre.name, '${genre.id}', 'with_genres'),
        for (final keyword in details.keywords)
          DetailLink(keyword.name, '${keyword.id}', 'with_keywords'),
        for (final country in details.countries)
          DetailLink(
            country.name == 'United States of America'
                ? 'United States'
                : country.name,
            country.code,
            'with_origin_country',
          ),
      ],
      cast: [
        for (final person in details.people)
          CastMember(
            name: person.name,
            role: person.role,
            id: person.id,
            isCrew: person.isCrew,
            photo: person.profilePath == null
                ? null
                : Uri.parse(
                    'https://image.tmdb.org/t/p/w185${person.profilePath}',
                  ),
          ),
      ],
      tagline: details.tagline,
      summary: summary ?? details.overview,
    );

SeriesEpisode _episodeOf(MediaItem episode, double? progress) => SeriesEpisode(
  season: episode.seasonNumber!,
  episode: episode.episodeNumber!,
  title: episode.subtitle ?? episode.title,
  duration: episode.duration ?? Duration.zero,
  description: '',
  still: episode.artwork,
  progress: progress,
);

Future<void> _openFilter(
  BuildContext context,
  TmdbCatalogue catalogue,
  TmdbDetails details,
  DetailLink link,
  void Function(BuildContext, MediaItem) onPlayMovie,
  void Function(BuildContext, MediaItem, List<MediaItem>) onPlayEpisode,
  ProgressRepository? progress,
) {
  final year = link.isYear ? int.parse(link.value) : null;
  return openTmdbGrid(
    context,
    catalogue: catalogue,
    title: link.label,
    query: TitleQuery(
      kind: details.item.kind == MediaKind.movie
          ? TitleKind.movie
          : TitleKind.tv,
      genreIds: link.filter == 'with_genres'
          ? [int.parse(link.value)]
          : const [],
      keywordIds: link.filter == 'with_keywords'
          ? [int.parse(link.value)]
          : const [],
      countryCode: link.isCountry ? link.value : null,
      yearFrom: year,
      yearTo: year,
    ),
    onItemTap: (item) => openTmdbDetail(
      context,
      catalogue: catalogue,
      item: item,
      onPlayMovie: onPlayMovie,
      onPlayEpisode: onPlayEpisode,
      progress: progress,
    ),
  );
}

/// Pushes a person's page (portrait, movies and shows they appear in).
Future<void> _openPerson(
  BuildContext context,
  TmdbCatalogue catalogue,
  CastMember member,
  void Function(BuildContext, MediaItem) onPlayMovie,
  void Function(BuildContext, MediaItem, List<MediaItem>) onPlayEpisode,
  ProgressRepository? progress,
) => pushAndRestoreFocus(
  Navigator.of(context),
  AppPageRoute<void>(
    builder: (pageContext) => PopOnEscape(
      child: Stack(
        children: [
          _CatalogueOptionsView(
            catalogue: catalogue,
            person: member,
            builder: (options, _) => PersonDetailScreen(
              person: member,
              memory: FocusMemory(),
              initialKind: options.kind,
              source: (query, page) =>
                  loadTmdbTitlePage(catalogue, query, page),
              genresByKind: options.genres,
              countries: options.countries,
              onTitleTap: (item) => openTmdbDetail(
                pageContext,
                catalogue: catalogue,
                item: item,
                onPlayMovie: onPlayMovie,
                onPlayEpisode: onPlayEpisode,
                progress: progress,
              ),
            ),
          ),
          const Positioned(top: 0, left: 0, child: PageBackButton()),
        ],
      ),
    ),
  ),
);

Future<void> openTmdbGrid(
  BuildContext context, {
  required TmdbCatalogue catalogue,
  required TitleQuery query,
  required String title,
  required ValueChanged<MediaItem> onItemTap,
}) => pushAndRestoreFocus(
  Navigator.of(context),
  AppPageRoute<void>(
    builder: (_) => PopOnEscape(
      child: _CatalogueOptionsView(
        catalogue: catalogue,
        builder: (options, _) => PagedTitleGrid(
          source: (query, page) => loadTmdbTitlePage(catalogue, query, page),
          initialQuery: query,
          title: title,
          genres: options.genres[query.kind]!,
          countries: options.countries,
          onItemTap: onItemTap,
        ),
      ),
    ),
  ),
);

/// Menu order: Home, Movies, TV shows, Genres, Liked, Search.
List<AppDestination> tmdbDestinations({
  required TmdbCatalogue catalogue,
  required FavouritesRepository favourites,
  required ProgressRepository progress,
  required FutureOr<void> Function(BuildContext context, MediaItem item)
  onItemTap,
  Listenable? libraryChanged,
  AppLogger? logger,
  Future<File>? snapshot,
}) => [
  AppDestination(
    id: 'home',
    label: lookupAppStrings(const Locale('en')).common_home,
    labelOf: (s) => s.common_home,
    icon: PhosphorIconsRegular.house,
    activeIcon: PhosphorIconsFill.house,
    builder: (_) => TmdbHomeView(
      catalogue: catalogue,
      favourites: favourites,
      progress: progress,
      libraryChanged: libraryChanged,
      onItemTap: onItemTap,
      logger: logger,
      snapshot: snapshot,
    ),
  ),
  for (final (id, label, icon, activeIcon, kind) in [
    (
      'movies',
      (AppStrings s) => s.common_movies,
      PhosphorIconsRegular.filmSlate,
      PhosphorIconsFill.filmSlate,
      TitleKind.movie,
    ),
    (
      'tv',
      (AppStrings s) => s.common_tvShows,
      PhosphorIconsRegular.television,
      PhosphorIconsFill.television,
      TitleKind.tv,
    ),
  ])
    AppDestination(
      id: id,
      label: label(lookupAppStrings(const Locale('en'))),
      labelOf: label,
      icon: icon,
      activeIcon: activeIcon,
      builder: (context) => TmdbKindView(
        catalogue: catalogue,
        kind: kind,
        title: label(AppStrings.of(context)),
        onItemTap: (item) => onItemTap(context, item),
      ),
    ),
  AppDestination(
    id: 'genres',
    label: lookupAppStrings(const Locale('en')).common_genres,
    labelOf: (s) => s.common_genres,
    icon: PhosphorIconsRegular.squaresFour,
    activeIcon: PhosphorIconsFill.squaresFour,
    iconWidget: const GenresIcon(),
    builder: (_) => TmdbGenresView(catalogue: catalogue, onItemTap: onItemTap),
  ),
  AppDestination(
    id: 'liked',
    label: lookupAppStrings(const Locale('en')).common_liked,
    labelOf: (s) => s.common_liked,
    icon: PhosphorIconsRegular.heart,
    activeIcon: PhosphorIconsFill.heart,
    builder: (context) => TmdbLikedView(
      catalogue: catalogue,
      favourites: favourites,
      onItemTap: (item) => onItemTap(context, item),
      logger: logger,
    ),
  ),
  AppDestination(
    id: 'search',
    label: lookupAppStrings(const Locale('en')).common_search,
    labelOf: (s) => s.common_search,
    icon: PhosphorIconsRegular.magnifyingGlass,
    activeIcon: PhosphorIconsFill.magnifyingGlass,
    builder: (context) => TmdbSearchView(
      catalogue: catalogue,
      onItemTap: (item) => onItemTap(context, item),
    ),
  ),
];

/// Movies / TV shows sidebar pages: the shared grid for one kind, no app bar.
class TmdbKindView extends StatelessWidget {
  const TmdbKindView({
    required this.catalogue,
    required this.kind,
    required this.title,
    required this.onItemTap,
    super.key,
  });
  final TmdbCatalogue catalogue;
  final TitleKind kind;
  final String title;
  final ValueChanged<MediaItem> onItemTap;
  @override
  Widget build(BuildContext context) => _CatalogueOptionsView(
    catalogue: catalogue,
    builder: (options, _) => PagedTitleGrid(
      source: (query, page) => loadTmdbTitlePage(catalogue, query, page),
      initialQuery: TitleQuery(kind: kind),
      title: title,
      genres: options.genres[kind]!,
      countries: options.countries,
      onItemTap: onItemTap,
      autofocus: false,
    ),
  );
}

/// Genres sidebar page; a genre tile opens the shared grid with that genre
/// preselected.
class TmdbGenresView extends StatelessWidget {
  const TmdbGenresView({
    required this.catalogue,
    required this.onItemTap,
    super.key,
  });
  final TmdbCatalogue catalogue;
  final void Function(BuildContext context, MediaItem item) onItemTap;
  @override
  Widget build(BuildContext context) => _CatalogueOptionsView(
    catalogue: catalogue,
    builder: (options, reload) => GenresPage(
      genresByKind: options.genres,
      onRefresh: reload,
      onSeeAll: (query, title) => openTmdbGrid(
        context,
        catalogue: catalogue,
        query: query,
        title: title,
        onItemTap: (item) => onItemTap(context, item),
      ),
    ),
  );
}

/// Liked sidebar page: the favourites as the shared title grid, refreshed
/// whenever a title is liked or unliked.
class TmdbLikedView extends StatefulWidget {
  const TmdbLikedView({
    required this.catalogue,
    required this.favourites,
    required this.onItemTap,
    this.logger,
    super.key,
  });
  final TmdbCatalogue catalogue;
  final FavouritesRepository favourites;
  final ValueChanged<MediaItem> onItemTap;
  final AppLogger? logger;
  @override
  State<TmdbLikedView> createState() => _TmdbLikedViewState();
}

class _TmdbLikedViewState extends State<TmdbLikedView> {
  final _titles = <String, MediaItem>{};
  StreamSubscription<List<String>>? _subscription;
  List<String>? _ids;

  @override
  void initState() {
    super.initState();
    _subscription = widget.favourites.watchAll().listen((ids) {
      if (mounted) setState(() => _ids = ids);
    });
    widget.favourites.all().then((ids) {
      if (mounted && _ids == null) setState(() => _ids = ids);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<TitlePage> _page(List<String> ids) async {
    final missing = ids.where((id) => !_titles.containsKey(id)).toList();
    for (final item in await loadTmdbTitles(
      widget.catalogue,
      missing,
      logger: widget.logger,
    )) {
      _titles[item.id] = item;
    }
    return TitlePage(
      items: [for (final id in ids) ?_titles[id]],
      nextPage: null,
      metadata: const {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final ids = _ids;
    if (ids == null) return const LoadingView(fullScreen: true);
    return PagedTitleGrid(
      key: ValueKey(ids.join(',')),
      source: (_, _) => _page(ids),
      initialQuery: TitleQuery(kind: TitleKind.movie),
      title: AppStrings.of(context).common_liked,
      showFilters: false,
      empty: EmptyView(
        key: const ValueKey('title-grid-empty'),
        icon: PhosphorIconsRegular.heart,
        headline: AppStrings.of(context).liked_emptyTitle,
        body: AppStrings.of(context).liked_emptyBody,
        primaryLabel: AppStrings.of(context).liked_browseMovies,
        onPrimary: () => AppShellScope.selectOf(context)?.call('movies'),
      ),
      onItemTap: widget.onItemTap,
      autofocus: false,
    );
  }
}

class TmdbSearchView extends StatelessWidget {
  const TmdbSearchView({
    required this.catalogue,
    required this.onItemTap,
    super.key,
  });
  final TmdbCatalogue catalogue;
  final ValueChanged<MediaItem> onItemTap;
  @override
  Widget build(BuildContext context) => _CatalogueOptionsView(
    catalogue: catalogue,
    builder: (options, _) => SearchScreen(
      source: (query, page) => loadTmdbTitlePage(catalogue, query, page),
      genresByKind: options.genres,
      countries: options.countries,
      onItemTap: onItemTap,
    ),
  );
}

typedef _CatalogueOptions = ({
  TitleKind kind,
  Map<TitleKind, List<TitleFilterOption<int>>> genres,
  List<TitleFilterOption<String>> countries,
});

class _CatalogueOptionsView extends StatefulWidget {
  const _CatalogueOptionsView({
    required this.catalogue,
    required this.builder,
    this.person,
  });
  final TmdbCatalogue catalogue;
  final CastMember? person;
  final Widget Function(_CatalogueOptions options, Future<void> Function() reload)
  builder;
  @override
  State<_CatalogueOptionsView> createState() => _CatalogueOptionsViewState();
}

class _CatalogueOptionsViewState extends State<_CatalogueOptionsView> {
  late Future<_CatalogueOptions> _options = _load();

  /// Pull-to-refresh: the old options stay on screen until the new ones are
  /// in; a failure is shown by the page's own error view (the awaited future).
  Future<void> _reload() async {
    final next = _load();
    try {
      await next;
    } on Object {
      // Shown by the FutureBuilder below once [next] is the current future.
    }
    if (mounted) setState(() => _options = next);
  }

  Future<_CatalogueOptions> _load() async {
    final client = widget.catalogue.client;
    final genres = await Future.wait([
      client.genres(isTv: false),
      client.genres(isTv: true),
    ]);
    final countries = await client.countries();
    final person = widget.person;
    final counts = person == null
        ? null
        : await client.personCreditCounts(person.id!, crew: person.isCrew);
    return (
      kind: counts != null && counts.tv > counts.movies
          ? TitleKind.tv
          : TitleKind.movie,
      genres: {
        for (final kind in TitleKind.values)
          kind: [
            for (final genre in genres[kind.index])
              TitleFilterOption(genre.id, genre.name),
          ],
      },
      countries: [
        for (final country in countries)
          TitleFilterOption(country.code, country.name),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: FutureBuilder<_CatalogueOptions>(
      future: _options,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(
            failure: snapshot.error is AppFailure
                ? snapshot.error! as AppFailure
                : UnexpectedFailure(
                    cause: snapshot.error,
                    stack: snapshot.stackTrace,
                  ),
            onRetry: () => setState(() => _options = _load()),
            fullScreen: true,
          );
        }
        if (!snapshot.hasData) return const LoadingView(fullScreen: true);
        return widget.builder(snapshot.data!, _reload);
      },
    ),
  );
}

/// Announces that playback saved a position (see [TmdbHomeView.libraryChanged]).
final class LibraryChanges extends ChangeNotifier {
  void announce() => notifyListeners();
}
