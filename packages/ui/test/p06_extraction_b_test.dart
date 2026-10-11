import 'package:ui/src/l10n_gen/app_strings_en.dart';
import 'package:ui/src/l10n_gen/app_strings_fa.dart';
import 'package:contracts/fakes/fake_playback_controller.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/src/player/player_box_options.dart';
import 'package:ui/src/player/stats/stats_popover.dart';
import 'package:ui/src/player/stats/stats_overlay.dart';
import 'package:ui/src/player/stats/stats_format.dart' as stats_format;
import 'package:core/core.dart';
import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:ui/src/settings/settings_catalog.dart';

import 'support/l10n_tools.dart';
import 'support/state_screen_registry.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool tv = false,
  Size size = const Size(1920, 1080),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [MarkedStringsDelegate()],
      theme: AppTheme.dark(tv: tv),
      home: AdaptiveBehavior(
        capabilities: PlatformCapabilities(isTv: tv),
        child: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _check(WidgetTester tester, {Set<String> allow = const {}}) {
  expect(
    findUnextractedText(tester, allow: {...fixtureContentStrings, ...allow}),
    isEmpty,
  );
  expect(tester.takeException(), isNull);
}

CapabilityReport _report() => CapabilityReport(
  hardwareDecode: true,
  decoders: ['h264'],
  hdrOutput: true,
  hdrFormats: ['HDR10'],
  displayModeSwitching: true,
  audioPassthrough: true,
  passthroughFormats: ['ac3', 'eac3', 'dts', 'trueHd', 'dtsHd'],
  diagnostics: {},
);

class _FailingRateController extends FakePlaybackController {
  _FailingRateController(this.failure);
  final Object failure;
  @override
  Future<void> setRate(double rate) async => throw failure;
}

void main() {
  for (final failure in [
    PlaybackFailure.openFailed(cause: 'fixture'),
    StateError('fixture'),
  ]) {
    testWidgets('option failure ${failure.runtimeType} extracts copy', (
      tester,
    ) async {
      final controller = _FailingRateController(failure);
      final options = ValueNotifier(PlayerOptionValues());
      addTearDown(controller.dispose);
      addTearDown(options.dispose);
      await _pump(
        tester,
        SizedBox(
          height: 900,
          width: 720,
          child: PlayerBoxOptions(
            controller: controller,
            state: controller.currentState,
            dismiss: () {},
            options: options,
            mediaInfo: MediaInfo.empty,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('options-section-Playback')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('speed-1.5')));
      await tester.pump();
      _check(tester);
    });
  }
  test(
    'every catalog setting has marked label, choices and apply note: ${settingDefs.length} settings',
    () {
      final strings = MarkedStrings();
      var checked = 0;
      for (final def in settingDefs) {
        expect(settingLabel(def, strings), startsWith('⟦'), reason: def.id);
        for (final choice in def.choices) {
          expect(
            choiceLabel(def, choice, strings),
            startsWith('⟦'),
            reason: '${def.id}: $choice',
          );
        }
        final note = applyNote(def, strings);
        if (note != null) expect(note, startsWith('⟦'), reason: def.id);
        checked++;
      }
      expect(checked, settingDefs.length);
    },
  );
  for (final (name, tv, size) in [
    ('desktop', false, const Size(1920, 1080)),
    ('tv', true, const Size(1920, 1080)),
    ('phone', false, const Size(400, 800)),
  ]) {
    testWidgets('player rest $name extracts all UI copy', (tester) async {
      final fixture = await p06MatrixFixtures['player']!();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      });
      await _pump(tester, fixture.widget, tv: tv, size: size);
      _check(tester, allow: {'Fixture player'});
    });
  }
  for (final section in <SettingSection?>[null, ...SettingSection.values]) {
    testWidgets(
      'Expert settings ${section?.name ?? 'root'} extracts all UI copy',
      (tester) async {
        final settings = AppSettings(MemorySettingsStore());
        await settings.setShowAdvanced(true);
        await settings.setShowExpert(true);
        await _pump(
          tester,
          SettingsScreen(
            settings: settings,
            capabilities: _report(),
            available: SettingCapability.values.toSet(),
            section: section,
          ),
        );
        _check(tester, allow: {'DejaVu Sans'});
        final scroll = find.byType(Scrollable).first;
        while (tester.state<ScrollableState>(scroll).position.extentAfter > 0) {
          await tester.drag(scroll, const Offset(0, -500));
          await tester.pump();
          _check(tester, allow: {'DejaVu Sans'});
        }
      },
    );
  }
  testWidgets('Diagnostics extracts all UI copy', (tester) async {
    await _pump(
      tester,
      DiagnosticsScreen(report: _report(), copyText: (_) async {}),
    );
    _check(tester, allow: {'h264', 'HDR10', 'ac3, eac3, dts, trueHd, dtsHd'});
  });
  testWidgets('player options and all its sections extract copy', (
    tester,
  ) async {
    final controller = FakePlaybackController();
    final options = ValueNotifier(PlayerOptionValues());
    addTearDown(controller.dispose);
    addTearDown(options.dispose);
    await _pump(
      tester,
      SizedBox(
        height: 900,
        width: 720,
        child: PlayerBoxOptions(
          controller: controller,
          state: controller.currentState,
          dismiss: () {},
          options: options,
          mediaInfo: MediaInfo.empty,
        ),
      ),
    );
    _check(tester);
    for (final section in ['Audio', 'Video', 'Playback', 'Info', 'Subtitles']) {
      await tester.tap(find.byKey(ValueKey('options-section-$section')));
      await tester.pump();
      _check(tester);
    }
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('download-subtitles')),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('options-list-Subtitles')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('download-subtitles')));
    await tester.pump();
    _check(tester);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  for (final type in [TrackType.audio, TrackType.subtitle]) {
    testWidgets('track panel ${type.name} extracts copy', (tester) async {
      final controller = FakePlaybackController();
      addTearDown(controller.dispose);
      await _pump(
        tester,
        TrackPanel(
          controller: controller,
          state: controller.currentState,
          dismiss: () {},
          type: type,
        ),
      );
      _check(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('Info panel extracts labels and metadata groups', (tester) async {
    final controller = FakePlaybackController();
    final output = ValueNotifier<String?>('PCM');
    addTearDown(controller.dispose);
    addTearDown(output.dispose);
    await _pump(
      tester,
      InfoPanel(
        description: null,
        info: const MediaInfo(
          container: 'matroska',
          fileSizeBytes: 1024 * 1024,
        ),
        tracks: controller.currentState.tracks,
        audioOutput: output,
      ),
    );
    _check(tester, allow: {'MATROSKA', '1 MB'});
  });
  testWidgets('stats popover and overlay extract labels, retain raw values', (
    tester,
  ) async {
    const transport = TransportStats(
      downloadBytesPerSecond: 1024,
      downloadedBytes: 1024,
      totalBytes: 4096,
      connections: 2,
    );
    final stats = PlayerStatsController(
      PlayerStatsSource(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('https://example.invalid/file'),
        readTransport: () async => transport,
      ),
    );
    addTearDown(stats.dispose);
    await _pump(tester, StatsPopover(controller: stats, onAdvanced: () {}));
    final values = {
      stats_format.formatSpeed(transport.downloadBytesPerSecond),
      stats_format.formatProgress(
        transport.downloadedBytes,
        transport.totalBytes,
      ),
    };
    _check(tester, allow: values);
    await _pump(tester, StatsOverlay(controller: stats, onClose: () {}));
    _check(
      tester,
      allow: {
        for (final group in buildStatsGroups(stats.source, stats.snapshot))
          for (final row in group.rows) row.value,
      },
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('up-next and post-video extract controls', (tester) async {
    await _pump(
      tester,
      UpNextPanel(
        items: const [
          UpNextItem(
            id: 'fixture',
            title: 'Fixture episode',
            state: UpNextState.upNext,
          ),
        ],
        onSelected: (_) {},
      ),
    );
    _check(tester, allow: {'Fixture episode'});
    await _pump(
      tester,
      PostVideoOverlay(
        nextTitle: 'Fixture episode',
        onPlayNext: () {},
        onDismiss: () {},
        onOpenSeason: () {},
        onOpenShow: () {},
        countdownPaused: true,
      ),
    );
    _check(tester, allow: {'Fixture episode'});
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('chapters overlay extracts unnamed chapter fallback', (
    tester,
  ) async {
    await _pump(
      tester,
      ChaptersOverlay(
        chapters: const [Chapter(start: Duration.zero)],
        onSeek: (_) {},
        onClose: () {},
      ),
    );
    _check(tester);
  });
  testWidgets('source picker extracts status and source-kind copy', (
    tester,
  ) async {
    await _pump(
      tester,
      SourcePickerPanel(
        sources: [
          SourceSpec(
            kind: SourceKind.torrentMagnet,
            uri: Uri.parse('magnet:?xt=urn:btih:fixture'),
          ),
        ],
        activeIndex: 0,
        statusOf: (_) => null,
        onSelected: (_) {},
      ),
    );
    _check(tester);
  });
  testWidgets('every Audio choice dialog extracts copy', (tester) async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await _pump(
      tester,
      SettingsScreen(
        settings: settings,
        capabilities: _report(),
        available: SettingCapability.values.toSet(),
        section: SettingSection.audio,
        audioDevices: [
          AudioDevice(
            id: 'fixture',
            name: 'Fixture device',
            isCurrent: true,
            supportedSampleRates: [48000],
          ),
        ],
      ),
    );
    for (final def in visibleSettings(
      SettingSection.audio,
      showAdvanced: true,
      showExpert: true,
      available: SettingCapability.values.toSet(),
    ).where((def) => def.kind == SettingKind.choice)) {
      final row = find.byKey(ValueKey('setting-${def.id}'));
      await tester.scrollUntilVisible(
        row,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(SettingChoiceRow)),
      );
      await tester.pumpAndSettle();
      _check(tester, allow: {'Fixture device'});
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
    }
  });

  test('numeric choices retain English and format Persian digits', () {
    final english = AppStringsEn();
    final persian = AppStringsFa();
    for (final (id, value, expected) in [
      ('audio.sampleRate', '48000', '۴۸۰۰۰'),
      ('audio.speakerLayout', '5.1', '۵٫۱'),
      ('streaming.quality', '20 Mbps', '۲۰ مگابیت بر ثانیه'),
      ('streaming.cacheSizeLimit', '2 GB', '۲ گیگابایت'),
    ]) {
      expect(choiceLabel(settingById(id), value, english), value);
      expect(choiceLabel(settingById(id), value, persian), expected);
    }
  });
  test('player failure copy keeps the contract English payload', () {
    final strings = AppStringsEn();
    for (final failure in [
      const PlaybackFailure.openFailed(cause: 'fixture'),
      const PlaybackFailure.decodeFailed(cause: 'fixture'),
      const PlaybackFailure.engineCrashed(cause: 'fixture'),
      const PlaybackFailure.sourceUnreachable(cause: 'fixture'),
      const PlaybackFailure.unsupportedCodec(codec: 'fixture-codec'),
      const PlaybackFailure.trackSelectionFailed(trackId: 'fixture-track'),
      PlaybackFailure.subtitleLoadFailed(
        uri: Uri.parse('https://example.invalid/file.srt'),
        cause: 'fixture',
      ),
    ]) {
      expect(playerFailureMessage(failure, strings), failure.message);
      expect(playerFailureMessage(failure, MarkedStrings()), startsWith('⟦'));
    }
  });
  for (final login in [UiProviderLogin.credentials, UiProviderLogin.qr]) {
    testWidgets('provider ${login.name} dialogs extract copy', (tester) async {
      await _pump(
        tester,
        ProvidersScreen(
          load: () async => [
            UiProviderAccount(
              id: 'fixture',
              name: 'Fixture service',
              login: login,
            ),
          ],
          onCredentials: (_, _, _) async => null,
          onStartQr: (_) async => UiQrLogin(
            code: '1234',
            url: Uri.parse('https://example.invalid/login'),
          ),
          onPollQr: (_, _) async => false,
          onLogout: (_) async {},
          onBuy: (_) async {},
        ),
      );
      _check(tester, allow: {'Fixture service'});
      await tester.tap(find.byKey(const ValueKey('provider-login-fixture')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      _check(tester, allow: {'Fixture service'});
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
