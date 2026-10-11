import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

const _tv = PlatformCapabilities.directionalPad();

Widget _shell(List<AppDestination> destinations) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: AdaptiveBehavior(
    capabilities: _tv,
    child: AppShell(activeId: 'a', destinations: destinations),
  ),
);

FocusNode? get _primary => FocusManager.instance.primaryFocus;

class _Surface extends FakeVideoSurface {
  @override
  Widget build(
    BuildContext context,
    controller, {
    BoxFit fit = BoxFit.contain,
    Color background = Colors.black,
  }) => const ColoredBox(color: Colors.black);
}

void main() {
  testWidgets('TV: Select on the hero Play pill activates it', (tester) async {
    var plays = 0;
    final node = FocusNode();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        theme: AppTheme.dark(tv: true),
        home: AdaptiveBehavior(
          capabilities: _tv,
          child: Scaffold(
            body: AppButton.primary(
              label: 'Play',
              icon: PhosphorIconsFill.play,
              focusNode: node,
              autofocus: true,
              onActivate: () => plays++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue, reason: 'Home lands on Play');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(plays, 1);
  });

  testWidgets('TV: Down leaves a nested focus scope for the next control', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 720));
    final top = FocusNode(debugLabel: 'top');
    final below = FocusNode(debugLabel: 'below');
    await tester.pumpWidget(
      _shell(<AppDestination>[
        AppDestination(
          id: 'a',
          label: 'a',
          icon: Icons.home,
          builder: (_) => Column(
            children: <Widget>[
              FocusScope(
                child: TextButton(
                  focusNode: top,
                  autofocus: true,
                  onPressed: () {},
                  child: const Text('top'),
                ),
              ),
              const Spacer(),
              TextButton(
                focusNode: below,
                onPressed: () {},
                child: const Text('below'),
              ),
            ],
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(top.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(below.hasPrimaryFocus, isTrue);
  });

  testWidgets('TV: cross-scope Up reveals an off-screen target', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 720));
    final top = FocusNode();
    final bottom = FocusNode();
    final scroll = ScrollController();
    await tester.pumpWidget(
      _shell(<AppDestination>[
        AppDestination(
          id: 'a',
          label: 'a',
          icon: Icons.home,
          builder: (_) => SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: <Widget>[
                FocusScope(
                  child: TextButton(
                    focusNode: top,
                    onPressed: () {},
                    child: const Text('top'),
                  ),
                ),
                const SizedBox(height: 1000),
                FocusScope(
                  child: TextButton(
                    focusNode: bottom,
                    onPressed: () {},
                    child: const Text('bottom'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    bottom.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(top.hasPrimaryFocus, isTrue);
    expect(top.rect.top, greaterThanOrEqualTo(0));
    await tester.pumpWidget(const SizedBox());
    top.dispose();
    bottom.dispose();
    scroll.dispose();
  });

  testWidgets('TV: a pushed page takes focus and popping restores it', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 720));
    final opener = FocusNode(debugLabel: 'opener');
    final inner = FocusNode(debugLabel: 'inner');
    await tester.pumpWidget(
      _shell(<AppDestination>[
        AppDestination(
          id: 'a',
          label: 'a',
          icon: Icons.home,
          builder: (context) => Center(
            child: TextButton(
              focusNode: opener,
              autofocus: true,
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => Center(
                    child: TextButton(
                      focusNode: inner,
                      onPressed: () {},
                      child: const Text('inner'),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(opener.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(inner.hasPrimaryFocus, isTrue);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(opener.hasPrimaryFocus, isTrue);
  });

  group('TV player', () {
    late FakePlaybackController controller;
    var exits = 0;

    Future<void> pumpPlayer(WidgetTester tester) async {
      exits = 0;
      await setLogicalSize(tester, const Size(1920, 1080));
      controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 2))
        ..advanceTo(const Duration(seconds: 60));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: AdaptiveBehavior(
            capabilities: _tv,
            child: PlayerScreen(
              controller: controller,
              videoSurface: _Surface(),
              setSystemUiMode: (_) async {},
              onExit: () => exits++,
            ),
          ),
        ),
      );
      await controller.play();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
    }

    testWidgets('Left/Right seek -10 s / +30 s even with controls hidden', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.recordedSeeks, <Duration>[
        const Duration(seconds: 90),
        const Duration(seconds: 90 - 10),
      ]);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });

    testWidgets('seek bar is remote-focusable and seeks -10 / +30 seconds', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_primary?.debugLabel, 'tv-seek-bar');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.recordedSeeks, <Duration>[
        const Duration(seconds: 90),
        const Duration(seconds: 80),
      ]);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });

    testWidgets('media play/pause key toggles playback', (tester) async {
      await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(controller.currentState.isPlaying, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(controller.currentState.isPlaying, isTrue);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });

    testWidgets('Down focuses a control, Select activates it', (tester) async {
      await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // reveal
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_primary?.debugLabel, isNot('player-surface'));
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(controller.currentState.isPlaying, isFalse);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });

    testWidgets('Back hides the controls first, then closes the player', (
      tester,
    ) async {
      await pumpPlayer(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp); // reveal
      await tester.pump();
      final surface = tester.widget<PlayerGestureSurface>(
        find.byType(PlayerGestureSurface),
      );
      expect(surface.chromeVisible, isTrue);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(
        tester
            .widget<PlayerGestureSurface>(find.byType(PlayerGestureSurface))
            .chromeVisible,
        isFalse,
      );
      expect(exits, 0);
      // DateTime.now() is real time: let the Back de-dup window lapse.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(seconds: 1));
      expect(exits, 1);
      await tester.pumpWidget(const SizedBox());
      await controller.dispose();
    });
  });
}
