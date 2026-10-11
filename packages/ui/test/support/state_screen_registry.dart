import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

enum ScreenFixtureState { loading, empty, error, content }

/// Explicit public API manifest: adding an exported screen requires a fixture.
const publicScreenExportPaths = <String, String>{
  'HomeScreen': 'src/browse/home_screen.dart',
  'LibraryScreen': 'src/browse/library_screen.dart',
  'SearchScreen': 'src/search/search_screen.dart',
  'MovieDetailScreen': 'src/detail/movie_detail_screen.dart',
  'SeriesDetailScreen': 'src/detail/series_detail_screen.dart',
  'PersonDetailScreen': 'src/detail/person_detail.dart',
  'PlaySourceScreen': 'src/play_flow/play_source_screen.dart',
  'PlayerScreen': 'src/player/player_screen.dart',
  'PreviewPlayerScreen': 'src/player/player_screen.dart',
  'StreamOpeningScreen': 'src/player/stream_opening.dart',
  'SettingsScreen': 'src/settings/settings_screen.dart',
  'DiagnosticsScreen': 'src/settings/diagnostics_screen.dart',
  'ProvidersScreen': 'src/settings/providers_screen.dart',
};

class BuiltScreenFixture {
  BuiltScreenFixture(this.widget, {this.cleanup});

  final Widget widget;
  final FutureOr<void> Function()? cleanup;

  /// Unmount the widget before calling this, as with any borrowed view model.
  Future<void> dispose() async => cleanup?.call();
}

class PublicScreenFixture {
  const PublicScreenFixture(this.name, this.build);

  final String name;
  final Future<BuiltScreenFixture> Function(ScreenFixtureState state) build;
  String get exportPath => publicScreenExportPaths[name]!;
}

final publicScreenFixtures = <PublicScreenFixture>[
  PublicScreenFixture('HomeScreen', _home),
  PublicScreenFixture('LibraryScreen', _library),
  PublicScreenFixture('SearchScreen', _search),
  PublicScreenFixture('MovieDetailScreen', _movie),
  PublicScreenFixture('SeriesDetailScreen', _series),
  PublicScreenFixture('PersonDetailScreen', _person),
  PublicScreenFixture('PlaySourceScreen', _sources),
  PublicScreenFixture('PlayerScreen', _player),
  PublicScreenFixture('PreviewPlayerScreen', _preview),
  PublicScreenFixture('StreamOpeningScreen', _opening),
  PublicScreenFixture('SettingsScreen', _settings),
  PublicScreenFixture('DiagnosticsScreen', _diagnostics),
  PublicScreenFixture('ProvidersScreen', _providers),
];

/// Titles of the browse grids (Movies, Search results) in the goldens.
const _gridTitles = <String>[
  'The Last Harbor',
  'Midnight Run',
  'Paper Moons',
  'Salt and Iron',
  'A Quiet Departure',
  'Northern Lights',
  'The Long Way Home',
  'Glass Houses',
  'Blue Hour',
  'Under the Bridge',
  'The Ferry Master',
  'Static',
  'Winter Orchard',
  'Open Water',
  'The Cartographer',
  'Low Tide',
  'Red Line',
  'Fifty Fathoms',
  'The Night Shift',
  'Dust and Honey',
  'Harbor Lights',
  'Second Spring',
  'The Understudy',
  'Lanterns',
];

/// A page of titles for the browse grids. [worstCase] swaps in what real data
/// does: 90-character titles, a Persian title, a one-letter title, missing
/// posters and no year.
List<MediaItem> browseGridItems({int count = 24, bool worstCase = false}) => [
  for (var i = 0; i < count; i++)
    MediaItem(
      id: 'browse-$i',
      title: worstCase
          ? switch (i % 4) {
              0 =>
                'The Extraordinarily Long and Winding Story of a Harbor Town '
                    'and the People Who Never Left It',
              1 => 'ماتریکس',
              2 => 'M',
              _ => _gridTitles[i % _gridTitles.length],
            }
          : _gridTitles[i % _gridTitles.length],
      kind: MediaKind.movie,
      year: worstCase && i % 3 == 2 ? null : 2000 + (i * 7) % 25,
      artwork: worstCase && i % 3 != 0
          ? null
          : Uri.parse('https://example.invalid/browse/$i.jpg?ar=port'),
    ),
];

