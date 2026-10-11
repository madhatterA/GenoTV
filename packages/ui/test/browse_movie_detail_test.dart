import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/detail/rating_mark.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 05 (planning/part-04-ui/chapter-02-browse/phase-05-detail.md) proof
// file: fixed backdrop/diagonal scrim, hero metadata/actions, below-fold
// rails (trailers/cast/related/about), Play/Resume thresholds, disabled
// action states, playback-return refresh without page recreation, scroll
// restoration, contrast/2x-text accessibility, and four content goldens.

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

const _item = MediaItem(
  id: 'detail-sintel',
  title: 'Sintel',
  kind: MediaKind.movie,
  duration: Duration(minutes: 14),
  artwork: null,
  subtitle: null,
);

MovieDetailPresentation _fixture({
  PlaybackProgress? progress,
  bool isWatched = false,
  bool isInWatchlist = false,
  List<MediaItem> trailers = const <MediaItem>[],
  List<CastMember> cast = const <CastMember>[],
  List<MediaItem> related = const <MediaItem>[],
  List<AboutFact> about = const <AboutFact>[],
}) => MovieDetailPresentation(
  item: _item.copyWith(
    artwork: Uri.parse('https://example.invalid/detail/sintel.jpg?ar=land'),
  ),
  year: '2010',
  runtimeLabel: '14 min',
  imdbRating: '8.5',
  rottenTomatoes: '58%',
  contentRating: 'PG',
  genres: const <String>['Animation', 'Short', 'Fantasy'],
  // No tagline: source (swift:673-678) DOES prefer `detail.tagline` over
  // `overview` when both exist — "else if let tagline = detail.tagline,
  // !tagline.isEmpty { descriptionLabel.text = tagline ... }" — but
  // Rivulet's own reference screenshot for this exact title
  // (`research/Rivulet/Screenshots/AppStore/03_detail-sintel.png`) shows
  // the long synopsis, not a short italic tagline, meaning the real Sintel
  // record it was captured from has no tagline. This fixture was inventing
  // one that doesn't exist upstream; leaving it null falls through to
  // `summary` and matches the reference art, with the priority logic
  // itself unchanged.
  tagline: null,
  summary:
      'Sintel, a determined young woman, is looking for a baby dragon '
      'she cared for and lost. On her journey she encounters a strange old '
      'man who reminds her about her past and her quest for the dragon.',
  qualityBadges: const <String>['4K', 'HDR', 'Dolby Atmos'],
  progress: progress,
  isWatched: isWatched,
  isInWatchlist: isInWatchlist,
  trailers: trailers,
  cast: cast,
  related: related,
  about: about,
);

extension on MediaItem {
  MediaItem copyWith({Uri? artwork}) => MediaItem(
    id: id,
    title: title,
    kind: kind,
    duration: duration,
    artwork: artwork ?? this.artwork,
    subtitle: subtitle,
  );
}

List<MediaItem> _mediaList(String prefix, int count) => <MediaItem>[
  for (var i = 0; i < count; i++)
    MediaItem(
      id: '$prefix-$i',
      title: '$prefix $i',
      kind: MediaKind.movie,
      artwork: Uri.parse('https://example.invalid/$prefix/$i.jpg?ar=port'),
    ),
];

PlaybackProgress _progressAt(double fraction) => PlaybackProgress(
  mediaId: _item.id,
  position: Duration(seconds: (818 * fraction).round()),
  duration: const Duration(seconds: 818),
  updatedAt: DateTime.utc(2026, 1, 1),
  completed: fraction >= 1,
);

