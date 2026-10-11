import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart' hide PlatformCapabilities;
import 'package:contracts/fakes/fake_playback_controller.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/player/player_box_options.dart';
import 'package:ui/src/player/stats/stats_overlay.dart';
import 'package:ui/src/player/stats/stats_popover.dart';
import 'package:ui/src/settings/settings_catalog.dart';
import 'package:ui/src/settings/settings_controls.dart';
import 'package:ui/ui.dart';

import 'support/l10n_tools.dart';
import 'support/state_screen_registry.dart';

/// Technical identifiers that stay Latin in Farsi settings, on top of [kTechAllowlist]
/// (DESIGN_SPEC §10.6: no standard Persian term exists).
const Set<String> _techNames = {
  'Demuxer',
  'Passthrough',
  'LPCM',
  'DHT',
  'PEX',
  'TLS',
  'GPU',
  'RAM',
  'QR',
  'ASS/SSA',
  'User agent',
  'mpv',
  'Info-hash',
  'DejaVu Sans',
  'CLL',
  'FALL',
  'file',
  'bt.2390',
  'bt.2446a',
  'st2094-40',
  'st2094-10',
  'clip',
  'mobius',
  'reinhard',
  'hable',
  'gamma',
  'linear',
  'spline',
  'nv12',
  'yuv420p',
  'yuv420p10',
  'yuv422p',
  'yuv422p10',
  'yuv444p',
  'yuv444p10',
  'rgb24',
  'fruit',
  'ordered',
  'opengl',
  'utf-8',
  'cp1250',
  'cp1251',
  'cp1252',
  'cp1253',
  'cp1254',
  'cp1256',
  'iso-8859-1',
  'iso-8859-2',
  'shift_jis',
  'gbk',
  'big5',
  'euc-kr',
  'Dolby Vision',
  'Fixture',
  'Fixture player',
  'matroska',
  'MATROSKA',
  'h264',
  'ac3',
  'eac3',
  'dts',
  'trueHd',
  'dtsHd',
  'A',
  'B',
  'OK',
  'Digital',
  'Plus',
  'Atmos',
  'DTS-HD',
  'DTS:X',
  'TrueHD',
  'Dolby',
  'Fixture device',
  'Fixture service',
  'Fixture episode',
  'https://example.invalid/login',
};

final Map<String, List<String>> _report = {};

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
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa'),
      localizationsDelegates: AppStrings.localizationsDelegates,
      supportedLocales: AppStrings.supportedLocales,
      builder: (_, child) =>
          Directionality(textDirection: TextDirection.ltr, child: child!),
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

void _check(WidgetTester tester, String name, {Set<String> allow = const {}}) {
  final left = findUntranslatedText(
    tester,
    allow: {
      ...fixtureContentStrings,
      ...kTechAllowlist,
      ..._techNames,
      ...allow,
    },
  );
  _report.putIfAbsent(name, () => []).addAll(left);
  expect(left, isEmpty, reason: name);
  expect(tester.takeException(), isNull);
}

CapabilityReport _caps() => CapabilityReport(
  hardwareDecode: true,
  decoders: ['h264'],
  hdrOutput: true,
  hdrFormats: ['HDR10'],
  displayModeSwitching: true,
  audioPassthrough: true,
  passthroughFormats: ['ac3', 'eac3', 'dts', 'trueHd', 'dtsHd'],
  diagnostics: {},
);

Future<AppSettings> _expert() async {
  final settings = AppSettings(MemorySettingsStore());
  await settings.setShowAdvanced(true);
  await settings.setShowExpert(true);
  return settings;
}