/// Genres and countries the Movies chip bar is shown with in the goldens.
const browseGenres = <TitleFilterOption<int>>[
  TitleFilterOption(28, 'Action'),
  TitleFilterOption(18, 'Drama'),
  TitleFilterOption(35, 'Comedy'),
  TitleFilterOption(878, 'Science Fiction'),
  TitleFilterOption(53, 'Thriller'),
];
const browseCountries = <TitleFilterOption<String>>[
  TitleFilterOption('US', 'United States'),
  TitleFilterOption('IR', 'Iran'),
];

const _failure = UnexpectedFailure(cause: 'Accessibility fixture failure');

/// These presentation-only screens receive data synchronously. Their host owns
/// loading/empty/error, so audit the shared host state view and actual content,
/// rather than inventing unsupported state flags on the content screen.
Widget _hostState(ScreenFixtureState state, Widget content) => switch (state) {
  ScreenFixtureState.loading => const LoadingView(fullScreen: true),
  ScreenFixtureState.empty => const EmptyView(
    headline: 'No content available',
    body: 'Choose another title or try again later.',
    fullScreen: true,
  ),
  ScreenFixtureState.error => ErrorView(
    failure: _failure,
    onRetry: () {},
    fullScreen: true,
  ),
  ScreenFixtureState.content => content,
};

Future<BuiltScreenFixture> _home(ScreenFixtureState state) async {
  final model = HomeViewModel(
    rows: state == ScreenFixtureState.empty ? [] : fixtureHomeRows(),
    loadState: HomeLoadState.values.byName(state.name),
    failure: state == ScreenFixtureState.error ? _failure : null,
    firstDeferredSectionReady: true,
    secondDeferredSectionReady: true,
  );
  return BuiltScreenFixture(
    HomeScreen(
      viewModel: model,
      progress: <String, PlaybackProgress>{
        for (final (id, fraction) in <(String, double)>[
          ('fixture-0-0', .35),
          ('fixture-0-1', .7),
          ('fixture-0-2', .15),
          ('fixture-1-1', .5),
        ])
          id: PlaybackProgress(
            mediaId: id,
            position: Duration(minutes: (100 * fraction).round()),
            duration: const Duration(minutes: 100),
            updatedAt: DateTime.utc(2026, 10, 9),
            completed: false,
          ),
      },
      onItemTap: (_) {},
      onRetry: () {},
    ),
    cleanup: model.dispose,
  );
}

Future<BuiltScreenFixture> _library(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      // LibraryScreen owns its empty-library presentation.
      state == ScreenFixtureState.empty
          ? const LibraryScreen(items: [], scope: BrowseScope.movies)
          : _hostState(
              state,
              LibraryScreen(
                items: browseGridItems(),
                scope: BrowseScope.movies,
                genres: browseGenres,
                countries: browseCountries,
                onItemTap: (_) {},
              ),
            ),
    );

Future<BuiltScreenFixture> _search(ScreenFixtureState state) async {
  final pending = Completer<List<MediaItem>>();
  final model = LibrarySearchController(
    search: (_) async => switch (state) {
      ScreenFixtureState.loading => pending.future,
      ScreenFixtureState.empty => <MediaItem>[],
      ScreenFixtureState.error => throw _failure,
      ScreenFixtureState.content => browseGridItems(count: 12),
    },
  );
  // Immediate request avoids real clocks and debounce timers in the matrix.
  model.activateRecent('fixture');
  await Future<void>.value();
  await Future<void>.value();
  return BuiltScreenFixture(
    SearchScreen(search: model.search, controller: model, onItemTap: (_) {}),
    cleanup: () {
      // Invalidate the pending request before it finishes, then dispose.
      model.updateQuery('');
      model.dispose();
      if (!pending.isCompleted) pending.complete([]);
    },
  );
}