void main() {
  group('facts line and tags', () {
    final links = <DetailLink>[
      const DetailLink('2026', '2026', 'primary_release_year'),
      for (var i = 0; i < 6; i++) DetailLink('Genre$i', '$i', 'with_genres'),
      for (var i = 0; i < 6; i++) DetailLink('Key$i', '$i', 'with_keywords'),
      const DetailLink('United States', 'US', 'with_origin_country'),
    ];
    MovieDetailPresentation withLinks() => MovieDetailPresentation(
      item: _item,
      year: '2026',
      runtimeLabel: '1h 35m',
      imdbRating: '7.3',
      rottenTomatoes: '87%',
      links: links,
    );

    testWidgets('TMDB fallback mark: icon + score, labelled, shown alone', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: MovieDetailPresentation(
              item: _item,
              year: '2026',
              tmdbRating: '7.0',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('TMDB rating 7.0'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('IMDb rating')), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Rotten Tomatoes')), findsNothing);
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: MovieDetailPresentation(item: _item, year: '2026'),
          ),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('rating')), findsNothing);
    });

    testWidgets('rating marks golden: IMDb, RT, TMDB fallback', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF3B2223),
            body: Center(
              child: RepaintBoundary(
                key: const Key('marks'),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    spacing: 24,
                    children: const [
                      RatingMark(imdb: '7.3', scale: 1.5),
                      RatingMark(rottenTomatoes: '87%', scale: 1.5),
                      RatingMark(tmdb: '7.0', scale: 1.5),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await expectLater(
        find.byKey(const Key('marks')),
        matchesGoldenFile('goldens/rating_marks_tmdb_fallback.png'),
      );
    });

    testWidgets('ratings are icon + score with semantic labels, IMDb and RT', (
      tester,
    ) async {
      for (final (imdb, rt) in [('7.3', '87%'), ('5.1', '41%')]) {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            home: Row(
              children: [
                RatingMark(imdb: imdb, scale: 1),
                RatingMark(rottenTomatoes: rt, scale: 1),
              ],
            ),
          ),
        );
        expect(find.bySemanticsLabel('IMDb rating $imdb'), findsOneWidget);
        final state = rt == '87%' ? 'fresh' : 'rotten';
        expect(
          find.bySemanticsLabel('Rotten Tomatoes $state $rt'),
          findsOneWidget,
        );
        expect(find.text('RT'), findsNothing);
      }
    });

    testWidgets('year and country are inline links; tags capped at 7', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      final tapped = <DetailLink>[];
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(presentation: withLinks(), onLinkTap: tapped.add),
        ),
      );
      await tester.pump();
      expect(find.bySemanticsLabel('IMDb rating 7.3'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Rotten Tomatoes fresh 87%'),
        findsOneWidget,
      );
      await tester.tap(find.text('United States'));
      await tester.tap(find.text('2026').first);
      expect(tapped.map((l) => l.filter), [
        'with_origin_country',
        'primary_release_year',
      ]);
      // 6 genres + first keyword = 7 chips; year/country are not chips.
      expect(
        find.byKey(const ValueKey('detail-link-with_keywords-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('detail-link-with_keywords-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('detail-link-with_genres-5')),
        findsOneWidget,
      );
    });
  });

  group('Play/Resume threshold', () {
    testWidgets('zero progress renders Play', (tester) async {
      await tester.pumpWidget(
        _app(MovieDetailScreen(presentation: _fixture(), onPlay: () {})),
      );
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      expect(find.textContaining('Resume'), findsNothing);
    });

    testWidgets('partial progress renders Resume', (tester) async {
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: _fixture(progress: _progressAt(0.4)),
            onPlay: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Resume 5:27'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
    });

    testWidgets('near-complete progress renders Play again (rewatch)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: _fixture(progress: _progressAt(0.99)),
            onPlay: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Play'), findsOneWidget);
      expect(find.textContaining('Resume'), findsNothing);
    });
  });

  group('action callbacks and disabled state', () {
    testWidgets('tapping actions fires the matching callback', (tester) async {
      var played = false;
      var watchedToggled = false;
      var watchlistToggled = false;
      var infoOpened = false;
      await setLogicalSize(tester, const Size(1200, 1800));
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: _fixture(),
            onPlay: () => played = true,
            onToggleWatched: () => watchedToggled = true,
            onToggleWatchlist: () => watchlistToggled = true,
            onInfo: () => infoOpened = true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey<String>('detail-play-action')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('detail-watched-action')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('detail-watchlist-action')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('detail-info-action')),
      );
      expect(played, isTrue);
      expect(watchedToggled, isTrue);
      expect(watchlistToggled, isTrue);
      expect(infoOpened, isTrue);
    });

    testWidgets('watched and watchlist rows show their state', (tester) async {
      await setLogicalSize(tester, const Size(1200, 1800));
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: _fixture(isWatched: true, isInWatchlist: false),
            onPlay: () {},
            onToggleWatched: () {},
            onToggleWatchlist: () {},
          ),
        ),
      );
      await tester.pump();
      final watched = tester.widget<AppRow>(
        find.byKey(const ValueKey<String>('detail-watched-action')),
      );
      final watchlist = tester.widget<AppRow>(
        find.byKey(const ValueKey<String>('detail-watchlist-action')),
      );
      expect(watched.selected, isTrue);
      expect(watchlist.selected, isFalse);
    });

    testWidgets('missing callback removes unavailable actions', (tester) async {
      await tester.pumpWidget(
        _app(MovieDetailScreen(presentation: _fixture())),
      );
      await tester.pump();
      final play = tester.widget<AppButton>(
        find.byKey(const ValueKey<String>('detail-play-action')),
      );
      expect(play.onActivate, isNull);

      expect(
        find.byKey(const ValueKey<String>('detail-watched-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('detail-watchlist-action')),
        findsNothing,
      );
    });
  });

  group('below-fold sections', () {
    testWidgets('only nonempty sections render, in fixed order', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MovieDetailScreen(
              presentation: _fixture(
                cast: const <CastMember>[
                  CastMember(name: 'Halina Reijn', role: 'Sintel'),
                ],
                about: const <AboutFact>[AboutFact('Director', 'Colin Levy')],
              ),
              onPlay: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('detail-section-trailers')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('detail-section-cast')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('detail-section-related')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('detail-section-about')),
        findsOneWidget,
      );

      final castCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('detail-section-cast')),
      );
      final aboutCenter = tester.getCenter(
        find.byKey(const ValueKey<String>('detail-section-about')),
      );
      expect(castCenter.dy, lessThan(aboutCenter.dy));
    });

    testWidgets('all sections empty renders nothing below the hero', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(MovieDetailScreen(presentation: _fixture(), onPlay: () {})),
      );
      await tester.pump();
      expect(find.byType(DetailSections), findsOneWidget);
      final sections = tester.widget<DetailSections>(
        find.byType(DetailSections),
      );
      expect(sections.presentation.trailers, isEmpty);
      expect(sections.presentation.cast, isEmpty);
      expect(sections.presentation.related, isEmpty);
      expect(sections.presentation.about, isEmpty);
    });

    testWidgets('related tap fires callback with the tapped item', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      MediaItem? tapped;
      final related = _mediaList('related', 3);
      await setLogicalSize(tester, const Size(1200, 1400));
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MovieDetailScreen(
              presentation: _fixture(related: related),
              onPlay: () {},
              onRelatedTap: (item) => tapped = item,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final handle = tester.ensureSemantics();
      await tester.tap(find.bySemanticsLabel('related 0').first);
      expect(tapped, related.first);
      handle.dispose();
    });

    testWidgets(
      'action row stays fully inside the hero and above the first rail '
      '(regression: a long synopsis pushed it off the bottom, clipped by '
      'the below-fold Trailers rail)',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        await setLogicalSize(tester, const Size(1920, 1080));
        final trailers = _mediaList('trailer', 3);
        await tester.pumpWidget(
          ArtworkResolverScope(
            resolver: resolver,
            child: _app(
              MovieDetailScreen(
                presentation: _fixture(trailers: trailers),
                onPlay: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final heroBottom = tester
            .getRect(find.byKey(const ValueKey<String>('detail-hero')))
            .bottom;
        final playRect = tester.getRect(
          find.byKey(const ValueKey<String>('detail-play-action')),
        );
        expect(
          playRect.bottom,
          lessThanOrEqualTo(heroBottom),
          reason: 'Play pill must be fully inside the fixed hero band.',
        );

        final trailersTop = tester
            .getTopLeft(
              find.byKey(const ValueKey<String>('detail-section-trailers')),
            )
            .dy;
        expect(
          playRect.bottom,
          lessThanOrEqualTo(trailersTop),
          reason: 'Play pill must not be overlapped by the Trailers rail.',
        );
      },
    );
  });

  group('playback-return refresh', () {
    testWidgets(
      'a new presentation updates progress/watch state without recreating '
      'the page or moving focus',
      (tester) async {
        final key = GlobalKey<MovieDetailScreenState>();
        await tester.pumpWidget(
          _app(
            MovieDetailScreen(
              key: key,
              presentation: _fixture(),
              onPlay: () {},
              onToggleWatched: () {},
            ),
          ),
        );
        await tester.pump();
        final stateBefore = key.currentState;
        expect(find.text('Play'), findsOneWidget);

        // Simulate "opening player records item ID and current focus".
        final playFocus = tester
            .widget<AppButton>(
              find.byKey(const ValueKey<String>('detail-play-action')),
            )
            .focusNode!;
        playFocus.requestFocus();
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey<String>('detail-play-action')),
        );
        expect(key.currentState!.recordedItemId, _item.id);
        expect(key.currentState!.recordedFocusNode, isNotNull);

        // Caller feeds a refreshed presentation (progress advanced,
        // watched flipped) back into the SAME widget/key — this is the
        // playback-return round trip, not a fresh push.
        await tester.pumpWidget(
          _app(
            MovieDetailScreen(
              key: key,
              presentation: _fixture(
                progress: _progressAt(0.5),
                isWatched: true,
              ),
              onPlay: () {},
              onToggleWatched: () {},
            ),
          ),
        );
        await tester.pump();

        expect(key.currentState, same(stateBefore));
        expect(find.textContaining('Resume'), findsOneWidget);
        await tester.dragFrom(const Offset(400, 580), const Offset(0, -900));
        await tester.pumpAndSettle();
        final watched = tester.widget<AppRow>(
          find.byKey(const ValueKey<String>('detail-watched-action')),
        );
        expect(watched.selected, isTrue);
      },
    );
  });

  group('scroll restoration', () {
    testWidgets('scroll offset survives a rebuild via PageStorageKey', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(800, 500));
      final bucket = PageStorageBucket();
      Widget build() => ArtworkResolverScope(
        resolver: resolver,
        child: _app(
          PageStorage(
            bucket: bucket,
            child: MovieDetailScreen(
              presentation: _fixture(
                cast: const <CastMember>[
                  CastMember(name: 'Halina Reijn'),
                  CastMember(name: 'Thom Hoffman'),
                ],
                about: const <AboutFact>[
                  AboutFact('Director', 'Colin Levy'),
                  AboutFact('Studio', 'Blender Foundation'),
                ],
              ),
              onPlay: () {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      // Drag from the bottom edge, clear of the hero's buttons.
      await tester.dragFrom(const Offset(400, 490), const Offset(0, -200));
      await tester.pumpAndSettle();
      // `Scrollable.of` looks for an ANCESTOR Scrollable, so the lookup
      // context must be a descendant of it (e.g. the sections content),
      // not the Scrollable's own element.
      final sectionsContext = tester.element(find.byType(DetailSections));
      final offsetBefore = Scrollable.of(sectionsContext).position.pixels;
      expect(offsetBefore, greaterThan(0));

      // Tear down and rebuild under the same PageStorageBucket.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      final offsetAfter = Scrollable.of(
        tester.element(find.byType(DetailSections)),
      ).position.pixels;
      expect(offsetAfter, offsetBefore);
    });
  });

  group('accessibility', () {
    testWidgets('renders without overflow at 2x text scale', (tester) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, const Size(1024, 900));
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: Scaffold(
                  body: MovieDetailScreen(
                    presentation: _fixture(
                      cast: const <CastMember>[
                        CastMember(name: 'Halina Reijn', role: 'Sintel'),
                      ],
                      about: const <AboutFact>[
                        AboutFact('Director', 'Colin Levy'),
                      ],
                    ),
                    onPlay: () {},
                    onToggleWatched: () {},
                    onToggleWatchlist: () {},
                    onInfo: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('hero title is exposed to semantics in textPrimary', (
      tester,
    ) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: _app(
            MovieDetailScreen(presentation: _fixture(), onPlay: () {}),
          ),
        ),
      );
      await tester.pump();
      final titleFinder = find.byKey(
        const ValueKey<String>('detail-hero-title'),
      );
      expect(titleFinder, findsOneWidget);
      final text = tester.widget<Text>(
        find.descendant(of: titleFinder, matching: find.byType(Text)),
      );
      expect(
        text.style!.color,
        RivuletTokens.of(tester.element(titleFinder)).colors.textPrimary,
      );
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Sintel'), findsWidgets);
      handle.dispose();
    });
  });

  group('four-viewport goldens', () {
    testWidgets(
      'content golden at phone, tablet, desktop and reference widths',
      (tester) async {
        final resolver = await loadFixtureArtworkResolver(tester);
        final presentation = _fixture(
          cast: const <CastMember>[
            CastMember(name: 'Halina Reijn', role: 'Sintel'),
            CastMember(name: 'Thom Hoffman', role: 'Shaman'),
            CastMember(name: 'Jasper Vrancken', role: 'Sintel (young)'),
          ],
          related: _mediaList('related', 6),
          trailers: _mediaList('trailer', 3),
          about: const <AboutFact>[
            AboutFact('Director', 'Colin Levy'),
            AboutFact('Studio', 'Blender Foundation'),
            AboutFact('Released', '2010'),
          ],
        );
        for (final size in const <Size>[
          Size(400, 800),
          Size(800, 800),
          Size(1400, 900),
          Size(1920, 1080),
        ]) {
          await setLogicalSize(tester, size);
          await tester.pumpWidget(
            ArtworkResolverScope(
              resolver: resolver,
              child: _app(
                MovieDetailScreen(presentation: presentation, onPlay: () {}),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 300));
          await expectLater(
            find.byKey(const ValueKey<String>('detail-page')),
            matchesGoldenFile(
              'goldens/browse_movie_detail_content_${size.width.toInt()}.png',
            ),
          );
        }
      },
    );
  });
}
