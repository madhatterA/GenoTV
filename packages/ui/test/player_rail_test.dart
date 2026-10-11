import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/fixture_artwork.dart';
import 'support/surface_size.dart';

// Phase 02 (planning/part-04-ui/chapter-03-player-ui/phase-02-transport-controls.md)
// proof file: PlayerControlRail (rail glass + metadata + progress row +
// secondary action buttons), TransportControlButton (focus/long-press),
// RailFocusMemory (default/remembered/fallback focus, ported from
// PlayerRailView.swift's preferredFocusEnvironments/didUpdateFocus).

class _FixtureVideoSurface extends FakeVideoSurface {
  const _FixtureVideoSurface();

  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.cover,
    Color background = const Color(0xFF000000),
  }) {
    final resolver = ArtworkResolverScope.of(context);
    return ColoredBox(
      color: background,
      child: Image(
        image: resolver('https://example.invalid/player/backdrop.jpg?ar=land'),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: const [AppStrings.delegate],
  theme: AppTheme.dark(tv: false),
  home: Scaffold(body: Center(child: child)),
);

FakePlaybackController _controllerAt(Duration position, Duration duration) =>
    FakePlaybackController()
      ..setDuration(duration)
      ..advanceTo(position);

void main() {
  group('RailFocusMemory', () {
    test('no remembered button: scrubber wins when available', () {
      final memory = RailFocusMemory();
      final target = memory.resolve(
        visible: const [RailAction.subtitles, RailAction.audio],
        defaultAction: RailAction.subtitles,
      );
      expect(target, RailFocusTarget.scrubber);
    });

    test('no scrubber: falls back to the default action', () {
      final memory = RailFocusMemory();
      final target = memory.resolve(
        visible: const [RailAction.audio, RailAction.info],
        defaultAction: RailAction.info,
        scrubberAvailable: false,
      );
      expect(target, RailFocusTarget.info);
    });

    test('no scrubber, default not visible: falls back to first visible', () {
      final memory = RailFocusMemory();
      final target = memory.resolve(
        visible: const [RailAction.upNext],
        defaultAction: RailAction.subtitles,
        scrubberAvailable: false,
      );
      expect(target, RailFocusTarget.upNext);
    });

    test('remembered button wins over the scrubber on reopen', () {
      final memory = RailFocusMemory()..remember(RailFocusTarget.info);
      final target = memory.resolve(
        visible: const [RailAction.subtitles, RailAction.info],
        defaultAction: RailAction.subtitles,
      );
      expect(target, RailFocusTarget.info);
    });

    test('remembering the scrubber is a no-op (never remembered)', () {
      final memory = RailFocusMemory()..remember(RailFocusTarget.scrubber);
      expect(memory.remembered, isNull);
    });

    test('removed/disabled remembered target falls back through the chain', () {
      final memory = RailFocusMemory()..remember(RailFocusTarget.filter);
      // filter no longer visible, scrubber unavailable -> default.
      final target = memory.resolve(
        visible: const [RailAction.subtitles],
        defaultAction: RailAction.subtitles,
        scrubberAvailable: false,
      );
      expect(target, RailFocusTarget.subtitles);
    });

    test('reset drops the remembered button', () {
      final memory = RailFocusMemory()..remember(RailFocusTarget.audio);
      memory.reset();
      expect(memory.remembered, isNull);
      final target = memory.resolve(
        visible: const [RailAction.audio],
        defaultAction: RailAction.audio,
      );
      expect(target, RailFocusTarget.scrubber);
    });
  });

  group('PlayerControlRail geometry', () {
    testWidgets(
      'noncompact (TV/desktop): rail height, padding, radius, button diameter/gap',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'Iron Man 3',
                controller: _controllerAt(
                  const Duration(minutes: 36, seconds: 18),
                  const Duration(hours: 2, minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  position: const Duration(minutes: 36, seconds: 18),
                  duration: const Duration(hours: 2, minutes: 10),
                ),
                onSubtitles: () {},
                onAudio: () {},
              ),
            ),
          ),
        );
        final container = tester.widget<Container>(
          find.byKey(const ValueKey<String>('player-control-rail')),
        );
        expect(
          (container.constraints as BoxConstraints).minHeight,
          260,
        ); // PlayerRailView.swift:19
        final decoration = container.decoration! as BoxDecoration;
        expect(
          decoration.borderRadius,
          BorderRadius.circular(32),
        ); // PlayerRailView.swift:77
        expect(
          container.padding,
          const EdgeInsets.symmetric(horizontal: 42, vertical: 34),
        ); // :22-23

        final subtitles = tester.widget<TransportControlButton>(
          find.byKey(const ValueKey<String>('rail-action-subtitles')),
        );
        expect(subtitles.diameter, 74); // :26
        final gap =
            tester
                .getTopLeft(
                  find.byKey(const ValueKey<String>('rail-action-audio')),
                )
                .dx -
            tester
                .getTopRight(
                  find.byKey(const ValueKey<String>('rail-action-subtitles')),
                )
                .dx;
        expect(gap, closeTo(20, 0.5)); // :25 buttonGap
      },
    );

    testWidgets(
      'compact (touch/phone): padding 8x14, radius 24, dense button 36',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 700,
              child: PlayerControlRail(
                title: 'The Office',
                compact: true,
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 25, seconds: 48),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 25, seconds: 48),
                ),
                onSubtitles: () {},
              ),
            ),
          ),
        );
        final container = tester.widget<Container>(
          find.byKey(const ValueKey<String>('player-control-rail')),
        );
        expect(
          container.padding,
          const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.borderRadius, BorderRadius.circular(24));
        final subtitles = tester.widget<TransportControlButton>(
          find.byKey(const ValueKey<String>('rail-action-subtitles')),
        );
        expect(subtitles.diameter, 36);
      },
    );

    testWidgets('title/eyebrow/meta type sizes (noncompact)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 1200,
            child: PlayerMetadata(
              title: 'Iron Man 3',
              eyebrow: 'Now Playing',
              rating: 'PG-13',
              runtime: '2h 10m',
              audio: 'Atmos',
            ),
          ),
        ),
      );
      final title = tester.widget<AppText>(
        find.byKey(const ValueKey<String>('rail-title')),
      );
      expect(title.style!.fontSize, 38);
      expect(title.style!.fontWeight, FontWeight.bold);
      final chip = tester.getSize(
        find.byKey(const ValueKey<String>('rail-rating-chip')),
      );
      expect(chip.height, 28);
      expect(chip.width, greaterThanOrEqualTo(58));
      // Must hug its text, not stretch to fill the metadata column's width
      // (regression: `Align`/`Center` without `widthFactor` inside `Wrap`
      // fills the wrap's bounded max width — see player_metadata.dart).
      expect(chip.width, lessThan(120));
    });
  });

  group('PlayerControlRail action matrix', () {
    testWidgets('renders only actions with callbacks, in the fixed order', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 1200,
            child: PlayerControlRail(
              title: 'x',
              controller: _controllerAt(
                Duration.zero,
                const Duration(minutes: 10),
              ),
              state: PlaybackState.initial().copyWith(
                duration: const Duration(minutes: 10),
              ),
              onSubtitles: () {},
              onUpNext: () {},
              // audio/info/insights/filter intentionally unwired.
            ),
          ),
        ),
      );
      final state = tester.state<PlayerControlRailState>(
        find.byType(PlayerControlRail),
      );
      expect(state.traversalOrder, <RailAction>[
        RailAction.subtitles,
        RailAction.upNext,
      ]);
      expect(
        find.byKey(const ValueKey<String>('rail-action-subtitles')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-action-upNext')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-action-audio')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-action-info')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-action-insights')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('rail-action-filter')),
        findsNothing,
      );
    });

    testWidgets(
      'full action set renders in subtitles/audio/info/insights/upNext/filter order',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1400,
              child: PlayerControlRail(
                title: 'x',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                onAudio: () {},
                onInfo: () {},
                onInsights: () {},
                onUpNext: () {},
                onFilter: () {},
              ),
            ),
          ),
        );
        final state = tester.state<PlayerControlRailState>(
          find.byType(PlayerControlRail),
        );
        expect(state.traversalOrder, RailAction.values);
        // Left-to-right on-screen order matches the enum order exactly.
        final xs = [
          for (final action in RailAction.values)
            tester
                .getTopLeft(
                  find.byKey(ValueKey<String>('rail-action-${action.name}')),
                )
                .dx,
        ];
        expect(xs, List<double>.from(xs)..sort());
      },
    );

    testWidgets('no skip-back button anywhere in the rail', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 1200,
            child: PlayerControlRail(
              title: 'x',
              controller: _controllerAt(
                Duration.zero,
                const Duration(minutes: 10),
              ),
              state: PlaybackState.initial().copyWith(
                duration: const Duration(minutes: 10),
              ),
              onSubtitles: () {},
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.replay_10), findsNothing);
    });
  });

  group('Focus restoration end to end', () {
    testWidgets(
      'traversal list contains exactly the visible supported actions',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'x',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                onAudio: () {},
                onUpNext: () {},
              ),
            ),
          ),
        );
        final state = tester.state<PlayerControlRailState>(
          find.byType(PlayerControlRail),
        );
        expect(state.traversalOrder, <RailAction>[
          RailAction.subtitles,
          RailAction.audio,
          RailAction.upNext,
        ]);
      },
    );

    testWidgets(
      'focusing a button remembers it; it wins on the next resolve()',
      (tester) async {
        final memory = RailFocusMemory();
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'x',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                onAudio: () {},
                focusMemory: memory,
              ),
            ),
          ),
        );
        final audioFocusWidget = tester.widget<Focus>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('rail-action-audio')),
                matching: find.byType(Focus),
              )
              .first,
        );
        audioFocusWidget.focusNode!.requestFocus();
        await tester.pump();
        expect(memory.remembered, RailFocusTarget.audio);

        final state = tester.state<PlayerControlRailState>(
          find.byType(PlayerControlRail),
        );
        expect(
          state.resolveFocus(scrubberAvailable: false),
          RailFocusTarget.audio,
        );
      },
    );

    testWidgets('resetFocusMemory drops the remembered button', (tester) async {
      final memory = RailFocusMemory()..remember(RailFocusTarget.audio);
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 1200,
            child: PlayerControlRail(
              title: 'x',
              controller: _controllerAt(
                Duration.zero,
                const Duration(minutes: 10),
              ),
              state: PlaybackState.initial().copyWith(
                duration: const Duration(minutes: 10),
              ),
              onSubtitles: () {},
              onAudio: () {},
              focusMemory: memory,
            ),
          ),
        ),
      );
      final state = tester.state<PlayerControlRailState>(
        find.byType(PlayerControlRail),
      );
      state.resetFocusMemory();
      expect(memory.remembered, isNull);
    });
  });

  group('TransportControlButton', () {
    testWidgets(
      'focus scales to 1.15x, white bg, black icon (TransportControlButton.swift:141-143)',
      (tester) async {
        final node = FocusNode();
        await tester.pumpWidget(
          _wrap(
            TransportControlButton(
              icon: Icons.subtitles,
              semanticLabel: 'Subtitles',
              focusNode: node,
              onPress: () {},
            ),
          ),
        );
        node.requestFocus();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        final scaleFinder = find.descendant(
          of: find.byType(TransportControlButton),
          matching: find.byType(AnimatedScale),
        );
        expect(tester.widget<AnimatedScale>(scaleFinder).scale, 1.15);
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.color, Colors.black);
        node.dispose();
      },
    );

    testWidgets('release before 600ms fires onPress, not onLongPress', (
      tester,
    ) async {
      var pressed = 0;
      var longPressed = 0;
      await tester.pumpWidget(
        _wrap(
          TransportControlButton(
            icon: Icons.subtitles,
            semanticLabel: 'Subtitles',
            onPress: () => pressed++,
            onLongPress: () => longPressed++,
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TransportControlButton)),
      );
      await tester.pump(const Duration(milliseconds: 599));
      await gesture.up();
      await tester.pump();
      expect(pressed, 1);
      expect(longPressed, 0);
    });

    testWidgets('holding 600ms fires onLongPress and suppresses onPress', (
      tester,
    ) async {
      var pressed = 0;
      var longPressed = 0;
      await tester.pumpWidget(
        _wrap(
          TransportControlButton(
            icon: Icons.subtitles,
            semanticLabel: 'Subtitles',
            onPress: () => pressed++,
            onLongPress: () => longPressed++,
          ),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TransportControlButton)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pump();
      expect(longPressed, 1);
      expect(pressed, 0);
    });

    testWidgets(
      'rail long-press on subtitles triggers onReplayLongPress, not a second subtitles action',
      (tester) async {
        var subtitles = 0;
        var replay = 0;
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'x',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () => subtitles++,
                onReplayLongPress: () => replay++,
              ),
            ),
          ),
        );
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.byKey(const ValueKey<String>('rail-action-subtitles')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 650));
        await gesture.up();
        await tester.pump();
        expect(replay, 1);
        expect(subtitles, 0);
      },
    );

    testWidgets('semantics exposes a button with the given label', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          TransportControlButton(
            icon: Icons.subtitles,
            semanticLabel: 'Subtitles',
            onPress: () {},
          ),
        ),
      );
      expect(
        tester.getSemantics(find.byType(TransportControlButton)),
        matchesSemantics(
          label: 'Subtitles',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('Ambient pause', () {
    testWidgets(
      'ambient hides plate/metadata/buttons but keeps the title when keepTitleWhenAmbient',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'S05E08',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                ambient: true,
                keepTitleWhenAmbient: true,
              ),
            ),
          ),
        );
        final titleOpacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const ValueKey<String>('rail-title')),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(titleOpacity.opacity, 1.0);
      },
    );

    testWidgets(
      'ambient without keepTitleWhenAmbient (movie) hides the title too',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'Iron Man 3',
                controller: _controllerAt(
                  Duration.zero,
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                ambient: true,
              ),
            ),
          ),
        );
        final titleOpacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.byKey(const ValueKey<String>('rail-title')),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(titleOpacity.opacity, 0.0);
      },
    );
  });

  group('accessibility', () {
    testWidgets('lays out without overflow at 2x text scale', (tester) async {
      await setLogicalSize(tester, const Size(1400, 900));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: _wrap(
            SizedBox(
              width: 1200,
              child: PlayerControlRail(
                title: 'A Very Long Title That Could Wrap Awkwardly At Double Text Scale',
                eyebrow: 'Now Playing',
                rating: 'PG-13',
                runtime: '2h 10m',
                audio: 'Dolby Atmos 5.1',
                controller: _controllerAt(
                  const Duration(minutes: 5),
                  const Duration(minutes: 10),
                ),
                state: PlaybackState.initial().copyWith(
                  position: const Duration(minutes: 5),
                  duration: const Duration(minutes: 10),
                ),
                onSubtitles: () {},
                onAudio: () {},
                onInfo: () {},
                onUpNext: () {},
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Buttons must stay fully inside the rail's own width, even with a
      // long, wrapping title — primary actions never pushed off-screen.
      final railRight = tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('player-control-rail')),
          )
          .dx;
      final lastButtonRight = tester
          .getBottomRight(
            find.byKey(const ValueKey<String>('rail-action-upNext')),
          )
          .dx;
      expect(lastButtonRight, lessThanOrEqualTo(railRight + 0.5));
    });
  });

  group('goldens', () {
    Future<PlaybackController> pumpGolden(
      WidgetTester tester,
      Size size,
      String name, {
      required FormFactor formFactor,
      List<UiMarker> markers = const <UiMarker>[],
    }) async {
      final resolver = await loadFixtureArtworkResolver(tester);
      await setLogicalSize(tester, size);
      final controller = _controllerAt(
        const Duration(minutes: 36, seconds: 18),
        const Duration(hours: 1, minutes: 36),
      );
      await tester.pumpWidget(
        ArtworkResolverScope(
          resolver: resolver,
          child: MaterialApp(
            localizationsDelegates: const [AppStrings.delegate],
            theme: AppTheme.dark(tv: false),
            home: PlayerScreen(
              controller: controller,
              videoSurface: const _FixtureVideoSurface(),
              setSystemUiMode: (_) async {},
              formFactor: formFactor,
              title: 'Iron Man 3',
              rating: 'PG-13',
              runtimeLabel: '2h 10m',
              audioLabel: 'Atmos',
              markers: markers,
              onSubtitles: () {},
              onAudioTrack: () {},
              onInfo: () {},
              onUpNext: () {},
            ),
          ),
        ),
      );
      await controller.play();
      await tester.pump();
      await expectLater(
        find.byType(PlayerScreen),
        matchesGoldenFile('goldens/$name'),
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'no FlutterError/overflow while building $name',
      );
      return controller;
    }

    testWidgets('TV rail (plate-less, gradient scrim) at 1920x1080', (
      tester,
    ) async {
      final controller = await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_rail_tv_1920.png',
        formFactor: FormFactor.tv,
      );
      await controller.dispose();
    });

    testWidgets('TV rail with active skip marker at 1920x1080', (tester) async {
      final controller = await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_rail_skip_marker_1920.png',
        formFactor: FormFactor.tv,
        markers: const <UiMarker>[
          UiMarker(
            id: 'chapter',
            kind: UiMarkerKind.intro,
            start: Duration(minutes: 36),
            end: Duration(minutes: 38),
          ),
        ],
      );
      await controller.dispose();
    });

    testWidgets('desktop floating glass pill at 1920x1080', (tester) async {
      final controller = await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_rail_desktop_1920.png',
        formFactor: FormFactor.desktop,
      );
      await controller.dispose();
    });

    testWidgets('compact phone chrome at phone size', (tester) async {
      final controller = await pumpGolden(
        tester,
        const Size(844, 390),
        'player_rail_compact_844.png',
        formFactor: FormFactor.phone,
      );
      await controller.dispose();
    });

    testWidgets('phone chrome at 1920x1080 for Infuse comparison', (
      tester,
    ) async {
      final controller = await pumpGolden(
        tester,
        const Size(1920, 1080),
        'player_rail_phone_1920.png',
        formFactor: FormFactor.phone,
      );
      await controller.dispose();
    });
  });

  group('exactly one play-pause control per form factor', () {
    Future<void> pumpFormFactor(
      WidgetTester tester,
      Size size,
      FormFactor formFactor,
    ) async {
      await setLogicalSize(tester, size);
      final controller = _controllerAt(
        const Duration(minutes: 36, seconds: 18),
        const Duration(hours: 1, minutes: 36),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: false),
          home: PlayerScreen(
            controller: controller,
            videoSurface: const FakeVideoSurface(),
            setSystemUiMode: (_) async {},
            formFactor: formFactor,
            title: 'Iron Man 3',
            onSubtitles: () {},
            onAudioTrack: () {},
            onInfo: () {},
            onUpNext: () {},
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('tv', (tester) async {
      await pumpFormFactor(tester, const Size(1920, 1080), FormFactor.tv);
      expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    });

    testWidgets('desktop', (tester) async {
      await pumpFormFactor(tester, const Size(1920, 1080), FormFactor.desktop);
      expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    });

    testWidgets('phone', (tester) async {
      await pumpFormFactor(tester, const Size(844, 390), FormFactor.phone);
      expect(find.byKey(const ValueKey<String>('play-pause')), findsOneWidget);
    });
  });
}