/// The movie detail the goldens show. [resume] adds a resume point; [worstCase]
/// is what real data does: a 120 character title, no backdrop, no poster, no
/// people, no rating, a Persian overview.
MovieDetailPresentation moviePresentation({
  bool resume = false,
  bool worstCase = false,
}) {
  final related = browseGridItems(count: 8);
  return MovieDetailPresentation(
    item: MediaItem(
      id: 'movie-detail',
      title: worstCase
          ? 'The Extraordinarily Long and Winding Story of a Harbor Town and '
                'the People Who Never Left It, Complete Director\'s Cut'
          : 'The Last Harbor',
      kind: MediaKind.movie,
      artwork: worstCase
          ? null
          : Uri.parse('https://example.invalid/movie/last-harbor.jpg?ar=land'),
    ),
    poster: worstCase
        ? null
        : Uri.parse('https://example.invalid/movie/last-harbor.jpg?ar=port'),
    year: worstCase ? null : '2024',
    runtimeLabel: worstCase ? null : '1h 52m',
    imdbRating: worstCase ? null : '7.8',
    rottenTomatoes: worstCase ? null : '91%',
    contentRating: worstCase ? null : 'PG-13',
    genres: worstCase ? const <String>[] : const <String>['Drama', 'Mystery'],
    links: worstCase
        ? const <DetailLink>[]
        : const <DetailLink>[
            DetailLink('2024', '2024', 'primary_release_year'),
            DetailLink('United States', 'US', 'with_origin_country'),
            DetailLink('Drama', '18', 'with_genres'),
            DetailLink('Mystery', '9648', 'with_genres'),
            DetailLink('Harbor', '1', 'with_keywords'),
          ],
    summary: worstCase
        ? 'در یک شهر بندری کوچک، مأموری بازنشسته پس از ده سال به محلهٔ قدیمی '
              'خود بازمی‌گردد و با رازی روبه‌رو می‌شود که همهٔ اهالی سال‌ها '
              'پنهانش کرده‌اند. هر شب مه از دریا بالا می‌آید و گذشته را با '
              'خود می‌آورد.'
        : 'A retired harbor master returns to the town he left a decade ago '
              'and finds the one secret everyone has spent years keeping from '
              'him. Each night the fog comes in with the tide and brings the '
              'past with it.',
    qualityBadges: worstCase ? const <String>[] : const <String>['4K', 'HDR10'],
    progress: resume
        ? PlaybackProgress(
            mediaId: 'movie-detail',
            position: const Duration(minutes: 12, seconds: 34),
            duration: const Duration(minutes: 112),
            updatedAt: DateTime.utc(2026, 10, 9),
            completed: false,
          )
        : null,
    trailers: worstCase
        ? const <MediaItem>[]
        : <MediaItem>[
            MediaItem(
              id: 'trailer-1',
              title: 'Official trailer',
              kind: MediaKind.other,
              artwork: Uri.parse(
                'https://example.invalid/movie/trailer.jpg?ar=land',
              ),
            ),
          ],
    cast: worstCase
        ? const <CastMember>[]
        : <CastMember>[fixtureLead('Director'), ...fixtureCastMembers()],
    related: worstCase ? const <MediaItem>[] : related,
  );
}

Future<BuiltScreenFixture> _movie(
  ScreenFixtureState state, {
  bool resume = false,
  bool worstCase = false,
}) async => BuiltScreenFixture(
  _hostState(
    state,
    FavouritesScope(
      repository: FakeFavouritesRepository(),
      child: MovieDetailScreen(
        presentation: moviePresentation(resume: resume, worstCase: worstCase),
        onPlay: () {},
        onRelatedTap: (_) {},
        onTrailerTap: (_) {},
        onLinkTap: (_) {},
        onCastTap: (_) {},
      ),
    ),
  ),
);

/// Movie detail with a resume point ("Resume 12:34").
Future<BuiltScreenFixture> movieResumeFixture() =>
    _movie(ScreenFixtureState.content, resume: true);

/// Movie detail with the break-ui worst-case data.
Future<BuiltScreenFixture> movieWorstCaseFixture() =>
    _movie(ScreenFixtureState.content, worstCase: true);

Future<BuiltScreenFixture> _series(ScreenFixtureState state) async {
  final model = SeriesViewModel(seasons: fixtureSeriesSeasons());
  return BuiltScreenFixture(
    _hostState(
      state,
      SeriesDetailScreen(
        presentation: fixtureSeriesPresentation(),
        viewModel: model,
        onPlay: (_) {},
      ),
    ),
    cleanup: model.dispose,
  );
}

