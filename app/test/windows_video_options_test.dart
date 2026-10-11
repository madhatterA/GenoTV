import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';
import 'package:video_player/ui_bindings.dart';

void main() {
  late SettingsValues values;
  setUp(() => values = SettingsValues(MemorySettingsStore()));
  tearDown(() => values.dispose());

  Map<String, String> open() => engineOptionsFor(
    values,
    scope: changedEngineSettings(values, os: 'windows'),
    os: 'windows',
  );

  // Kodi Windows 2.1: videoplayer.usedxva2 defaults on; DXVA -> mpv d3d11va.
  test('Windows applies D3D11VA (copy) at open with software fallback', () {
    final options = open();
    expect(options['hwdec'], 'd3d11va-copy');
    expect(options['vd-lavc-software-fallback'], 'yes');
    expect(options['vf'], '');
  });

  test(
    'Off and software decoder choose software; CPU filters use copy',
    () async {
      await values.write(settingById('video.hwdec'), 'Off');
      expect(open()['hwdec'], 'no');
      await values.reset(settingById('video.hwdec'));
      await values.write(settingById('video.decoder'), 'software');
      expect(open()['hwdec'], 'no');
      await values.reset(settingById('video.decoder'));
      await values.write(settingById('video.chroma'), '4:4:4');
      final copy = open();
      expect(copy['hwdec'], 'd3d11va-copy');
      expect(copy['vf'], 'format=yuv444p');
    },
  );

  test('Windows offers no GPU backend choice (Direct3D 11 only)', () {
    final report = CapabilityReport(
      hardwareDecode: true,
      decoders: const ['h264'],
      hdrOutput: false,
      hdrFormats: const [],
      displayModeSwitching: true,
      audioPassthrough: false,
      passthroughFormats: const [],
      diagnostics: const {'os': 'windows'},
    );
    final available = availableSettingCapabilities(report, os: 'windows');
    expect(available, isNot(contains(SettingCapability.gpuBackend)));
    expect(available, contains(SettingCapability.displayModeSwitching));
    expect(available, isNot(contains(SettingCapability.hdrOutput)));
  });

  // Kodi Windows 4.1: videoscreen.monitor (Default + monitor names) is offered.
  test('Windows and macOS offer the monitor picker', () {
    final report = CapabilityReport(
      hardwareDecode: true,
      decoders: const ['h264'],
      hdrOutput: false,
      hdrFormats: const [],
      displayModeSwitching: true,
      audioPassthrough: false,
      passthroughFormats: const [],
      diagnostics: const {'os': 'windows'},
    );
    expect(
      availableSettingCapabilities(report, os: 'windows'),
      contains(SettingCapability.multipleDisplays),
    );
    expect(
      availableSettingCapabilities(report, os: 'macos'),
      contains(SettingCapability.multipleDisplays),
    );
  });

  // Kodi Windows 4.2: videoscreen.fakefullscreen (windowed / fullscreen window).
  test('Windows offers the fullscreen mode', () {
    final report = CapabilityReport(
      hardwareDecode: true,
      decoders: const ['h264'],
      hdrOutput: false,
      hdrFormats: const [],
      displayModeSwitching: true,
      audioPassthrough: false,
      passthroughFormats: const [],
      diagnostics: const {'os': 'windows'},
    );
    expect(
      availableSettingCapabilities(report, os: 'windows'),
      contains(SettingCapability.desktopWindow),
    );
  });
}
