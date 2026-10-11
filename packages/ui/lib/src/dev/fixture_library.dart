import 'package:contracts/contracts.dart';

import '../browse/home_view_model.dart';
import '../detail/movie_detail_presentation.dart';
import '../detail/series_view_model.dart';

List<HomeRow> fixtureHomeRows() {
  const rowTitles = <String>[
    'Continue watching',
    'Trending',
    'Iranian films',
    'New releases',
    'Because you watched',
  ];
  return <HomeRow>[
    for (var row = 0; row < rowTitles.length; row++)
      HomeRow(
        title: rowTitles[row],
        items: <MediaItem>[
          for (var index = 0; index < 20; index++)
            MediaItem(
              id: 'fixture-$row-$index',
              title: row == 2 && index == 3
                  ? 'یک عنوان فارسی بسیار طولانی برای آزمایش برش متن'
                  : '${rowTitles[row]} ${index + 1}',
              kind: index.isEven ? MediaKind.movie : MediaKind.episode,
              subtitle: index.isOdd ? 'S${row + 1}E${index + 1}' : null,
              year: 2000 + (row * 7 + index * 3) % 25,
              duration: Duration(minutes: 84 + index * 4),
              // `ar=land`/`ar=port` is a test-fixture-only hint consumed by
              // `loadFixtureArtworkResolver` to hand landscape stills to the
              // continue-watching row (row 0, same tile shape as the hero
              // backdrop) and portrait posters to every other row — real
              // artwork URLs carry no such query.
              artwork: index == 4
                  ? null
                  : Uri.parse(
                      'https://example.invalid/$row/$index.jpg'
                      '?ar=${row == 0 ? 'land' : 'port'}',
                    ),
            ),
        ],
      ),
  ];
}

List<MediaItem> fixtureLibraryItems({int count = 2000}) => <MediaItem>[
  for (var index = 0; index < count; index++)
    MediaItem(
      id: 'library-$index',
      title: index == count - 1
          ? 'Library fixture last title'
          : 'Library fixture title ${index + 1}',
      kind: index.isEven ? MediaKind.movie : MediaKind.episode,
      duration: Duration(minutes: 80 + (index % 40)),
      artwork: index % 7 == 0
          ? null
          : Uri.parse('https://example.invalid/library/$index.jpg'),
    ),
];

/// Realistic (fictional) episode titles for the "Harbor Line" fixture
/// series, cycled per season so goldens never show a placeholder
/// "Fixture episode N" label.
const List<String> _episodeTitles = <String>[
  'The Low Tide',
  'Harbor Lights',
  'A Stranger\'s Wake',
  'Salt in the Water',
  'What the Net Caught',
  'Old Debts',
  'The Longshoreman',
  'Undertow',
  'A Quiet Departure',
  'The Ferry Master',
  'Static on the Radio',
  'Harbor Line',
];

List<SeriesSeason> fixtureSeriesSeasons() => <SeriesSeason>[
  for (var season = 1; season <= 4; season++)
    SeriesSeason(
      number: season,
      title: 'Season $season',
      episodes: <SeriesEpisode>[
        for (
          var episode = 1;
          episode <= (season == 3 ? 1 : 10 + season * 4);
          episode++
        )
          SeriesEpisode(
            season: season,
            episode: episode,
            title: _episodeTitles[(episode - 1) % _episodeTitles.length],
            duration: Duration(minutes: 42 + episode),
            description: episode == 5
                ? 'A longer focused episode description. ' * 8
                : 'The crew follows a lead that surfaces after the storm, '
                      'and Elena has to decide how much of the past she is '
                      'willing to reopen.',
            still: Uri.parse(
              'https://example.invalid/still/$season/$episode.jpg?ar=land',
            ),
            progress: season == 1 && episode == 2 ? 0.45 : null,
          ),
      ],
    ),
];

/// Realistic (fictional, non-trademarked) cast for series/person goldens —
/// original names, never a real actor or real show, per the safety
/// guidance against depicting real people.
List<CastMember> fixtureCastMembers() => <CastMember>[
  CastMember(
    id: 101,
    name: 'Mara Voss',
    role: 'Elena Cortez',
    photo: Uri.parse('https://example.invalid/person/mara-voss.jpg?ar=port'),
  ),
  CastMember(
    id: 102,
    name: 'Idris Calder',
    role: 'Detective Sam Whitlock',
    photo: Uri.parse('https://example.invalid/person/idris-calder.jpg?ar=port'),
  ),
  CastMember(
    id: 103,
    name: 'Priya Anand',
    role: 'Dr. Neha Rao',
    photo: Uri.parse('https://example.invalid/person/priya-anand.jpg?ar=port'),
  ),
  CastMember(
    id: 104,
    name: 'Tomas Reyes',
    role: 'Captain Marcus Boyle',
    photo: Uri.parse('https://example.invalid/person/tomas-reyes.jpg?ar=port'),
  ),
  CastMember(
    id: 105,
    name: 'Greta Lindqvist',
    role: 'Ingrid Solberg',
    photo: Uri.parse(
      'https://example.invalid/person/greta-lindqvist.jpg?ar=port',
    ),
  ),
];

/// A realistic series presentation for goldens — synopsis, genres, cast.
MovieDetailPresentation fixtureSeriesPresentation() => MovieDetailPresentation(
  item: MediaItem(
    id: 'series-harbor-line',
    title: 'Harbor Line',
    kind: MediaKind.episode,
    artwork: Uri.parse(
      'https://example.invalid/series/harbor-line.jpg?ar=land',
    ),
  ),
  poster: Uri.parse('https://example.invalid/series/harbor-line.jpg?ar=port'),
  year: '2023',
  imdbRating: '8.1',
  rottenTomatoes: '92%',
  contentRating: 'TV-MA',
  genres: const <String>['Crime', 'Drama', 'Mystery'],
  summary:
      'A coastal detective unravels a decade-old disappearance that '
      'ties her own family to the harbor town\'s most powerful shipping '
      'dynasty.',
  qualityBadges: const <String>['4K', 'HDR10'],
  cast: fixtureCastMembers(),
);

/// Known-for/filmography items for a [PersonDetailScreen] golden.
List<MediaItem> fixturePersonFilmography() => <MediaItem>[
  MediaItem(
    id: 'film-1',
    title: 'Low Tide',
    kind: MediaKind.movie,
    artwork: Uri.parse('https://example.invalid/film/low-tide.jpg?ar=port'),
  ),
  MediaItem(
    id: 'film-2',
    title: 'Harbor Line',
    kind: MediaKind.episode,
    artwork: Uri.parse('https://example.invalid/film/harbor-line.jpg?ar=port'),
  ),
  MediaItem(
    id: 'film-3',
    title: 'Salt Road',
    kind: MediaKind.movie,
    artwork: Uri.parse('https://example.invalid/film/salt-road.jpg?ar=port'),
  ),
  MediaItem(
    id: 'film-4',
    title: 'The Quiet Pier',
    kind: MediaKind.movie,
    artwork: Uri.parse('https://example.invalid/film/quiet-pier.jpg?ar=port'),
  ),
];
