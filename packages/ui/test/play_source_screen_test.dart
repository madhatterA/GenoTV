import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:ui/src/play_flow/stream_display.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

const _moviejavanMessage = 'MovieJavan login is not set up yet.';

// Real provider order: MovieJavan (parked — auth not wired up), 30nama,
// DigiMoviez (the owner IS logged in to it, so it's a normal working
// provider here — not a failure fixture).
final _providers = <UiProviderOption>[
  const UiProviderOption(
    id: 'moviejavan',
    name: 'MovieJavan',
    state: UiProviderState.failed,
    message: _moviejavanMessage,
  ),
  const UiProviderOption(
    id: 'thirtynama',
    name: '30nama',
    state: UiProviderState.ready,
  ),
  const UiProviderOption(
    id: 'digimoviez',
    name: 'DigiMoviez',
    state: UiProviderState.ready,
  ),
];

final _streams = <SourceSpec>[
  SourceSpec(
    kind: SourceKind.hlsUrl,
    uri: Uri.parse('https://cdn.thirtynama.example/a.m3u8'),
    label: 'Inception 1080p HLS',
    quality: '1080p',
  ),
  SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse('https://cdn.thirtynama.example/b.mkv'),
    label: 'Inception 2160p WEB-DL',
    quality: '2160p',
    expectedBytes: 36400000000,
  ),
  SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse('https://cdn.thirtynama.example/c.mkv'),
    label: 'Inception 1080p WEB-DL',
    quality: '1080p',
    expectedBytes: 2400000000,
  ),
];

Widget _app({
  String? selectedProviderId,
  UiStreamList streams = const UiStreamListNone(),
  ValueChanged<String>? onProviderSelected,
  ValueChanged<SourceSpec>? onStreamSelected,
  VoidCallback? onBack,
  VoidCallback? onInsertLink,
}) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  debugShowCheckedModeBanner: false,
  theme: ThemeData.dark().copyWith(
    extensions: <ThemeExtension<dynamic>>[RivuletTokens.dark(tv: false)],
  ),
  home: PlaySourceScreen(
    title: 'Inception',
    subtitle: '2010 · Movie',
    providers: _providers,
    selectedProviderId: selectedProviderId,
    streams: streams,
    backdropArtwork: 'https://example.invalid/inception-backdrop?ar=land',
    onProviderSelected: onProviderSelected ?? (_) {},
    onStreamSelected: onStreamSelected ?? (_) {},
    onBack: onBack ?? () {},
    onInsertLink: onInsertLink,
  ),
);

Future<Widget> _wrapped(WidgetTester tester, Widget app) async {
  final resolver = await loadFixtureArtworkResolver(tester);
  return ArtworkResolverScope(resolver: resolver, child: app);
}

