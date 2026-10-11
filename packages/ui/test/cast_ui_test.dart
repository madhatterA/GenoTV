import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/surface_size.dart';

class _FakeCast implements CastUiController {
  @override
  final ValueNotifier<CastUiState> state = ValueNotifier<CastUiState>(
    const CastUiState(
      targets: <CastTarget>[
        CastTarget(id: 'a', name: 'Living Room TV', playable: true),
        CastTarget(id: 'b', name: 'Bedroom Chromecast', playable: false),
      ],
    ),
  );
  final calls = <String>[];

  @override
  Future<void> startDiscovery() async => calls.add('discover');
  @override
  Future<void> stopDiscovery() async => calls.add('stopDiscovery');
  @override
  Future<void> cast(String id) async => calls.add('cast:$id');
  @override
  Future<void> play() async => calls.add('play');
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> seek(Duration p) async => calls.add('seek:${p.inSeconds}');
  @override
  Future<void> stop() async => calls.add('stop');
}

Future<_FakeCast> _pump(WidgetTester tester, Size size, FormFactor form) async {
  await setLogicalSize(tester, size);
  final cast = _FakeCast();
  final player = FakePlaybackController()
    ..setDuration(const Duration(minutes: 2));
  await player.play();
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [AppStrings.delegate],
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: false),
      home: PlayerScreen(
        controller: player,
        videoSurface: FakeVideoSurface(),
        setSystemUiMode: (_) async {},
        formFactor: form,
        title: 'Iron Man 3',
        cast: cast,
      ),
    ),
  );
  await tester.pump();
  return cast;
}

