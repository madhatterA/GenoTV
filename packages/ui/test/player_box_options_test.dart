import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:ui/src/player/player_box_options.dart';

import 'dart:async';

class _Surface extends FakeVideoSurface {
  int builds = 0;
  @override
  Widget build(
    BuildContext context,
    PlaybackController controller, {
    BoxFit fit = BoxFit.contain,
    Color background = const Color(0xFF000000),
  }) {
    builds++;
    return const ColoredBox(color: Color(0xFF243448));
  }
}

class _Player extends FakePlaybackController {
  Uri? external;
  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {
    external = uri;
  }

  Object? subtitleDelayFailure;
  Future<void>? delayGate;
  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    if (subtitleDelayFailure case final failure?) throw failure;
    await super.setSubtitleDelay(delay);
    await delayGate;
  }
}

Future<(_Player, _Surface)> _mount(
  WidgetTester tester, {
  FormFactor form = FormFactor.desktop,
  Size size = const Size(1280, 800),
  double defaultSubtitleScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final player = _Player();
  player.setDuration(const Duration(minutes: 2));
  player.setTracks(
    const TrackList(
      audio: [
        Track(id: 'a1', type: TrackType.audio, title: 'English audio'),
        Track(id: 'a2', type: TrackType.audio, title: 'Persian audio'),
      ],
      subtitle: [
        Track(id: 's1', type: TrackType.subtitle, title: 'English captions'),
        Track(id: 's2', type: TrackType.subtitle, title: 'Persian captions'),
      ],
    ),
  );
  await player.selectTrack(
    const TrackSelection(
      audio: TrackChoice.specific('a1'),
      subtitle: TrackChoice.off(),
    ),
  );
  await player.play();
  final surface = _Surface();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      theme: AppTheme.dark(tv: false),
      debugShowCheckedModeBanner: false,
      home: PlayerScreen(
        controller: player,
        videoSurface: surface,
        formFactor: form,
        title: 'Sample film',
        defaultSubtitleScale: defaultSubtitleScale,
        setSystemUiMode: (_) async {},
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
  addTearDown(player.dispose);
  return (player, surface);
}

Finder _button(String name) => find.byKey(ValueKey('player-box-$name'));
Future<void> _open(WidgetTester tester, String name) async {
  await tester.tap(_button(name));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('Info tab shows live media facts and omits unknowns', (
    tester,
  ) async {
    final (player, _) = await _mount(tester, size: const Size(1280, 800));
    player.emitMediaInfo(
      const MediaInfo(
        container: 'mp4',
        fileSizeBytes: 734003200,
        duration: Duration(minutes: 42, seconds: 7),
        bitrate: 2400000,
        videoCodec: 'hevc',
        width: 3840,
        height: 2160,
        frameRate: 23.976,
        bitDepth: 10,
        colorTransfer: 'pq',
        audioCodec: 'eac3',
        audioChannelLayout: '5.1(side)',
        audioSampleRate: 48000,
      ),
    );
    await _open(tester, 'options');
    await tester.tap(find.byKey(const ValueKey('options-section-Info')));
    await tester.pumpAndSettle();
    expect(
      find.text('HEVC · 3840×2160 · 23.976 fps · 10-bit · HDR10'),
      findsOneWidget,
    );
    expect(find.text('EAC3 · 5.1 · 48 kHz'), findsOneWidget);
    expect(find.text('Subtitle'), findsNothing);
    await expectLater(
      find.byType(PlayerScreen),
      matchesGoldenFile('goldens/player_box_desktop_info.png'),
    );
  });

  testWidgets('pending options survive reopen without losing another choice', (
    tester,
  ) async {
    final (player, _) = await _mount(tester);
    final gate = Completer<void>();
    player.delayGate = gate.future;
    await _open(tester, 'options');
    await tester.tap(find.byKey(const ValueKey('subtitle-delay-plus')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _open(tester, 'options');
    await tester.tap(find.byKey(const ValueKey('subtitle-size-Large')));
    await tester.pumpAndSettle();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Delay 0.1 s'), findsOneWidget);
    expect(
      tester
          .widget<PanelRow>(find.byKey(const ValueKey('subtitle-size-Large')))
          .selected,
      true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delay bounds disable the next step and Reset clears each delay',
    (tester) async {
      final (player, _) = await _mount(tester);
      await _open(tester, 'options');
      final options = tester
          .widget<PlayerBoxOptions>(find.byType(PlayerBoxOptions))
          .options;
      for (final subtitle in [true, false]) {
        if (!subtitle) {
          await tester.tap(find.byKey(const ValueKey('options-section-Audio')));
          await tester.pumpAndSettle();
        }
        final prefix = subtitle ? 'subtitle-delay' : 'audio-delay';
        final limit = subtitle ? 10000 : 5000;
        for (final bound in [-limit, limit]) {
          options.value = subtitle
              ? options.value.copyWith(subtitleDelay: bound)
              : options.value.copyWith(audioDelay: bound);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<IconButton>(
                  find.byKey(
                    ValueKey('$prefix-${bound < 0 ? 'minus' : 'plus'}'),
                  ),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.byKey(ValueKey('$prefix-reset')));
          await tester.pumpAndSettle();
          expect(
            subtitle
                ? player.recordedSubtitleDelays.last
                : player.recordedAudioDelays.last,
            Duration.zero,
          );
        }
      }
    },
  );

  testWidgets('failed option leaves its previous value and shows the failure', (
    tester,
  ) async {
    final (player, _) = await _mount(tester);
    player.subtitleDelayFailure = StateError('option rejected');
    await _open(tester, 'options');
    await tester.tap(find.byKey(const ValueKey('subtitle-delay-plus')));
    await tester.pumpAndSettle();
    expect(find.text('Delay 0.0 s'), findsOneWidget);
    expect(find.textContaining('option rejected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'default subtitle size is shown selected and survives a new video',
    (tester) async {
      final (player, _) = await _mount(tester, defaultSubtitleScale: 1.25);
      await _open(tester, 'options');
      bool large() => tester
          .widget<PanelRow>(find.byKey(const ValueKey('subtitle-size-Large')))
          .selected;
      expect(large(), true);
      await player.open(Uri.parse('file:///second-video.mp4'));
      await tester.pumpAndSettle();
      expect(large(), true);
    },
  );

  testWidgets('choices survive panel reopen and reset on another video', (
    tester,
  ) async {
    final (player, _) = await _mount(tester);
    await _open(tester, 'options');
    await tester.tap(find.byKey(const ValueKey('subtitle-delay-plus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subtitle-size-Large')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await _open(tester, 'options');
    expect(find.text('Delay 0.1 s'), findsOneWidget);
    expect(
      tester
          .widget<PanelRow>(find.byKey(const ValueKey('subtitle-size-Large')))
          .selected,
      true,
    );
    await player.open(Uri.parse('file:///second-video.mp4'));
    await tester.pumpAndSettle();
    expect(find.text('Delay 0.0 s'), findsOneWidget);
    expect(
      tester
          .widget<PanelRow>(find.byKey(const ValueKey('subtitle-size-Normal')))
          .selected,
      true,
    );
    await tester.tap(find.byKey(const ValueKey('options-section-Video')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PanelRow>(find.byKey(const ValueKey('aspect-Auto')))
          .selected,
      true,
    );
    expect(
      tester.widget<Switch>(find.byKey(const ValueKey('fill-screen'))).value,
      false,
    );
  });

  for (final form in [FormFactor.desktop, FormFactor.tv]) {
    testWidgets('live options keyboard/remote activation ${form.name}', (
      tester,
    ) async {
      final (player, _) = await _mount(tester, form: form);
      await _open(tester, 'options');
      for (final key in [
        'subtitle-size-Large',
        'subtitle-position-Raised',
        'download-subtitles',
      ]) {
        final target = find.byKey(ValueKey(key));
        await tester.ensureVisible(target);
        final focus = tester
            .widget<Focus>(
              find.descendant(of: target, matching: find.byType(Focus)).first,
            )
            .focusNode!;
        focus.requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(
          form == FormFactor.tv
              ? LogicalKeyboardKey.select
              : LogicalKeyboardKey.enter,
        );
        await tester.pumpAndSettle();
      }
      expect(player.recordedSubtitleScales.last, 1.25);
      expect(player.recordedSubtitlePositions.last, 85);
      expect(find.text('No subtitle sources yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('options-section-Video')));
      await tester.pumpAndSettle();
      final target = find.byKey(const ValueKey('aspect-4:3'));
      final focus = tester
          .widget<Focus>(
            find.descendant(of: target, matching: find.byType(Focus)).first,
          )
          .focusNode!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(player.recordedAspectRatios.last, '4:3');
      expect(tester.takeException(), isNull);
    });
    testWidgets('golden ${form.name} video options', (tester) async {
      await _mount(
        tester,
        form: form,
        size: form == FormFactor.tv
            ? const Size(1920, 1080)
            : const Size(1280, 800),
      );
      await _open(tester, 'options');
      await tester.tap(find.byKey(const ValueKey('options-section-Video')));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(PlayerScreen),
        matchesGoldenFile('goldens/player_box_${form.name}_video_options.png'),
      );
    });
  }

  testWidgets('live subtitle/audio/video options and empty download panel', (
    tester,
  ) async {
    final (player, _) = await _mount(tester);
    await _open(tester, 'options');
    Future<void> tap(String key) async {
      final target = find.byKey(ValueKey(key));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tap('subtitle-delay-plus');
    expect(
      player.recordedSubtitleDelays.last,
      const Duration(milliseconds: 100),
    );
    await tap('subtitle-delay-minus');
    expect(player.recordedSubtitleDelays.last, Duration.zero);
    await tap('subtitle-delay-reset');
    expect(player.recordedSubtitleDelays.last, Duration.zero);
    for (final entry in {
      'Small': 0.75,
      'Normal': 1.0,
      'Large': 1.25,
      'Extra large': 1.5,
    }.entries) {
      await tap('subtitle-size-${entry.key}');
      expect(player.recordedSubtitleScales.last, entry.value);
    }
    await tap('subtitle-position-Raised');
    expect(player.recordedSubtitlePositions.last, 85);
    await tap('subtitle-position-Bottom');
    expect(player.recordedSubtitlePositions.last, 100);
    await tap('download-subtitles');
    expect(find.text('No subtitle sources yet'), findsOneWidget);
    await tap('subtitle-sources-back');
    await tap('options-section-Audio');
    await tap('audio-delay-minus');
    expect(player.recordedAudioDelays.last, const Duration(milliseconds: -50));
    await tap('audio-delay-plus');
    expect(player.recordedAudioDelays.last, Duration.zero);
    await tap('audio-delay-reset');
    expect(player.recordedAudioDelays.last, Duration.zero);
    await tap('options-section-Video');
    for (final ratio in ['16:9', '4:3', '21:9', '2.39:1', 'Auto']) {
      await tap('aspect-$ratio');
      expect(player.recordedAspectRatios.last, ratio == 'Auto' ? null : ratio);
    }
    await tap('fill-screen');
    expect(player.recordedFillScreen.last, true);
    await tap('fill-screen');
    expect(player.recordedFillScreen.last, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop volume keeps its normal size at medium and narrow widths',
    (tester) async {
      for (final width in [1000.0, 480.0, 800.0, 1920.0]) {
        await _mount(tester, size: Size(width, 800));
        final volume = find.byKey(const ValueKey('player-volume'));
        final icon = find.descendant(
          of: volume,
          matching: find.byIcon(Icons.volume_up),
        );
        final slider = find.descendant(
          of: volume,
          matching: find.byType(Slider),
        );
        expect(
          tester.getRect(icon).width,
          closeTo(18, 0.01),
          reason: 'window $width',
        );
        expect(
          tester.getRect(icon).height,
          closeTo(18, 0.01),
          reason: 'window $width',
        );
        expect(
          tester.getRect(slider).width,
          greaterThanOrEqualTo(90),
          reason: 'window $width',
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );
  testWidgets('golden desktop medium volume', (tester) async {
    await _mount(tester, size: const Size(1000, 800));
    await expectLater(
      find.byType(PlayerScreen),
      matchesGoldenFile('goldens/player_box_desktop_medium.png'),
    );
  });
  for (final form in FormFactor.values) {
    testWidgets('top bar and ordered box controls: ${form.name}', (
      tester,
    ) async {
      await _mount(tester, form: form);
      expect(find.byKey(const ValueKey('open-player-overlay')), findsNothing);
      final points = [
        'subtitles',
        'audio',
        'options',
      ].map((s) => tester.getCenter(_button(s))).toList();
      expect(points[0].dx, lessThan(points[1].dx));
      expect(points[1].dx, lessThan(points[2].dx));
      for (final name in ['subtitles', 'audio', 'options']) {
        expect(tester.getTopLeft(_button(name)).dy, greaterThan(400));
      }
    });
  }
  testWidgets('quick lists select, check current choice, anchor and close', (
    tester,
  ) async {
    final (player, _) = await _mount(tester);
    await _open(tester, 'subtitles');
    expect(find.text('Subtitles'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Off')).dy,
      lessThan(tester.getTopLeft(find.text('English captions')).dy),
    );
    expect(
      tester.getBottomRight(find.byKey(const ValueKey('player-panel-host'))).dy,
      lessThan(tester.getTopLeft(_button('subtitles')).dy),
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Persian captions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      player.currentState.selected.subtitle,
      const TrackChoice.specific('s2'),
    );
    expect(find.byKey(const ValueKey('player-overlay')), findsNothing);
    await _open(tester, 'audio');
    expect(find.text('Off'), findsNothing);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await tester.tap(find.text('Persian audio'));
    await tester.pumpAndSettle();
    expect(
      player.currentState.selected.audio,
      const TrackChoice.specific('a2'),
    );
  });
  testWidgets(
    'Options reuses tracks and info, adds subtitle and changes speed',
    (tester) async {
      final (player, surface) = await _mount(tester);
      await _open(tester, 'options');
      for (final title in [
        'Options',
        'Subtitles',
        'Audio',
        'Playback',
        'Info',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Source'), findsNothing);
      expect(find.byType(TrackPanel), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('external-subtitle-uri')),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('options-list-Subtitles')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.enterText(
        find.byKey(const ValueKey('external-subtitle-uri')),
        'https://example.com/captions.srt',
      );
      await tester.ensureVisible(find.text('Add external subtitle'));
      await tester.tap(find.text('Add external subtitle'));
      await tester.pump();
      expect(player.external, Uri.parse('https://example.com/captions.srt'));
      await tester.tap(find.byKey(const ValueKey('options-section-Playback')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('1.5×'),
        80,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.5×'));
      await tester.pump();
      expect(player.currentState.rate, 1.5);
      await tester.tap(find.byKey(const ValueKey('options-section-Info')));
      await tester.pump();
      expect(find.byType(InfoPanel), findsOneWidget);
      expect(player.currentState.isPlaying, isTrue);
      expect(surface.builds, 1);
    },
  );
  for (final form in [FormFactor.desktop, FormFactor.tv]) {
    testWidgets(
      'Escape and Back restore opener, panels suppress hide: ${form.name}',
      (tester) async {
        await _mount(tester, form: form);
        for (final name in ['subtitles', 'audio', 'options']) {
          final opener = tester
              .widget<TransportControlButton>(_button(name))
              .focusNode!;
          opener.requestFocus();
          await tester.pump();
          expect(opener.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 6));
          expect(_button(name).hitTestable(), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('player-overlay')), findsNothing);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'player-box-$name',
          );
          await _open(tester, name);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('player-overlay')), findsNothing);
          expect(
            FocusManager.instance.primaryFocus?.debugLabel,
            'player-box-$name',
          );
        }
      },
    );
  }

  for (final form in [FormFactor.desktop, FormFactor.tv]) {
    testWidgets(
      'quick rows accept keyboard focus and selection: ${form.name}',
      (tester) async {
        final (player, _) = await _mount(tester, form: form);
        for (final panel in ['subtitles', 'audio']) {
          final rows = panel == 'subtitles'
              ? ['subtitle-off', 'track-s1', 'track-s2']
              : ['track-a1', 'track-a2'];
          for (final row in rows) {
            await _open(tester, panel);
            final focus = tester
                .widget<Focus>(
                  find
                      .descendant(
                        of: find.byKey(ValueKey(row)),
                        matching: find.byType(Focus),
                      )
                      .first,
                )
                .focusNode!;
            expect(focus.canRequestFocus, isTrue);
            focus.requestFocus();
            await tester.pump();
            expect(focus.hasPrimaryFocus, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('player-overlay')), findsNothing);
            expect(
              panel == 'subtitles'
                  ? player.currentState.selected.subtitle
                  : player.currentState.selected.audio,
              row == 'subtitle-off'
                  ? const TrackChoice.off()
                  : TrackChoice.specific(row.substring(6)),
            );
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'player-box-$panel',
            );
          }
        }
      },
    );
  }

  for (final form in [FormFactor.desktop, FormFactor.tv]) {
    testWidgets(
      'panels anchor horizontally to laid-out openers: ${form.name}',
      (tester) async {
        await _mount(
          tester,
          form: form,
          size: form == FormFactor.tv
              ? const Size(1920, 1080)
              : const Size(1280, 800),
        );
        for (final panel in ['subtitles', 'audio', 'options']) {
          await _open(tester, panel);
          final rect = tester.getRect(
            find.byKey(const ValueKey('player-panel-host')),
          );
          final opener = tester.getRect(_button(panel));
          if (panel == 'options') {
            expect(rect.right, closeTo(opener.right, 1));
          } else {
            final size =
                tester.view.physicalSize / tester.view.devicePixelRatio;
            expect(
              rect.left,
              closeTo(
                opener.left.clamp(
                  PlayerPanelGeometry.edgeInset,
                  size.width - rect.width - PlayerPanelGeometry.edgeInset,
                ),
                1,
              ),
            );
            final lastRow = find.byKey(
              ValueKey(panel == 'subtitles' ? 'track-s2' : 'track-a2'),
            );
            expect(
              rect.bottom - tester.getRect(lastRow).bottom,
              closeTo(PlayerPanelGeometry.padding, 1),
            );
            expect(
              tester
                  .state<ScrollableState>(find.byType(Scrollable).last)
                  .position
                  .maxScrollExtent,
              0,
            );
          }
          expect(rect.bottom, lessThan(opener.top));
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('Options compact rows and visibly selected sections', (
    tester,
  ) async {
    await _mount(tester);
    await _open(tester, 'options');
    for (final section in ['Subtitles', 'Audio']) {
      await tester.tap(find.byKey(ValueKey('options-section-$section')));
      await tester.pump();
      final panel = tester.widget<TrackPanel>(find.byType(TrackPanel));
      expect(panel.compact, isTrue);
      for (final name in ['Subtitles', 'Audio', 'Playback', 'Info']) {
        final row = tester.widget<PanelRow>(
          find.byKey(ValueKey('options-section-$name')),
        );
        expect(row.selected, name == section);
      }
      final track = tester.widget<Text>(
        find.text(
          section == 'Subtitles' ? 'English captions' : 'English audio',
        ),
      );
      expect(track.style?.fontSize, 16);
    }
  });

  testWidgets('long quick lists scroll inside the screen', (tester) async {
    final (player, _) = await _mount(tester);
    player.setTracks(
      TrackList(
        audio: const [],
        subtitle: [
          for (var i = 0; i < 20; i++)
            Track(
              id: 'long-$i',
              type: TrackType.subtitle,
              title: 'Subtitle $i',
            ),
        ],
      ),
    );
    await tester.pump();
    await _open(tester, 'subtitles');
    final rect = tester.getRect(
      find.byKey(const ValueKey('player-panel-host')),
    );
    expect(rect.height, lessThanOrEqualTo(400));
    expect(rect.bottom, lessThan(tester.getTopLeft(_button('subtitles')).dy));
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.scrollUntilVisible(
      find.text('Subtitle 19'),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Subtitle 19').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small Options and switching open panels stay usable', (
    tester,
  ) async {
    await _mount(tester, size: const Size(480, 480));
    await _open(tester, 'subtitles');
    await _open(tester, 'audio');
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
    await _open(tester, 'options');
    expect(find.text('Options'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close player'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-overlay')), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'player-box-options',
    );
  });

  for (final form in [FormFactor.desktop, FormFactor.tv]) {
    for (final panel in ['rest', 'subtitles', 'audio', 'options']) {
      testWidgets('golden ${form.name} $panel', (tester) async {
        await _mount(
          tester,
          form: form,
          size: form == FormFactor.tv
              ? const Size(1920, 1080)
              : const Size(1280, 800),
        );
        if (panel != 'rest') await _open(tester, panel);
        await expectLater(
          find.byType(PlayerScreen),
          matchesGoldenFile('goldens/player_box_${form.name}_$panel.png'),
        );
      });
    }
  }
}
