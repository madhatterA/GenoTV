import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/ui_bindings.dart';

CapabilityReport _report() => CapabilityReport(
  hardwareDecode: true,
  decoders: const ['h264'],
  hdrOutput: false,
  hdrFormats: const [],
  displayModeSwitching: true,
  audioPassthrough: false,
  passthroughFormats: const [],
  diagnostics: const {},
);

void main() {
  test('iOS matches resolution only; desktop also controls refresh rate', () {
    final ios = availableSettingCapabilities(_report(), os: 'ios');
    expect(ios, contains(SettingCapability.displayModeSwitching));
    expect(ios, isNot(contains(SettingCapability.refreshRateControl)));
    final mac = availableSettingCapabilities(_report(), os: 'macos');
    expect(mac, contains(SettingCapability.refreshRateControl));
  });
}
