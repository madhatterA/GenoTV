import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:contracts/fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:core/core.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'support/fixture_artwork.dart';

import 'package:ui/ui.dart';

const _factors = {
  'phone': (size: Size(400, 800), dpr: 1.0, factor: FormFactor.phone),
  'desktop': (size: Size(1280, 800), dpr: 1.0, factor: FormFactor.desktop),
  'tv': (size: Size(960, 540), dpr: 2.0, factor: FormFactor.tv),
};

void main() {
  const expected = {
    'phone': {
      'play-pause': [171, 371, 58, 58],
      'player-box-subtitles': [186, 670, 44, 44],
      'player-box-audio': [238, 670, 44, 44],
      'player-box-options': [290, 670, 44, 44],
      'player-box-stats': [342, 670, 44, 44],
      'seek': [14, 726, 372, 66],
    },
    'desktop': {
      'play-pause': [564, 608, 56, 56],
      'player-box-subtitles': [710, 614, 44, 44],
      'player-box-audio': [762, 614, 44, 44],
      'player-box-options': [814, 614, 44, 44],
      'player-box-stats': [866, 614, 44, 44],
      'seek': [369, 674, 542, 70],
    },
    'tv': {
      'play-pause': [496, 314, 74, 74],
      'player-box-subtitles': [598, 314, 74, 74],
      'player-box-audio': [680, 314, 74, 74],
      'player-box-options': [762, 314, 74, 74],
      'player-box-stats': [844, 314, 74, 74],
      'seek': [42, 408, 876, 75],
    },
  };
  for (final entry in _factors.entries) {
    testWidgets('player rects ${entry.key}', (tester) async {
      final factor = entry.value;
      tester.view.physicalSize = factor.size * factor.dpr;
      tester.view.devicePixelRatio = factor.dpr;
      addTearDown(tester.view.reset);
      final controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 96))
        ..advanceTo(const Duration(minutes: 36));
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [AppStrings.delegate],
          theme: AppTheme.dark(tv: factor.factor == FormFactor.tv),
          home: AdaptiveBehavior(
            capabilities: factor.factor == FormFactor.tv
                ? const PlatformCapabilities.directionalPad()
                : factor.factor == FormFactor.phone
                ? const PlatformCapabilities.touch()
                : const PlatformCapabilities(),
            child: PlayerScreen(
              controller: controller,
              videoSurface: const FakeVideoSurface(),
              formFactor: factor.factor,
              title: 'Iron Man 3',
              setSystemUiMode: (_) async {},
              stats: PlayerStatsSource(
                kind: SourceKind.httpUrl,
                readTransport: () async => const TransportStats(
                  downloadBytesPerSecond: 1,
                  downloadedBytes: 1,
                  totalBytes: 2,
                  connections: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      final rects = <String, List<double>>{};
      for (final key in [
        'play-pause',
        'player-box-subtitles',
        'player-box-audio',
        'player-box-options',
        'player-box-stats',
      ]) {
        final rect = tester.getRect(find.byKey(ValueKey(key)));
        rects[key] = [rect.left, rect.top, rect.width, rect.height];
      }
      final seek = tester.getRect(find.byType(ProgressRail));
      rects['seek'] = [seek.left, seek.top, seek.width, seek.height];
      for (final control in rects.entries) {
        final before = expected[entry.key]![control.key]!;
        for (var i = 0; i < 4; i++) {
          expect(
            control.value[i],
            closeTo(before[i], 2),
            reason: '${entry.key} ${control.key} rect component $i',
          );
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await controller.dispose();
    });
  }

  _stateProofs();
}

class _CastFixture implements CastUiController {
  @override
  final ValueNotifier<CastUiState> state = ValueNotifier<CastUiState>(
    const CastUiState(
      targets: [
        CastTarget(id: 'living', name: 'Living Room TV', playable: true),
        CastTarget(id: 'bedroom', name: 'Bedroom Chromecast', playable: false),
        CastTarget(
          id: 'long',
          name: 'The television in the upstairs living room with a very long device name',
          playable: true,
        ),
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
  Future<void> seek(Duration value) async =>
      calls.add('seek:${value.inSeconds}');
  @override
  Future<void> stop() async => calls.add('stop');
}

Future<void> _host(
  WidgetTester tester,
  String form,
  Widget child, {
  double textScale = 1,
  bool reduced = false,
  bool fa = false,
}) async {
  final factor = _factors[form]!;
  tester.view.physicalSize = factor.size * factor.dpr;
  tester.view.devicePixelRatio = factor.dpr;
  addTearDown(tester.view.reset);

  final artwork = await loadFixtureArtworkResolver(tester);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      locale: fa ? const Locale('fa') : null,
      key: const ValueKey('phase-proof'),
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(tv: factor.factor == FormFactor.tv).copyWith(
        platform: form == 'desktop'
            ? TargetPlatform.macOS
            : TargetPlatform.android,
      ),
      builder: (context, route) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduced,
        ),
        child: AdaptiveBehavior(
          capabilities: factor.factor == FormFactor.tv
              ? const PlatformCapabilities.directionalPad()
              : factor.factor == FormFactor.phone
              ? const PlatformCapabilities.touch()
              : const PlatformCapabilities(),
          // Layout never mirrors in Farsi (DESIGN_SPEC §10.3).
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ArtworkResolverScope(resolver: artwork, child: route!),
          ),
        ),
      ),
      home: Scaffold(backgroundColor: Colors.transparent, body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 600));
}

/// One frame to mount the route/overlay, then past its `base` transition.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Widget _onBase(Widget child, {bool top = false}) => Builder(
  builder: (context) => ColoredBox(
    color: RivuletTokens.of(context).colors.bgBase,
    child: top
        ? SizedBox.expand(
            child: Align(alignment: Alignment.topLeft, child: child),
          )
        : child,
  ),
);

PlayerScreen _player(FakePlaybackController controller, {_CastFixture? cast}) =>
    PlayerScreen(
      controller: controller,
      videoSurface: const FakeVideoSurface(),
      title: 'Iron Man 3',
      setSystemUiMode: (_) async {},
      cast: cast,
    );

Future<void> _golden(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  await expectLater(
    find.byKey(const ValueKey('phase-proof')),
    matchesGoldenFile('goldens/p06/$name.png'),
  );
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// Every form factor in English, plus Farsi on phone and desktop.
List<(String, bool)> _formsFa() => [
  for (final form in _factors.keys) (form, false),
  ('phone', true),
  ('desktop', true),
];

void _stateProofs() {
  for (final form in ['desktop', 'tv']) {
    testWidgets('golden player options $form', (tester) async {
      final controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 96));
      await _host(tester, form, _player(controller));
      await tester.tap(find.byKey(const ValueKey('player-box-options')));
      await _settle(tester);
      expect(
        find.descendant(
          of: find.byType(PlayerPanelHost),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );
      await _golden(tester, 'player_options_panel_$form');
      await controller.dispose();
    });
  }
  testWidgets('TV: the control rail fades out while a panel is open', (
    tester,
  ) async {
    final controller = FakePlaybackController()
      ..setDuration(const Duration(minutes: 96));
    await _host(tester, 'tv', _player(controller));
    final opener = find.byKey(const ValueKey('player-box-options'));
    double railOpacity() => tester
        .widget<AnimatedOpacity>(
          find
              .ancestor(of: opener, matching: find.byType(AnimatedOpacity))
              .last,
        )
        .opacity;
    expect(railOpacity(), 1);
    await tester.tap(opener);
    await _settle(tester);
    expect(railOpacity(), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(railOpacity(), 1);
    expect(
      tester.widget<TransportControlButton>(opener).focusNode?.hasFocus,
      isTrue,
    );
    await controller.dispose();
  });
  for (final (form, fa) in _formsFa()) {
    testWidgets('golden cast picker $form${fa ? ' fa' : ''}', (tester) async {
      final controller = FakePlaybackController()
        ..setDuration(const Duration(minutes: 96));
      final cast = _CastFixture();
      await _host(tester, form, _player(controller, cast: cast), fa: fa);
      await tester.tap(find.byKey(const ValueKey('cast-button')));
      await _settle(tester);
      expect(find.byType(AppRowGroup), findsOneWidget);
      if (form == 'desktop') {
        expect(find.byType(CompositedTransformFollower), findsOneWidget);
        final picker = tester.getRect(find.byType(CastPicker));
        expect(
          picker.bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('cast-button'))).top,
          ),
        );
      }
      await _golden(tester, 'cast_picker_$form${fa ? '_fa' : ''}');
      expect(cast.calls, ['discover', 'stopDiscovery']);
      cast.state.dispose();
      await controller.dispose();
    });
  }
  testWidgets('golden player post video desktop', (tester) async {
    await _host(
      tester,
      'desktop',
      Stack(
        children: [
          PostVideoOverlay(
            nextTitle: 'The next episode',
            nextDescription: 'Continue watching the next episode.',
            countdownPaused: true,
            onPlayNext: () {},
            onDismiss: () {},
          ),
        ],
      ),
    );
    expect(find.byType(TintedSurface), findsOneWidget);
    await _golden(tester, 'player_post_video_desktop');
  });
  testWidgets('golden player buffering desktop', (tester) async {
    await _host(
      tester,
      'desktop',
      ColoredBox(
        color: Colors.black,
        child: const Stack(children: [PlayerBufferingIndicator(progress: .42)]),
      ),
    );
    expect(find.byType(OrbLoader), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    await _golden(tester, 'player_buffering_desktop');
  });
  testWidgets('golden casting chrome desktop', (tester) async {
    final cast = _CastFixture();
    cast.state.value = const CastUiState(
      castingTo: 'Living Room TV',
      isPlaying: true,
      duration: Duration(minutes: 96),
      position: Duration(minutes: 36),
    );
    await _host(
      tester,
      'desktop',
      ColoredBox(
        color: Colors.black,
        child: Stack(children: [CastingChrome(controller: cast)]),
      ),
    );
    expect(
      find.ancestor(of: find.byType(Slider), matching: find.byType(FocusRing)),
      findsOneWidget,
    );
    await _golden(tester, 'casting_chrome_desktop');
    cast.state.dispose();
  });
  testWidgets('throwing play handler restores submit and preserves input', (
    tester,
  ) async {
    await _host(
      tester,
      'phone',
      PlayLinkInput(
        onPlay: (_) async => throw StateError('Cannot open link'),
        pickTorrent: () async => null,
      ),
    );
    await tester.enterText(
      find.byType(EditableText),
      'https://example.com/movie.mkv',
    );
    await tester.tap(find.text('Play'));
    await tester.pumpAndSettle();
    expect(find.text('Bad state: Cannot open link'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byType(AppButton).first).onActivate,
      isNotNull,
    );
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'https://example.com/movie.mkv',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  const longLink =
      'https://example.com/a-very-long-directory-name/another-long-directory/فیلم-بسیار-طولانی/movie-with-a-long-title.mkv';
  Future<RecentLinks> recents() async {
    final recent = RecentLinks(MemorySettingsStore());
    await recent.add(longLink, kind: 'http', title: 'A recently played movie');
    return recent;
  }

  testWidgets('golden play link recent phone', (tester) async {
    final recent = await recents();
    await _host(
      tester,
      'phone',
      PlayLinkPage(
        recents: recent,
        onPlay: (_) async => null,
        pickTorrent: () async => null,
      ),
    );
    expect(find.byType(AppRowGroup), findsOneWidget);
    await _golden(tester, 'play_link_recent_phone');
  });
  testWidgets(
    'long URL keeps graphemes full semantics and separate Remove action',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final recent = await recents();
      await _host(
        tester,
        'phone',
        PlayLinkPage(
          recents: recent,
          onPlay: (_) async => null,
          pickTorrent: () async => null,
        ),
        textScale: 2,
      );
      expect(
        find.bySemanticsLabel('Remove A recently played movie'),
        findsOneWidget,
      );
      final remove = tester.getSemantics(
        find.bySemanticsLabel('Remove A recently played movie'),
      );
      expect(remove.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(remove.label, isNot(contains(longLink)));
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(longLink))),
        findsWidgets,
      );
      final captions = tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => text.data?.contains('…') ?? false);
      expect(captions.any((text) => text.data!.endsWith('.mkv')), isTrue);
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Remove A recently played movie'));
      await tester.pumpAndSettle();
      expect(recent.entries, isEmpty);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('golden dialog confirm desktop', (tester) async {
    final recent = await recents();
    await _host(
      tester,
      'desktop',
      PlayLinkPage(
        recents: recent,
        onPlay: (_) async => null,
        pickTorrent: () async => null,
      ),
    );
    await tester.tap(find.text('Clear all'));
    await _settle(tester);
    expect(find.text('Clear all recent links?'), findsOneWidget);
    await _golden(tester, 'dialog_confirm_desktop');
  });
  for (final (form, fa) in [
    ('desktop', false),
    ('tv', false),
    ('desktop', true),
    ('phone', true),
  ]) {
    testWidgets('golden toast $form${fa ? ' fa' : ''}', (tester) async {
      await _host(
        tester,
        form,
        fa: fa,
        _onBase(
          top: true,
          Builder(
            builder: (context) => AppButton.primary(
              label: 'Show toast',
              onActivate: () => showAppToast(
                context,
                PhosphorIconsRegular.check,
                fa
                    ? AppStrings.of(context).detail_watchlist
                    : 'Added to watchlist',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Show toast'));
      await _settle(tester);
      expect(
        find.text(fa ? 'فهرست تماشا' : 'Added to watchlist'),
        findsOneWidget,
      );
      await _golden(tester, 'toast_$form${fa ? '_fa' : ''}');
    });
  }
  for (final form in ['phone', 'desktop', 'tv']) {
    testWidgets('golden offline $form', (tester) async {
      final outage = ConnectionOutageController()
        ..updateConnection(healthy: false);
      await _host(
        tester,
        form,
        _onBase(
          top: true,
          ConnectionOutageBanner(controller: outage, onRetry: () async {}),
        ),
      );
      expect(find.text("You're offline"), findsOneWidget);
      await _golden(tester, 'offline_$form');
      outage.dispose();
    });
  }
  for (final (form, fa) in [
    ('desktop', false),
    ('tv', false),
    ('desktop', true),
    ('phone', true),
  ]) {
    testWidgets('golden error full $form${fa ? ' fa' : ''}', (tester) async {
      await _host(
        tester,
        form,
        fa: fa,
        _onBase(
          ErrorView(
            fullScreen: true,
            failure: const PlaybackFailure.sourceUnreachable(cause: 'fixture'),
            onRetry: () {},
            onBack: () {},
          ),
        ),
      );
      await _golden(tester, 'error_full_$form${fa ? '_fa' : ''}');
    });
  }
}
