import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: child),
);

MovieDetailPresentation _movie({PlaybackProgress? progress}) =>
    MovieDetailPresentation(
      item: const MediaItem(id: 'm', title: 'Movie', kind: MediaKind.movie),
      runtimeLabel: '2h 1m',
      tagline: 'The short tagline',
      summary: 'The full overview of the movie, which is the longer text.',
      progress: progress,
      cast: const <CastMember>[CastMember(name: 'Ann', role: 'Lead', id: 7)],
    );

void main() {
  testWidgets('Play shows no runtime; the full overview beats the tagline', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(
      _app(MovieDetailScreen(presentation: _movie(), onPlay: () {})),
    );
    await tester.pump();
    final play = find.byKey(const ValueKey<String>('detail-play-action'));
    expect(
      find.descendant(of: play, matching: find.text('Play')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: play, matching: find.text('2h 1m')),
      findsNothing,
    );
    expect(find.textContaining('The full overview'), findsOneWidget);
    expect(find.text('The short tagline'), findsNothing);
  });

  testWidgets(
    'a resumable movie shows "Resume" and the resume time in the button',
    (tester) async {
      await setLogicalSize(tester, const Size(1400, 900));
      final progress = PlaybackProgress(
        mediaId: 'm',
        updatedAt: DateTime.utc(2026),
        completed: false,
        position: const Duration(minutes: 12, seconds: 5),
        duration: const Duration(hours: 2),
      );
      await tester.pumpWidget(
        _app(
          MovieDetailScreen(
            presentation: _movie(progress: progress),
            onPlay: () {},
          ),
        ),
      );
      await tester.pump();
      final play = find.byKey(const ValueKey<String>('detail-play-action'));
      expect(
        find.descendant(of: play, matching: find.text('Resume 12:05')),
        findsOneWidget,
      );
    },
  );

  testWidgets('tapping a cast portrait reports that person', (tester) async {
    await setLogicalSize(tester, const Size(1400, 900));
    CastMember? tapped;
    await tester.pumpWidget(
      _app(
        MovieDetailScreen(
          presentation: _movie(),
          onPlay: () {},
          onCastTap: (member) => tapped = member,
        ),
      ),
    );
    await tester.pump();
    final finder = find.byKey(const ValueKey<String>('cast-member-7'));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    expect(tapped?.id, 7);
  });

  testWidgets('episode card is one "E1 · Name" line with no S01E01', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1400, 900));
    await tester.pumpWidget(
      _app(
        EpisodeRow(
          episode: const SeriesEpisode(
            season: 1,
            episode: 1,
            title: 'S01E01 · Welcome to Margrave',
            duration: Duration(minutes: 57),
            description: '',
          ),
          onPlay: () {},
        ),
      ),
    );
    expect(find.text('E1 · Welcome to Margrave'), findsOneWidget);
    expect(find.textContaining('S01E01'), findsNothing);
    expect(find.text('57 min'), findsOneWidget);
  });

  testWidgets('page title starts to the right of the Home pill', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1000, 700));
    const pill = Rect.fromLTWH(106, 50, 60, 60);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: AppShellScope(
            backDispatcher: BackDispatcher(),
            pillRect: pill,
            child: const PageHeader(title: 'United States'),
          ),
        ),
      ),
    );
    final title = tester.getTopLeft(find.text('United States'));
    expect(title.dx, greaterThanOrEqualTo(pill.right));
  });
}
