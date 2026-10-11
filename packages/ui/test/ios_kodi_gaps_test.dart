import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_catalog.dart';

/// ios_reference.md 1.13 / 4.3-4.6: keep-alive and match resolution are
/// offered; exclusive mode, frame-rate matching, refresh rate and whitelist
/// are not.
void main() {
  test('iOS offers keep-alive and match resolution, not refresh controls', () {
    final available = <SettingCapability>{
      SettingCapability.displayModeSwitching,
    };
    Set<String> ids(String os) => {
      for (final section in SettingSection.values)
        for (final def in visibleSettings(
          section,
          showAdvanced: true,
          showExpert: true,
          available: available,
          os: os,
        ))
          def.id,
    };
    final ios = ids('ios');
    expect(
      ios,
      containsAll(['audio.deviceKeepAlive', 'video.matchResolution']),
    );
    expect(
      ios,
      isNot(
        containsAny([
          'audio.exclusiveMode',
          'video.matchFrameRate',
          'display.refreshRate',
          'video.displayModeWhitelist',
        ]),
      ),
    );
    expect(ids('macos'), isNot(contains('audio.deviceKeepAlive')));
  });
}

Matcher containsAny(List<String> items) => predicate<Set<String>>(
  (set) => items.any(set.contains),
  'contains any of $items',
);