void _goldens() {
  const phone = Size(400, 800);
  const desktop = Size(1280, 800);
  const tv = Size(960, 540);
  Future<void> shot(WidgetTester tester, String name) async {
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/p06/${name}_fa.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  }

  for (final (form, size, isTv) in [
    ('phone', phone, false),
    ('desktop', desktop, false),
    ('tv', tv, true),
  ]) {
    testWidgets('golden settings root $form fa', (tester) async {
      await _pump(
        tester,
        SettingsScreen(
          settings: AppSettings(MemorySettingsStore()),
          capabilities: _caps(),
          available: SettingCapability.values.toSet(),
        ),
        tv: isTv,
        size: size,
      );
      await shot(tester, 'settings_root_$form');
    });
    testWidgets('golden settings audio $form fa', (tester) async {
      await _pump(
        tester,
        SettingsScreen(
          settings: await _expert(),
          capabilities: _caps(),
          available: SettingCapability.values.toSet(),
          section: SettingSection.audio,
        ),
        tv: isTv,
        size: size,
      );
      await shot(tester, 'settings_audio_$form');
    });
    testWidgets('golden player $form fa', (tester) async {
      final fixture = await p06MatrixFixtures['player']!();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      });
      await _pump(tester, fixture.widget, tv: isTv, size: size);
      await shot(tester, 'player_$form');
    });
  }
  testWidgets('golden settings video desktop fa', (tester) async {
    await _pump(
      tester,
      SettingsScreen(
        settings: await _expert(),
        capabilities: _caps(),
        available: SettingCapability.values.toSet(),
        section: SettingSection.video,
      ),
      size: desktop,
    );
    await shot(tester, 'settings_video_desktop');
  });
  testWidgets('golden settings choice dialog desktop fa', (tester) async {
    await _pump(
      tester,
      Builder(
        builder: (context) => Center(
          child: SizedBox(
            width: 720,
            child: AppRowGroup(
              children: [
                SettingChoiceRow(
                  title: AppStrings.of(context).settings_video_decoder_label,
                  value: 'Auto',
                  options: const ['Auto', 'hardware', 'software'],
                  labelOf: (v) => choiceLabel(
                    settingById('video.decoder'),
                    v,
                    AppStrings.of(context),
                  ),
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
      size: desktop,
    );
    await tester.tap(find.byType(SettingChoiceRow));
    await tester.pumpAndSettle();
    await shot(tester, 'settings_choice_dialog_desktop');
  });
  testWidgets('golden player options panel desktop fa', (tester) async {
    final controller = FakePlaybackController();
    final options = ValueNotifier(PlayerOptionValues());
    addTearDown(controller.dispose);
    addTearDown(options.dispose);
    await _pump(
      tester,
      Center(
        child: SizedBox(
          height: 700,
          width: 520,
          child: PlayerBoxOptions(
            controller: controller,
            state: controller.currentState,
            dismiss: () {},
            options: options,
            mediaInfo: MediaInfo.empty,
          ),
        ),
      ),
      size: desktop,
    );
    await shot(tester, 'player_options_panel_desktop');
  });
  testWidgets('golden diagnostics desktop fa', (tester) async {
    await _pump(
      tester,
      DiagnosticsScreen(
        report: _caps(),
        playbackDiagnostics: const {'Decoder': 'software'},
        copyText: (_) async {},
      ),
      size: desktop,
    );
    await shot(tester, 'diagnostics_desktop');
  });
}

void main() {
  _goldens();
  tearDownAll(() {
    final out = Platform.environment['FARSI_B_JSON'];
    if (out != null) {
      File(out).writeAsStringSync(
        const JsonEncoder.withIndent('  ')
            .convert({'screens': _report.length, 'untranslated': _report}),
      );
    }
  });

  for (final (name, tv, size) in [
    ('desktop', false, const Size(1920, 1080)),
    ('tv', true, const Size(1920, 1080)),
    ('phone', false, const Size(400, 800)),
  ]) {
    testWidgets('player $name is Persian', (tester) async {
      final fixture = await p06MatrixFixtures['player']!();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await fixture.dispose();
      });
      await _pump(tester, fixture.widget, tv: tv, size: size);
      _check(tester, 'player_$name');
    });
  }

  for (final section in <SettingSection?>[null, ...SettingSection.values]) {
    testWidgets('Expert settings ${section?.name ?? 'root'} is Persian', (
      tester,
    ) async {
      final settings = await _expert();
      await _pump(
        tester,
        SettingsScreen(
          settings: settings,
          capabilities: _caps(),
          available: SettingCapability.values.toSet(),
          section: section,
        ),
      );
      final name = 'settings_${section?.name ?? 'root'}';
      _check(tester, name);
      final scroll = find.byType(Scrollable).first;
      while (tester.state<ScrollableState>(scroll).position.extentAfter > 0) {
        await tester.drag(scroll, const Offset(0, -500));
        await tester.pump();
        _check(tester, name);
      }
    });
  }

  testWidgets('Diagnostics is Persian', (tester) async {
    await _pump(
      tester,
      DiagnosticsScreen(report: _caps(), copyText: (_) async {}),
    );
    _check(tester, 'diagnostics');
  });

  testWidgets('player options and all sections are Persian', (tester) async {
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
    _check(tester, 'player_options');
    for (final section in ['Audio', 'Video', 'Playback', 'Info', 'Subtitles']) {
      await tester.tap(find.byKey(ValueKey('options-section-$section')));
      await tester.pump();
      _check(tester, 'player_options_$section');
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final type in [TrackType.audio, TrackType.subtitle]) {
    testWidgets('track panel ${type.name} is Persian', (tester) async {
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
      _check(tester, 'track_${type.name}');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Info panel is Persian', (tester) async {
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
    _check(tester, 'info_panel', allow: {'1 MB'});
  });

  testWidgets('stats popover and overlay labels are Persian', (tester) async {
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
    // Values (units, hosts, codecs) are exempt, DESIGN_SPEC §10.5.
    final values = {
      for (final group in buildStatsGroups(stats.source, stats.snapshot))
        for (final row in group.rows) row.value,
    };
    await _pump(tester, StatsPopover(controller: stats, onAdvanced: () {}));
    _check(tester, 'stats_popover', allow: values);
    await _pump(tester, StatsOverlay(controller: stats, onClose: () {}));
    _check(tester, 'stats_overlay', allow: values);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('up-next, post-video, chapters, sources are Persian', (
    tester,
  ) async {
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
    _check(tester, 'up_next');
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
    _check(tester, 'post_video');
    await _pump(
      tester,
      ChaptersOverlay(
        chapters: const [Chapter(start: Duration.zero)],
        onSeek: (_) {},
        onClose: () {},
      ),
    );
    _check(tester, 'chapters');
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
    _check(tester, 'source_picker');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('every Audio choice dialog is Persian', (tester) async {
    final settings = await _expert();
    await _pump(
      tester,
      SettingsScreen(
        settings: settings,
        capabilities: _caps(),
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
      _check(tester, 'audio_choice_dialog');
      tester.state<NavigatorState>(find.byType(Navigator).last).pop();
      await tester.pumpAndSettle();
    }
  });

  for (final login in [UiProviderLogin.credentials, UiProviderLogin.qr]) {
    testWidgets('provider ${login.name} dialogs are Persian', (tester) async {
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
      _check(tester, 'providers_${login.name}');
      await tester.tap(find.byKey(const ValueKey('provider-login-fixture')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      _check(tester, 'providers_${login.name}_dialog');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