void main() {
  const desktop = Size(1280, 800);
  const tv = Size(1920, 1080);
  final button = find.byKey(const ValueKey<String>('cast-button'));

  testWidgets('no cast controller: no cast button', (tester) async {
    await setLogicalSize(tester, desktop);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [AppStrings.delegate],
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark(tv: false),
        home: PlayerScreen(
          controller: FakePlaybackController(),
          videoSurface: FakeVideoSurface(),
          setSystemUiMode: (_) async {},
          formFactor: FormFactor.desktop,
        ),
      ),
    );
    await tester.pump();
    expect(button, findsNothing);
  });

  testWidgets(
    'picker: playable casts, not-compatible is disabled with message',
    (tester) async {
      final cast = await _pump(tester, desktop, FormFactor.desktop);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(cast.calls, ['discover']);
      expect(find.text("This device can't play this file"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('cast-target-b')));
      await tester.pumpAndSettle();
      expect(cast.calls, [
        'discover',
      ], reason: 'incompatible TV is not castable');
      expect(
        find.byType(CastPicker),
        findsOneWidget,
        reason: 'picker stays open',
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/cast_picker_desktop.png'),
      );
      await tester.tap(find.byKey(const ValueKey<String>('cast-target-a')));
      await tester.pumpAndSettle();
      expect(cast.calls, ['discover', 'cast:a', 'stopDiscovery']);
    },
  );

  testWidgets('AirPlay: route picker is an entry in the same picker', (
    tester,
  ) async {
    final created = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') created.add(call.arguments);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    final cast = await _pump(tester, desktop, FormFactor.desktop);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('cast-airplay-row')),
      findsNothing,
    );

    cast.state.value = const CastUiState(airPlayAvailable: true);
    await tester.pumpAndSettle();
    expect(find.text('AirPlay'), findsOneWidget);
    expect(find.byType(AppKitView), findsOneWidget);
    expect(created.single, isA<Map<Object?, Object?>>());
    expect(
      (created.single! as Map<Object?, Object?>)['viewType'],
      airPlayRoutePickerViewType,
    );

    // A file AirPlay cannot play: row stays, says so, no route button.
    cast.state.value = const CastUiState(
      airPlayAvailable: true,
      airPlayPlayable: false,
    );
    await tester.pumpAndSettle();
    expect(find.text('AirPlay'), findsOneWidget);
    expect(find.text("This device can't play this file"), findsOneWidget);
    expect(find.byType(AppKitView), findsNothing);

    // The native button starts casting without a row tap: the picker closes.
    cast.state.value = const CastUiState(
      castingTo: 'AirPlay',
      airPlayAvailable: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CastPicker), findsNothing);
    expect(find.text('Casting to AirPlay'), findsOneWidget);
  });

  testWidgets('casting chrome: shows target, play/pause, seek, stop', (
    tester,
  ) async {
    final cast = await _pump(tester, desktop, FormFactor.desktop);
    cast.state.value = const CastUiState(
      castingTo: 'Living Room TV',
      isPlaying: true,
      position: Duration(minutes: 2),
      duration: Duration(minutes: 10),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Casting to Living Room TV'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('cast-play-pause')));
    await tester.tap(find.byKey(const ValueKey<String>('cast-stop')));
    await tester.pump();
    expect(cast.calls, ['pause', 'stop']);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<String>('casting-chrome')),
        matching: find.byType(Slider),
      ),
    );
    await tester.pump();
    expect(cast.calls.last, startsWith('seek:'));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cast_casting_desktop.png'),
    );
  });

  testWidgets('TV goldens: picker and casting', (tester) async {
    final cast = await _pump(tester, tv, FormFactor.tv);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cast_picker_tv.png'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('cast-target-a')));
    await tester.pumpAndSettle();
    cast.state.value = const CastUiState(
      castingTo: 'Living Room TV',
      position: Duration(minutes: 2),
      duration: Duration(minutes: 10),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/cast_casting_tv.png'),
    );
  });

  testWidgets('desktop pill keeps all action buttons on one row', (
    tester,
  ) async {
    await _pump(tester, desktop, FormFactor.desktop);
    double top(String k) =>
        tester.getTopLeft(find.byKey(ValueKey<String>(k))).dy;
    final castTop = top('cast-button');
    for (final k in [
      'player-box-subtitles',
      'player-box-audio',
      'player-box-options',
    ]) {
      expect(top(k), castTop, reason: '$k on the cast button\'s row');
    }
    // Volume sits on that row too, not on a wrapped second one.
    expect(
      tester.getCenter(find.byKey(const ValueKey<String>('player-volume'))).dy,
      closeTo(tester.getCenter(button).dy, 1),
    );
  });

  testWidgets('picker sits directly above the cast button, like Subtitles', (
    tester,
  ) async {
    await _pump(tester, desktop, FormFactor.desktop);
    await tester.tap(button);
    await tester.pumpAndSettle();
    final panel = tester.getRect(
      find.byKey(const ValueKey<String>('player-panel-host')),
    );
    final opener = tester.getRect(button);
    expect(panel.bottom, lessThanOrEqualTo(opener.top));
    expect(opener.top - panel.bottom, lessThan(40));
    expect(panel.left, closeTo(opener.left, 1));
  });

  testWidgets('keyboard: rows in order, Enter selects, Escape returns focus', (
    tester,
  ) async {
    final cast = await _pump(tester, desktop, FormFactor.desktop);
    await tester.tap(button);
    await tester.pumpAndSettle();
    FocusNode? focused() => FocusManager.instance.primaryFocus;
    bool onRow(String id) =>
        focused()!.context!.findAncestorWidgetOfExactType<AppRow>()?.key ==
        ValueKey<String>('cast-target-$id');
    expect(onRow('a'), isTrue, reason: 'first row focused first');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(onRow('b'), isTrue, reason: 'second row follows');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CastPicker), findsNothing);
    expect(
      focused()!.context!.findAncestorWidgetOfExactType<CastButton>(),
      isNotNull,
      reason: 'focus returns to the cast button',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(CastPicker), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(cast.calls, contains('cast:a'));
    expect(find.byType(CastPicker), findsNothing);
  });

  testWidgets('a checking target reads Checking…, not can\'t play', (
    tester,
  ) async {
    final cast = await _pump(tester, desktop, FormFactor.desktop);
    cast.state.value = const CastUiState(
      targets: <CastTarget>[
        CastTarget(
          id: 'a',
          name: 'Living Room TV',
          playable: false,
          checking: true,
        ),
      ],
    );
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Checking…'), findsOneWidget);
    expect(find.text("This device can't play this file"), findsNothing);
  });
}
