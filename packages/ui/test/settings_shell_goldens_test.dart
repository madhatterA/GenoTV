import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';

import 'support/settings_shell_host.dart';
import 'support/surface_size.dart';

final Set<SettingCapability> _all = SettingCapability.values.toSet();

Future<void> _golden(
  WidgetTester tester, {
  required String name,
  required Size size,
  required bool advanced,
  PlatformCapabilities platform = const PlatformCapabilities(),
  String? section,
  int tabs = 0,
  bool captureFocusRing = false,
  Future<int> Function()? onClearCache,
}) async {
  await setLogicalSize(tester, size);
  final settings = AppSettings(MemorySettingsStore());
  await settings.setShowAdvanced(advanced);
  await settings.setShowExpert(advanced);
  await pumpSettings(
    tester,
    settings,
    available: _all,
    platform: platform,
    onClearCache: onClearCache,
  );
  if (section != null) {
    await tester.tap(find.byKey(ValueKey<String>('section-$section')));
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < tabs; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  await expectLater(
    captureFocusRing
        ? find.byKey(const ValueKey<String>('settings-focus-capture'))
        : find.byType(SettingsScreen),
    matchesGoldenFile('goldens/settings_shell_$name.png'),
  );
}

void main() {
  for (final advanced in const [false, true]) {
    final tier = advanced ? 'advanced' : 'basic';
    testWidgets('desktop $tier', (tester) async {
      await _golden(
        tester,
        name: 'desktop_$tier',
        size: const Size(1280, 800),
        advanced: advanced,
        section: 'video',
      );
    });
    testWidgets('phone section $tier', (tester) async {
      await _golden(
        tester,
        name: 'phone_section_$tier',
        size: const Size(400, 800),
        advanced: advanced,
        platform: const PlatformCapabilities.touch(),
        section: 'video',
      );
    });
    testWidgets('tv section $tier', (tester) async {
      await _golden(
        tester,
        name: 'tv_section_$tier',
        size: const Size(1920, 1080),
        advanced: advanced,
        platform: const PlatformCapabilities.directionalPad(),
        section: 'video',
        tabs: 2, // back button, then the first setting
      );
    });
  }
  testWidgets('desktop section list', (tester) async {
    await _golden(
      tester,
      name: 'desktop_list_basic',
      size: const Size(1280, 800),
      advanced: false,
    );
  });
  testWidgets('phone section list', (tester) async {
    await _golden(
      tester,
      name: 'phone_list_advanced',
      size: const Size(400, 800),
      advanced: true,
      platform: const PlatformCapabilities.touch(),
    );
  });
  testWidgets('tv section list', (tester) async {
    await _golden(
      tester,
      name: 'tv_list_basic',
      size: const Size(1920, 1080),
      advanced: false,
      platform: const PlatformCapabilities.directionalPad(),
      tabs: 1,
      captureFocusRing: true,
    );
  });
  testWidgets('desktop streaming basic', (tester) async {
    await _golden(
      tester,
      name: 'desktop_streaming_basic',
      size: const Size(1280, 800),
      advanced: false,
      section: 'streaming',
      onClearCache: () async => 0,
    );
  });
  testWidgets('desktop numbers', (tester) async {
    await _golden(
      tester,
      name: 'desktop_numbers_advanced',
      size: const Size(1280, 800),
      advanced: true,
      section: 'streaming',
    );
  });
  testWidgets('phone numbers', (tester) async {
    await _golden(
      tester,
      name: 'phone_numbers_advanced',
      size: const Size(400, 800),
      advanced: true,
      platform: const PlatformCapabilities.touch(),
      section: 'downloads',
    );
  });
}
