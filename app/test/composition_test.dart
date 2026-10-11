import 'dart:io';

import 'package:contracts/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

import 'package:ui/ui.dart';
import 'package:video_player/composition.dart';
import 'package:video_player/fixture_provider.dart';

void main() {
  runSourceProviderContractTests(FixtureProvider.new);

  test('fixture provider exposes every source kind without fakes', () async {
    final provider = FixtureProvider();
    final page = await provider.browse(const BrowseQuery(limit: 20));
    final kinds = <SourceKind>{};
    for (final item in page.items) {
      kinds.addAll((await provider.resolve(item)).map((source) => source.kind));
    }
    expect(kinds, {
      SourceKind.localFile,
      SourceKind.httpUrl,
      SourceKind.torrentMagnet,
      SourceKind.torrentFile,
    });
    await provider.dispose();
  });

  test(
    'local fixture resolves to a real file for the end-to-end path',
    () async {
      final provider = FixtureProvider();
      addTearDown(provider.dispose);
      final item = (await provider.browse(const BrowseQuery(limit: 20))).items
          .firstWhere((item) => item.id == 'fixture-movie');
      final source = (await provider.resolve(item)).single;

      expect(source.kind, SourceKind.localFile);
      expect(source.uri.isScheme('file'), isTrue);
      expect(File.fromUri(source.uri).existsSync(), isTrue);
    },
  );

  test(
    'created provider materializes and safely reuses its cache fixture',
    () async {
      final cache = await Directory.systemTemp.createTemp('fixture-cache-');
      addTearDown(() => cache.delete(recursive: true));

      final first = await FixtureProvider.create(fixtureDirectory: cache);
      final firstSource = (await first.resolve(
        (await first.browse(const BrowseQuery(limit: 20))).items.first,
      )).single;
      final cached = File.fromUri(firstSource.uri);
      final original = await cached.readAsBytes();
      expect(firstSource.uri.toFilePath(), '${cache.path}/Butterfly-209.mp4');
      expect(original, isNotEmpty);
      await first.dispose();

      await cached.writeAsBytes(const <int>[]);
      final refreshed = await FixtureProvider.create(fixtureDirectory: cache);
      expect(await cached.readAsBytes(), original);
      await refreshed.dispose();

      await cached.writeAsBytes(const <int>[1, 2, 3]);
      final reused = await FixtureProvider.create(fixtureDirectory: cache);
      expect(await cached.readAsBytes(), <int>[1, 2, 3]);
      await reused.dispose();
    },
  );

  test('fixture search is deterministic and paged', () async {
    final provider = FixtureProvider();
    final result = await provider.search('episode', limit: 1);
    expect(result.items, hasLength(1));
    expect(result.items.single.id, 'fixture-episode');
    expect(result.hasMore, isFalse);
    await provider.dispose();
  });

  testWidgets('composition renders provider catalogue on home and library', (
    tester,
  ) async {
    final provider = FixtureProvider();
    addTearDown(provider.dispose);

    // AppShell only renders the compact bottom bar below the 600pt
    // breakpoint (RivuletLayout); the default 800x600 test surface lands in
    // "medium", which uses the sidebar instead.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: false),
        home: AppShell(
          activeId: 'home',
          destinations: <AppDestination>[
            AppDestination(
              id: 'home',
              label: 'Home',
              icon: Icons.home,
              builder: (_) => FixtureCatalogueView(provider: provider),
            ),
            AppDestination(
              id: 'library',
              label: 'Library',
              icon: Icons.video_library,
              builder: (_) =>
                  FixtureCatalogueView(provider: provider, library: true),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Fixture catalogue'), findsOneWidget);
    // Poster tiles render no visible title caption (Rivulet `PosterCell`
    // parity, see bug_history.md); the tile still carries a Semantics label
    // with the title for accessibility, so identity is checked that way.
    // Scoped to the poster tile specifically (`FocusableCard`): the Part B
    // hero focus wiring (`HeroBackdrop`'s Play/Watchlist/Info/Next `Focus`
    // nodes) gives the hero its own semantics boundary, so with only one
    // fixture item the hero's title text now also exposes its own
    // "Fixture Movie" node (previously merged, invisibly, into one
    // multi-line hero label) — a real second match, not a regression.
    expect(
      find.descendant(
        of: find.byType(MediaRow),
        matching: find.bySemanticsLabel('Fixture Movie'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('menu-item-library')));
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Fixture Episode'), findsOneWidget);
  });
}