Future<BuiltScreenFixture> _person(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      _hostState(
        state,
        PersonDetailScreen(
          person: CastMember(
            id: 7,
            name: 'Mara Voss',
            role: 'Actor',
            photo: Uri.parse(
              'https://example.invalid/person/mara-voss.jpg?ar=port',
            ),
          ),
          memory: FocusMemory(),
          source: (_, _) async => TitlePage(items: browseGridItems(count: 12)),
          onTitleTap: (_) {},
        ),
      ),
    );

/// The director/creator card the detail pages lead their Cast row with.
CastMember fixtureLead(String role) => CastMember(
  id: 100,
  name: 'Ines Halvorsen',
  role: role,
  isCrew: true,
  photo: Uri.parse('https://example.invalid/person/idris-calder.jpg?ar=port'),
);

/// Streams of the source-picker goldens: a 4K HDR torrent with seeders and a
/// size, a 1080p file with captions, and a plain 720p link.
List<SourceSpec> sourceFixtureStreams() => <SourceSpec>[
  SourceSpec(
    kind: SourceKind.torrentMagnet,
    uri: Uri.parse('magnet:?xt=urn:btih:0123456789abcdef'),
    expectedBytes: 18 * 1024 * 1024 * 1024,
    label:
        'The.Last.Harbor.2024.2160p.UHD.BluRay.HDR.x265-NOMAD\n'
        'Seeders: 214\nRelease group: NOMAD',
  ),
  SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse(
      'https://example.invalid/The.Last.Harbor.2024.1080p.WEB-DL.mkv',
    ),
    expectedBytes: 4 * 1024 * 1024 * 1024,
    quality: '1080p',
    label: 'Softsub',
  ),
  SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse(
      'https://example.invalid/The.Last.Harbor.2024.720p.WEB-DL.mp4',
    ),
    expectedBytes: 1400 * 1024 * 1024,
    quality: '720p',
  ),
];

Future<BuiltScreenFixture> _sources(
  ScreenFixtureState state,
) async => BuiltScreenFixture(
  Builder(
    builder: (context) => PlaySourceScreen(
      title: 'The Last Harbor',
      subtitle: '2024',
      backdropArtwork: 'https://example.invalid/movie/last-harbor.jpg?ar=land',
      providers: [
        const UiProviderOption(
          id: 'fixture',
          name: 'Fixture provider',
          state: UiProviderState.ready,
        ),
        UiProviderOption(
          id: 'slow',
          name: 'Second provider',
          state: UiProviderState.loading,
        ),
        UiProviderOption(
          id: 'down',
          name: 'Third provider',
          state: UiProviderState.failed,
          message: AppStrings.of(context).play_providerUnavailable,
        ),
      ],
      selectedProviderId: 'fixture',
      streams: switch (state) {
        ScreenFixtureState.loading => const UiStreamListLoading(),
        ScreenFixtureState.empty => const UiStreamListReady([]),
        ScreenFixtureState.error => UiStreamListFailed(
          AppStrings.of(context).play_providerUnavailable,
        ),
        ScreenFixtureState.content => UiStreamListReady(sourceFixtureStreams()),
      },
      onProviderSelected: (_) {},
      onStreamSelected: (_) {},
      onBack: () {},
      onInsertLink: () {},
      onRetry: () {},
    ),
  ),
);

/// The source picker while sources are being found.
Future<BuiltScreenFixture> sourcesLoadingFixture() =>
    _sources(ScreenFixtureState.loading);

/// The source picker after the provider failed.
Future<BuiltScreenFixture> sourcesFailedFixture() =>
    _sources(ScreenFixtureState.error);

Future<BuiltScreenFixture> _player(ScreenFixtureState state) async {
  final controller = FakePlaybackController();
  if (state == ScreenFixtureState.content) {
    controller.setDuration(const Duration(minutes: 2));
    controller.advanceTo(const Duration(seconds: 20));
  } else if (state == ScreenFixtureState.error) {
    controller.failWith(
      const PlaybackFailure.sourceUnreachable(cause: 'fixture'),
    );
  }
  final player = PlayerScreen(
    title: 'Fixture player',
    controller: controller,
    videoSurface: const FakeVideoSurface(),
    setSystemUiMode: (_) async {},
    onExit: () {},
    onRetry: () {},
  );
  return BuiltScreenFixture(
    // No-source empty presentation belongs to the host; initial engine state
    // is the real PlayerScreen loading state, not a fake empty player state.
    state == ScreenFixtureState.empty ? _hostState(state, player) : player,
    cleanup: controller.dispose,
  );
}