void main() {
  for (final width in [480.0, 800.0, 1280.0]) {
    testWidgets('torrent peers and file info fit at $width', (tester) async {
      await setLogicalSize(tester, Size(width, 800));
      final torrent = SourceSpec(
        kind: SourceKind.torrentMagnet,
        uri: Uri.parse('magnet:?xt=urn:btih:abc'),
        label: 'Film.1080p.x265-YIFY\nRelease group: YIFY\nSeeders: 733\nLeechers: 66',
        fileHint: 'Film.1080p.x265-YIFY.mkv',
        expectedBytes: 1503238553,
      );
      await tester.pumpWidget(
        await _wrapped(
          tester,
          _app(
            selectedProviderId: 'thirtynama',
            streams: UiStreamListReady([torrent]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey<String>('stream-info')));
      await tester.pumpAndSettle();
      expect(find.text('File name'), findsOneWidget);
      expect(find.text('Film.1080p.x265-YIFY.mkv'), findsOneWidget);
    });
  }
  testWidgets('selecting a provider keeps its row and text size', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    await tester.pumpWidget(await _wrapped(tester, _app()));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey<String>('provider-row-thirtynama'));
    final size = tester.getSize(row);
    final label = find.descendant(of: row, matching: find.byType(Text)).first;
    final textSize = tester.getSize(label);
    await tester.pumpWidget(
      await _wrapped(tester, _app(selectedProviderId: 'thirtynama')),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(row), size);
    expect(tester.getSize(label), textSize);
    final tokens = RivuletTokens.of(tester.element(row));
    expect(tokens.colors.panelRowSelectedFill.a, lessThan(0.3));
  });

  testWidgets(
    'torrent rows show success-coloured seeders with a down arrow and retained release info',
    (tester) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      final torrent = SourceSpec(
        kind: SourceKind.torrentMagnet,
        uri: Uri.parse('magnet:?xt=urn:btih:abc'),
        label: 'Film.2020.1080p.x265-YIFY\nRelease group: YIFY\nSeeders: 12\nLeechers: 3',
      );
      await tester.pumpWidget(
        await _wrapped(
          tester,
          _app(
            selectedProviderId: 'thirtynama',
            streams: UiStreamListReady([torrent]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('YIFY'), findsOneWidget);
      // Seeders only: green count with a down arrow; leechers are not shown.
      expect(
        tester.widget<Text>(find.text('12')).style!.color,
        RivuletTokens.of(tester.element(find.text('12'))).colors.success,
      );
      expect(find.byIcon(PhosphorIconsRegular.arrowDown), findsOneWidget);
      expect(find.textContaining('↑'), findsNothing);
      expect(find.text('3'), findsNothing);
      await expectLater(
        find.byType(PlaySourceScreen),
        matchesGoldenFile('goldens/play_source_torrent.png'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('stream-info')));
      await tester.pumpAndSettle();
      expect(find.text('Release'), findsOneWidget);
      expect(find.text('Film.2020.1080p.x265-YIFY'), findsOneWidget);
    },
  );
  for (final size in const [
    Size(480, 480),
    Size(800, 600),
    Size(1280, 800),
    Size(1920, 1080),
  ]) {
    testWidgets(
      'provider + stream list lays out at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await setLogicalSize(tester, size);
        await tester.pumpWidget(
          await _wrapped(
            tester,
            _app(
              selectedProviderId: 'thirtynama',
              streams: UiStreamListReady(_streams),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('providers golden', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(await _wrapped(tester, _app(onInsertLink: () {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_providers.png'),
    );
  });

  testWidgets('loading golden', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: const UiStreamListLoading(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_loading.png'),
    );
  });

  testWidgets('streams golden', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady(_streams),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_streams.png'),
    );
  });

  testWidgets('all compact badges remain on one stream row', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    final featured = SourceSpec(
      kind: SourceKind.httpUrl,
      uri: Uri.parse(
        'https://cdn.example/Movie.2160p.HDR10%2B.DoVi.10bit.x265.CC-CtrlHD.mkv',
      ),
    );
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady([featured]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final badge in ['4K', 'HDR10+', 'DV', '10-bit', 'H.265']) {
      expect(find.text(badge), findsOneWidget);
    }
    expect(find.byKey(const ValueKey<String>('badge-cc')), findsOneWidget);
    expect(find.text('CtrlHD'), findsOneWidget);
    expect(
      tester.getCenter(find.text('4K')).dy,
      tester.getCenter(find.text('H.265')).dy,
    );
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_badges.png'),
    );
  });

  testWidgets('streams focused golden — stream row 1 focused', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady(_streams),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Row 0 autofocuses on mount (Decisions: "first stream row takes
    // focus"); move to row 1 explicitly with a directional key the row
    // itself doesn't intercept, then simulate focus arriving there so the
    // pill/focus-ring treatment is provable without shipping a
    // key-driven up/down traversal this phase doesn't ask for.
    // `stream-row-1` wraps two `Focus` widgets: an outer one (arrow-left
    // handling only, its own unrelated implicit node) and `PanelRow`'s own
    // inner one, which shares `_StreamRowState`'s node — the one that
    // actually drives both the pill/ring visual and the row content's
    // focused-foreground color. `.last` is the inner one.
    final row1 = tester.widget<Focus>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('stream-row-1')),
            matching: find.byType(Focus),
          )
          .last,
    );
    row1.focusNode?.requestFocus();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_streams_focused.png'),
    );
  });

  testWidgets('failed golden — tapped provider fails (MovieJavan auth)', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'moviejavan',
          streams: const UiStreamListFailed(_moviejavanMessage),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(PlaySourceScreen),
      matchesGoldenFile('goldens/play_source_failed.png'),
    );
  });

  testWidgets('tapping a provider row calls onProviderSelected', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    String? selected;
    await tester.pumpWidget(
      await _wrapped(tester, _app(onProviderSelected: (id) => selected = id)),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('provider-row-thirtynama')),
    );
    await tester.pump();
    expect(selected, 'thirtynama');
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping stream row 2 calls onStreamSelected with second spec', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    SourceSpec? selected;
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady(_streams),
          onStreamSelected: (spec) => selected = spec,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stream-row-1')));
    await tester.pump();
    expect(selected, _streams[1]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'HLS variants show one Auto row and file info shows filename only',
    (tester) async {
      await setLogicalSize(tester, const Size(1920, 1080));
      final variants = [
        _streams.first,
        SourceSpec(
          kind: SourceKind.hlsUrl,
          uri: Uri.parse('https://cdn.example/auto.m3u8?token=private'),
          label: 'HLS Auto',
        ),
        _streams[1],
      ];
      await tester.pumpWidget(
        await _wrapped(
          tester,
          _app(
            selectedProviderId: 'thirtynama',
            streams: UiStreamListReady(variants),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('stream-row-2')), findsNothing);
      expect(find.text('HLS'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('stream-info')).first);
      await tester.pumpAndSettle();
      expect(find.text('auto.m3u8'), findsOneWidget);
      expect(find.textContaining('token=private'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Escape calls onBack', (tester) async {
    await setLogicalSize(tester, const Size(1920, 1080));
    var backCalled = false;
    await tester.pumpWidget(
      await _wrapped(tester, _app(onBack: () => backCalled = true)),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(backCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a provider row keeps its height while its links load', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 800));
    Widget screen(UiProviderState state) => MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: ThemeData.dark().copyWith(
        extensions: <ThemeExtension<dynamic>>[RivuletTokens.dark(tv: false)],
      ),
      home: PlaySourceScreen(
        title: 'Inception',
        providers: [
          UiProviderOption(id: 'thirtynama', name: '30nama', state: state),
        ],
        selectedProviderId: 'thirtynama',
        streams: state == UiProviderState.loading
            ? const UiStreamListLoading()
            : UiStreamListReady(_streams),
        onProviderSelected: (_) {},
        onStreamSelected: (_) {},
        onBack: () {},
      ),
    );
    final row = find.byKey(const ValueKey<String>('provider-row-thirtynama'));
    await tester.pumpWidget(
      await _wrapped(tester, screen(UiProviderState.ready)),
    );
    await tester.pumpAndSettle();
    final ready = tester.getSize(row);
    await tester.pumpWidget(
      await _wrapped(tester, screen(UiProviderState.loading)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      find.byKey(const ValueKey<String>('provider-loading')),
      findsOneWidget,
    );
    expect(tester.getSize(row), ready);
  });

  testWidgets('streams sort by size; torrents also by seeds', (tester) async {
    await setLogicalSize(tester, const Size(1280, 800));
    SourceSpec torrent(String name, int seeders, int bytes) => SourceSpec(
      kind: SourceKind.torrentMagnet,
      uri: Uri.parse('magnet:?xt=urn:btih:$name'),
      label: '$name.1080p-GRP\nRelease group: $name\nSeeders: $seeders',
      expectedBytes: bytes,
    );
    final specs = [
      torrent('Small', 900, 1000),
      torrent('Huge', 5, 9000),
      torrent('Mid', 300, 5000),
    ];
    Future<List<String>> order() async {
      final names = <String>[];
      for (var i = 0; i < 3; i++) {
        final row = find.byKey(ValueKey<String>('stream-row-$i'));
        names.add(
          ['Small', 'Huge', 'Mid'].firstWhere(
            (n) => find
                .descendant(of: row, matching: find.text(n))
                .evaluate()
                .isNotEmpty,
          ),
        );
      }
      return names;
    }

    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady(specs),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(await order(), ['Small', 'Huge', 'Mid']); // default order kept
    await tester.tap(find.byKey(const ValueKey<String>('stream-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Seeds'), findsOneWidget);
    await tester.tap(find.text('Size'));
    await tester.pumpAndSettle();
    expect(await order(), ['Huge', 'Mid', 'Small']);
    await tester.tap(find.byKey(const ValueKey<String>('stream-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Seeds'));
    await tester.pumpAndSettle();
    expect(await order(), ['Small', 'Mid', 'Huge']);
  });

  testWidgets('non-torrent streams offer Size only', (tester) async {
    await setLogicalSize(tester, const Size(1280, 800));
    await tester.pumpWidget(
      await _wrapped(
        tester,
        _app(
          selectedProviderId: 'thirtynama',
          streams: UiStreamListReady(_streams),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('stream-sort')));
    await tester.pumpAndSettle();
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('Seeds'), findsNothing);
  });

  testWidgets(
    'torrent titles with a bare % render in default and sorted order',
    (tester) async {
      await setLogicalSize(tester, const Size(1280, 800));
      final specs = [
        // Magnet whose display name holds a raw '%'; no label, so the name
        // comes from the magnet itself.
        SourceSpec(
          kind: SourceKind.torrentMagnet,
          uri: Uri.parse('magnet:?xt=urn:btih:aaa&dn=Movie 100% Uncut 2160p'),
          expectedBytes: 9000,
        ),
        SourceSpec(
          kind: SourceKind.torrentMagnet,
          uri: Uri.parse('magnet:?xt=urn:btih:bbb'),
          label: 'Movie 100% Uncut 2160p\nRelease group: GRP\nSeeders: 5',
          fileHint: 'Movie 100% Uncut 2160p.mkv',
          expectedBytes: 5000,
        ),
      ];
      await tester.pumpWidget(
        await _wrapped(
          tester,
          _app(
            selectedProviderId: 'thirtynama',
            streams: UiStreamListReady(specs),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(
        parseStreamDisplay(specs[0], providerName: 'T').fileName,
        'Movie 100% Uncut 2160p',
      );
      for (final choice in ['Size', 'Seeds']) {
        await tester.tap(find.byKey(const ValueKey<String>('stream-sort')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey<String>('stream-row-1')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const ValueKey<String>('stream-info')).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('100% Uncut'), findsWidgets);
    },
  );
}
