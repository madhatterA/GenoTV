import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

SourceStatus _source(
  SourceState state, {
  double speed = 0,
  int? total,
  int downloaded = 0,
}) => SourceStatus(
  state: state,
  available: downloaded > 0
      ? RangeSet.empty().add(ByteRange(0, downloaded - 1))
      : RangeSet.empty(),
  totalBytes: total,
  bytesPerSecond: speed,
  peersOrConnections: 0,
);

PlaybackState _playback({
  double? buffering,
  Duration duration = Duration.zero,
  bool playing = false,
}) => PlaybackState.initial().copyWith(
  bufferingProgress: buffering,
  duration: duration,
  isPlaying: playing,
);

Future<Widget> _app(
  WidgetTester tester,
  Widget home, {
  bool reduceMotion = false,
}) async {
  final resolver = await loadFixtureArtworkResolver(tester);
  return ArtworkResolverScope(
    resolver: resolver,
    child: MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[RivuletTokens.dark(tv: false)],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: child!,
      ),
      home: home,
    ),
  );
}

StreamOpeningScreen _screen({
  StreamOpeningStatus status = const StreamOpeningStatus(
    label: 'Buffering 42%',
    progress: 0.42,
  ),
  AppFailure? failure,
  VoidCallback? onRetry,
  VoidCallback? onBack,
}) => StreamOpeningScreen(
  title: 'Inception',
  artwork: Uri.parse('https://example.invalid/inception-backdrop?ar=land'),
  kind: MediaKind.movie,
  status: status,
  failure: failure,
  onRetry: onRetry,
  onBack: onBack ?? () {},
);

double? _barValue(WidgetTester tester) => tester
    .widget<LinearProgressIndicator>(
      find.byKey(const ValueKey<String>('stream-opening-bar')),
    )
    .value;