Future<BuiltScreenFixture> _opening(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      StreamOpeningScreen(
        title: 'The Last Harbor',
        artwork: Uri.parse(
          'https://example.invalid/movie/last-harbor.jpg?ar=land',
        ),
        kind: MediaKind.movie,
        status: state == ScreenFixtureState.content
            ? const StreamOpeningStatus(label: 'Buffering 42%', progress: 0.42)
            : const StreamOpeningStatus(label: 'Connecting…'),
        failure: state == ScreenFixtureState.error
            ? const PlaybackFailure.sourceUnreachable(cause: 'fixture')
            : null,
        onRetry: () {},
        onBack: () {},
      ),
    );

Future<BuiltScreenFixture> _preview(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      _hostState(state, const PreviewPlayerScreen(mediaId: 'fixture-preview')),
    );

CapabilityReport _report() => CapabilityReport(
  hardwareDecode: true,
  decoders: const ['h264'],
  hdrOutput: false,
  hdrFormats: const [],
  displayModeSwitching: false,
  audioPassthrough: false,
  passthroughFormats: const [],
  diagnostics: const {'fixture': 'local deterministic report'},
);

Future<BuiltScreenFixture> _settings(ScreenFixtureState state) async {
  return BuiltScreenFixture(
    _hostState(
      state,
      SettingsScreen(
        settings: AppSettings(MemorySettingsStore()),
        capabilities: _report(),
        providersPage: (_) => ProvidersScreen(
          load: () async => const [
            UiProviderAccount(id: 'ccloud', name: 'CCloud'),
          ],
          onCredentials: (_, _, _) async =>
              'Sign-in is not available in the app yet',
          onStartQr: (_) async =>
              UiQrLogin(code: 'fixture', url: Uri.parse('https://example.com')),
          onPollQr: (_, _) async => false,
          onLogout: (_) async {},
          onBuy: (_) async {},
        ),
        available: const <SettingCapability>{},
      ),
    ),
  );
}

Future<BuiltScreenFixture> _providers(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      _hostState(
        state,
        ProvidersScreen(
          load: () async => const [
            UiProviderAccount(id: 'free', name: 'Free provider'),
            UiProviderAccount(
              id: 'ccloud',
              name: 'CCloud',
              login: UiProviderLogin.credentials,
            ),
          ],
          onCredentials: (_, _, _) async => null,
          onStartQr: (_) async =>
              UiQrLogin(code: 'fixture', url: Uri.parse('https://example.com')),
          onPollQr: (_, _) async => false,
          onLogout: (_) async {},
          onBuy: (_) async {},
        ),
      ),
    );

Future<BuiltScreenFixture> _diagnostics(ScreenFixtureState state) async =>
    BuiltScreenFixture(
      _hostState(
        state,
        DiagnosticsScreen(report: _report(), copyText: (_) async {}),
      ),
    );

/// The 11 screens of the Part 06 golden matrix (DESIGN_SPEC §12), content
/// state only, keyed by the matrix file-name id.
final p06MatrixFixtures = <String, Future<BuiltScreenFixture> Function()>{
  'home': () => _home(ScreenFixtureState.content),
  'movies': () => _library(ScreenFixtureState.content),
  'genres': _genresPage,
  'search': () => _search(ScreenFixtureState.content),
  'movie_detail': () => _movie(ScreenFixtureState.content),
  'person_detail': () => _person(ScreenFixtureState.content),
  'series_detail': () => _series(ScreenFixtureState.content),
  'settings_root': () => _settings(ScreenFixtureState.content),
  'settings_audio': _settingsAudio,
  'player': () => _player(ScreenFixtureState.content),
  'play_source': () => _sources(ScreenFixtureState.content),
  'play_link': _playLink,
};

Future<BuiltScreenFixture> _genresPage() async => BuiltScreenFixture(
  GenresPage(
    genresByKind: <TitleKind, List<TitleFilterOption<int>>>{
      TitleKind.movie: <TitleFilterOption<int>>[
        for (var i = 1; i <= 6; i++) TitleFilterOption(i, 'Movie genre $i'),
      ],
      TitleKind.tv: <TitleFilterOption<int>>[
        for (var i = 101; i <= 103; i++) TitleFilterOption(i, 'TV genre $i'),
      ],
    },
    onSeeAll: (_, _) {},
  ),
);

