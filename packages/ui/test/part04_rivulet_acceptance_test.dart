import 'dart:ui' as ui;

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

const _viewports = <Size>[
  Size(400, 800),
  Size(844, 390),
  Size(1280, 800),
  Size(1920, 1080),
];

const _items = <MediaItem>[
  MediaItem(
    id: 'acc-1',
    title: 'Acceptance One',
    kind: MediaKind.movie,
    duration: Duration(minutes: 90),
  ),
  MediaItem(
    id: 'acc-2',
    title: 'Acceptance Two',
    kind: MediaKind.movie,
    duration: Duration(minutes: 95),
  ),
];

class _CountingSurface extends FakeVideoSurface {
  _CountingSurface(this.onBuild);
  final VoidCallback onBuild;

  @override
  Widget build(
    BuildContext context,
    controller, {
    BoxFit fit = BoxFit.contain,
    Color background = Colors.black,
  }) {
    onBuild();
    return const ColoredBox(color: Colors.black);
  }
}

void main() {
  for (final size in _viewports) {
    testWidgets(
      'one fixture graph: shell, home, tabs, player at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await setLogicalSize(tester, size);
        final trace = <String>[];
        final controller = FakePlaybackController()
          ..setDuration(const Duration(minutes: 5));
        final model = HomeViewModel(
          rows: const <HomeRow>[
            HomeRow(title: 'Acceptance row', items: _items),
          ],
        );
        final navKey = GlobalKey<NavigatorState>();
        var surfaces = 0;
        var exits = 0;
        final compact = size.width < 700;

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            debugShowCheckedModeBanner: false,
            navigatorKey: navKey,
            theme: AppTheme.dark(tv: false),
            home: AppShell(
              activeId: 'home',
              onExitRequested: () {
                exits++;
                trace.add('exit');
              },
              destinations: <AppDestination>[
                AppDestination(
                  id: 'home',
                  label: 'Home',
                  icon: Icons.home_filled,
                  builder: (_) => HomeScreen(
                    viewModel: model,
                    onItemTap: (item) => trace.add('open:${item.id}'),
                  ),
                ),
                AppDestination(
                  id: 'library',
                  label: 'Library',
                  icon: Icons.video_library,
                  builder: (_) =>
                      LibraryScreen(items: _items, scope: BrowseScope.movies),
                ),
              ],
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.byType(AppShell), findsOneWidget);
        trace.add('shell:${size.width.toInt()}x${size.height.toInt()}');

        // Same command by touch/click and by keyboard on the same card.
        final card = find.byKey(const ValueKey<String>('acc-1'));
        await tester.scrollUntilVisible(
          card,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(card);
        await tester.pump();
        expect(trace.last, 'open:acc-1');
        expect(tester.takeException(), isNull);

        // Tab switch keeps the shell; every form factor uses the menu panel.
        if (compact) {
          await tester.tap(find.byKey(const ValueKey<String>('menu-pill')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey<String>('menu-item-library')),
          );
          await tester.pumpAndSettle();
          trace.add('tab:library');
          expect(
            tester
                .widget<Stack>(
                  find.byKey(const ValueKey<String>('shell-content-stack')),
                )
                .children
                .indexWhere((c) => c is Offstage && !c.offstage),
            1,
          );
        }

        // Back priority last resort: nothing to pop, so the app is asked to exit.
        await tester.binding.handlePopRoute();
        await tester.pump();

        // Player on the same controller; one surface while time/panels update.
        navKey.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerScreen(
              controller: controller,
              videoSurface: _CountingSurface(() => surfaces++),
              setSystemUiMode: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (var i = 1; i <= 5; i++) {
          controller.advanceTo(Duration(seconds: i * 10));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(surfaces, 1);
        trace.add('player:surfaces=$surfaces');
        expect(find.byType(PlayerScreen), findsOneWidget);

        // Non-flat pixels at this viewport.
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first,
        );
        final colors = await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 0.2);
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final set = <int>{
            for (var i = 0; i < bytes.lengthInBytes; i += 4) bytes.getUint32(i),
          };
          image.dispose();
          return set.length;
        });
        expect(colors, greaterThan(3));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            'goldens/acceptance_player_${size.width.toInt()}x${size.height.toInt()}.png',
          ),
        );

        // Trace is complete and ordered; no exceptions; no extra exits.
        expect(trace.where((e) => e.startsWith('open:')), ['open:acc-1']);
        expect(trace, [
          'shell:${size.width.toInt()}x${size.height.toInt()}',
          'open:acc-1',
          if (compact) 'tab:library',
          'exit',
          'player:surfaces=1',
        ]);
        expect(tester.takeException(), isNull);
        expect(exits, 1);

        await tester.pumpWidget(const SizedBox());
        model.dispose();
        await controller.dispose();
      },
    );
  }
}