void main() {
  group('stage and progress mapping', () {
    test('before the stream handle exists an http source is connecting', () {
      final status = StreamOpeningStatus.from(kind: SourceKind.httpUrl);
      expect(status.label, 'Connecting…');
      expect(status.progress, isNull);
    });

    test('before the stream handle exists a torrent fetches metadata', () {
      for (final kind in [SourceKind.torrentMagnet, SourceKind.torrentFile]) {
        final status = StreamOpeningStatus.from(kind: kind);
        expect(status.label, 'Fetching metadata…');
        expect(status.progress, isNull);
      }
    });

    test('transport metadata state reports metadata, no total', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.torrentMagnet,
        source: _source(SourceState.metadata),
      );
      expect(status.label, 'Fetching metadata…');
      expect(status.progress, isNull);
    });

    test('engine buffering below 100 % is a determinate percentage', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: _source(SourceState.buffering),
        playback: _playback(buffering: 0.42),
      );
      expect(status.label, 'Buffering 42%');
      expect(status.progress, 0.42);
    });

    test('download speed is appended when the transport reports one', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: _source(SourceState.buffering, speed: 2 * 1024 * 1024),
        playback: _playback(buffering: 0.1),
      );
      expect(status.label, startsWith('Buffering 10% · '));
      expect(status.label, endsWith('/s'));
    });

    test('an open handle with no engine number is indeterminate', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: _source(SourceState.ready),
        playback: _playback(buffering: 1),
      );
      expect(status.label, 'Preparing video…');
      expect(status.progress, isNull);
    });

    test(
      'preparing measures progress to the first 5 minutes, not the file',
      () {
        // 1000 MiB over 50 minutes: the first 5 minutes are 100 MiB.
        final status = StreamOpeningStatus.from(
          kind: SourceKind.httpUrl,
          source: _source(
            SourceState.ready,
            total: 1000 * 1024 * 1024,
            downloaded: 30 * 1024 * 1024,
          ),
          playback: _playback(
            buffering: 1,
            duration: const Duration(minutes: 50),
          ),
        );
        expect(status.label, startsWith('Preparing video… '));
        expect(status.label, contains('30.0 MB / 100 MB'));
        expect(status.label, isNot(contains('1000 MB')));
        expect(status.progress, closeTo(0.3, 1e-9));
      },
    );

    test('bytes beyond the first 5 minutes do not count toward the bar', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: SourceStatus(
          state: SourceState.ready,
          available: RangeSet.empty()
              .add(const ByteRange(0, 10 * 1024 * 1024 - 1))
              .add(ByteRange(900 * 1024 * 1024, 950 * 1024 * 1024 - 1)),
          totalBytes: 1000 * 1024 * 1024,
          bytesPerSecond: 0,
          peersOrConnections: 0,
        ),
        playback: _playback(
          buffering: 1,
          duration: const Duration(minutes: 50),
        ),
      );
      expect(status.progress, closeTo(0.1, 1e-9));
    });

    test('a short video needs only its own length', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: _source(
          SourceState.ready,
          total: 40 * 1024 * 1024,
          downloaded: 10 * 1024 * 1024,
        ),
        playback: _playback(buffering: 1, duration: const Duration(minutes: 2)),
      );
      expect(status.progress, closeTo(0.25, 1e-9));
    });

    test(
      'a known size without a duration stays indeterminate, no total shown',
      () {
        final status = StreamOpeningStatus.from(
          kind: SourceKind.httpUrl,
          source: _source(
            SourceState.ready,
            total: 1000 * 1024 * 1024,
            downloaded: 100 * 1024 * 1024,
          ),
          playback: _playback(buffering: 1),
        );
        expect(status.label, contains('100 MB'));
        expect(status.label, isNot(contains('1000 MB')));
        expect(status.progress, isNull);
      },
    );

    test('preparing with bytes but no size stays indeterminate', () {
      final status = StreamOpeningStatus.from(
        kind: SourceKind.httpUrl,
        source: _source(SourceState.ready, downloaded: 4096),
        playback: _playback(buffering: 1),
      );
      expect(status.label, startsWith('Preparing video…'));
      expect(status.progress, isNull);
    });

    test('ready needs a known duration, playing and a full buffer', () {
      const d = Duration(minutes: 90);
      expect(StreamOpeningStatus.isReady(_playback()), isFalse);
      expect(
        StreamOpeningStatus.isReady(_playback(duration: d, playing: true)),
        isTrue,
      );
      expect(
        StreamOpeningStatus.isReady(
          _playback(duration: d, playing: true, buffering: 0.5),
        ),
        isFalse,
      );
      expect(StreamOpeningStatus.isReady(_playback(duration: d)), isFalse);
    });
  });

  group('opening screen', () {
    testWidgets('shows title, orb, determinate bar and status line', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(await _app(tester, _screen()));
      await tester.pump();
      expect(find.text('Inception'), findsOneWidget);
      expect(find.byType(OrbLoader), findsOneWidget);
      expect(find.text('Buffering 42%'), findsOneWidget);
      expect(_barValue(tester), 0.42);
    });

    testWidgets('a stage without a total animates the bar, never fakes', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        await _app(
          tester,
          _screen(status: const StreamOpeningStatus(label: 'Connecting…')),
        ),
      );
      await tester.pump();
      expect(_barValue(tester), isNull);
    });

    testWidgets('reduced motion shows an empty track, not a moving bar', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        await _app(
          tester,
          _screen(status: const StreamOpeningStatus(label: 'Connecting…')),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      expect(_barValue(tester), 0);
    });

    testWidgets('a failure shows Retry and Back that call back', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      var retried = 0;
      var backed = 0;
      await tester.pumpWidget(
        await _app(
          tester,
          _screen(
            failure: const UnexpectedFailure(cause: 'boom'),
            onRetry: () => retried++,
            onBack: () => backed++,
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(OrbLoader), findsNothing);
      await tester.tap(find.text('Retry'));
      await tester.tap(find.text('Back'));
      expect(retried, 1);
      expect(backed, 1);
    });

    testWidgets('fits a phone width', (tester) async {
      await setLogicalSize(tester, const Size(390, 844));
      await tester.pumpWidget(await _app(tester, _screen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('layout and leaving', () {
    for (final size in const <Size>[
      Size(390, 844),
      Size(1440, 900),
      Size(1920, 1080),
    ]) {
      testWidgets('title, orb, bar, status do not overlap at $size', (
        tester,
      ) async {
        await setLogicalSize(tester, size);
        await tester.pumpWidget(await _app(tester, _screen()));
        await tester.pump();
        Rect r(Finder f) => tester.getRect(f);
        final title = r(find.byKey(const ValueKey('stream-opening-title')));
        final orb = r(find.byType(OrbLoader));
        final bar = r(find.byKey(const ValueKey('stream-opening-bar')));
        final status = r(find.byKey(const ValueKey('stream-opening-status')));
        // The orb paints a halo outside its box: keep the whole halo clear.
        final halo = orb.inflate(orb.width * 0.35);
        expect(halo.bottom, lessThanOrEqualTo(bar.top));
        expect(halo.top, greaterThanOrEqualTo(title.bottom));
        expect(bar.bottom, lessThanOrEqualTo(status.top));
      });
    }

    // TV Back arrives as a route pop (Navigator.maybePop), which the app
    // already routes to onBack; Escape is the keyboard path.
    testWidgets('Escape leaves the opening screen', (tester) async {
      var backs = 0;
      await tester.pumpWidget(
        await _app(tester, _screen(onBack: () => backs++)),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(backs, 1);
    });
  });

  group('cross-fade to the first frame', () {
    Widget host({required bool ready}) => StreamOpeningHost(
      ready: ready,
      player: const ColoredBox(
        key: ValueKey<String>('player-stub'),
        color: Color(0xFF123456),
      ),
      screen: _screen(),
    );

    double opacity(WidgetTester tester) => tester
        .widget<FadeTransition>(
          find.byKey(const ValueKey<String>('stream-opening-fade')),
        )
        .opacity
        .value;

    testWidgets('screen is opaque until ready, then fades and is removed', (
      tester,
    ) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(await _app(tester, host(ready: false)));
      await tester.pump();
      expect(opacity(tester), 1);
      await tester.pumpWidget(await _app(tester, host(ready: true)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(tester), inExclusiveRange(0, 1));
      expect(find.byKey(const ValueKey<String>('player-stub')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(StreamOpeningScreen), findsNothing);
      expect(find.byKey(const ValueKey<String>('player-stub')), findsOneWidget);
    });

    testWidgets('reduced motion still ends within 120 ms', (tester) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        await _app(tester, host(ready: false), reduceMotion: true),
      );
      await tester.pump();
      await tester.pumpWidget(
        await _app(tester, host(ready: true), reduceMotion: true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 130));
      expect(find.byType(StreamOpeningScreen), findsNothing);
    });

    testWidgets('a failure keeps the screen even when ready', (tester) async {
      await setLogicalSize(tester, const Size(1280, 800));
      await tester.pumpWidget(
        await _app(
          tester,
          StreamOpeningHost(
            ready: true,
            player: const SizedBox(),
            screen: _screen(failure: const UnexpectedFailure(cause: 'x')),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StreamOpeningScreen), findsOneWidget);
    });
  });

  group('goldens', () {
    for (final (name, size) in <(String, Size)>[
      ('phone', const Size(390, 844)),
      ('desktop', const Size(1440, 900)),
    ]) {
      testWidgets('buffering $name', (tester) async {
        await setLogicalSize(tester, size);
        await tester.pumpWidget(await _app(tester, _screen()));
        await tester.pump();
        await expectLater(
          find.byType(StreamOpeningScreen),
          matchesGoldenFile('goldens/stream_opening_$name.png'),
        );
      });
    }

    testWidgets('error desktop', (tester) async {
      await setLogicalSize(tester, const Size(1440, 900));
      await tester.pumpWidget(
        await _app(
          tester,
          _screen(
            failure: const UnexpectedFailure(cause: 'boom'),
            onRetry: () {},
          ),
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(StreamOpeningScreen),
        matchesGoldenFile('goldens/stream_opening_error_desktop.png'),
      );
    });
  });
}