Future<BuiltScreenFixture> _settingsAudio() async => BuiltScreenFixture(
  SettingsScreen(
    settings: AppSettings(MemorySettingsStore()),
    capabilities: _report(),
    available: const <SettingCapability>{},
    section: SettingSection.audio,
  ),
);

Future<BuiltScreenFixture> _playLink() async => BuiltScreenFixture(
  PlayLinkPage(
    recents: RecentLinks(MemorySettingsStore()),
    onPlay: (_) async => null,
    pickTorrent: () async => null,
  ),
);

/// Home rows for the desktop keywalk (`test/focus/p06_desktop_keywalk_test`):
/// Continue watching 3 cards, Trending movies 8, Trending shows 8, every row
/// with a query so each shows its "See all" end card.
List<HomeRow> keywalkHomeRows() {
  MediaItem item(String id, String title, {bool land = false}) => MediaItem(
    id: id,
    title: title,
    kind: MediaKind.movie,
    artwork: Uri.parse(
      'https://example.invalid/$id.jpg?ar=${land ? 'land' : 'port'}',
    ),
  );
  final query = TitleQuery(kind: TitleKind.movie);
  return <HomeRow>[
    HomeRow(
      title: 'Continue watching',
      query: query,
      items: <MediaItem>[
        for (var i = 0; i < 3; i++) item('cw-$i', 'Continue $i', land: true),
      ],
    ),
    HomeRow(
      title: 'Trending movies',
      query: query,
      items: <MediaItem>[for (var i = 0; i < 8; i++) item('tm-$i', 'Movie $i')],
    ),
    HomeRow(
      title: 'Trending shows',
      query: query,
      items: <MediaItem>[for (var i = 0; i < 8; i++) item('ts-$i', 'Show $i')],
    ),
  ];
}

/// A deterministic capability report for the Settings walk.
CapabilityReport keywalkCapabilityReport() => _report();

/// The movie detail the keywalks open: a trailer, three people with a page,
/// four "More like this" titles.
MovieDetailPresentation keywalkMoviePresentation(MediaItem item) =>
    MovieDetailPresentation(
      item: item,
      year: '2024',
      summary: 'A journey through a changing world.',
      trailers: <MediaItem>[
        MediaItem(
          id: 'trailer-0',
          title: 'Trailer',
          kind: MediaKind.other,
          artwork: Uri.parse('https://example.invalid/trailer-0.jpg?ar=land'),
        ),
      ],
      cast: <CastMember>[
        fixtureLead('Creator'),
        ...fixtureCastMembers().take(3),
      ],
      related: <MediaItem>[
        for (var i = 0; i < 4; i++)
          MediaItem(
            id: 'rel-$i',
            title: 'Related $i',
            kind: MediaKind.movie,
            artwork: Uri.parse('https://example.invalid/rel-$i.jpg?ar=port'),
          ),
      ],
    );

/// Content supplied by the fixtures, never application interface copy.
final fixtureContentStrings = <String>{
  ..._gridTitles,
  for (final row in fixtureHomeRows()) ...[
    row.title,
    for (final item in row.items) item.title,
  ],
  for (final genre in browseGenres) genre.label,
  for (final country in browseCountries) country.label,
  for (var i = 1; i <= 6; i++) 'Movie genre $i',
  for (var i = 101; i <= 103; i++) 'TV genre $i',
  for (final presentation in [
    moviePresentation(),
    fixtureSeriesPresentation(),
  ]) ...[
    presentation.item.title,
    ?presentation.summary,
    ?presentation.contentRating,
    ...presentation.genres,
    for (final link in presentation.links) link.label,
    for (final trailer in presentation.trailers) trailer.title,
    for (final member in presentation.cast) ...[member.name, ?member.role],
  ],
  for (final season in fixtureSeriesSeasons()) ...[
    season.title,
    for (final episode in season.episodes) ...[
      episode.title,
      episode.description,
    ],
  ],
  'Actor',
  'Fixture provider',
  'Second provider',
  'Third provider',
  '18.0 GB',
  '4.0 GB',
  '1.4 GB',
  'NOMAD',
  'Softsub',
  'BluRay',
  'WEB-DL',
  'UHD',
  'x265',
  'Living room',
  'https://example.invalid/recent.mp4',
  'Recent fixture',
  'fixture',
};
