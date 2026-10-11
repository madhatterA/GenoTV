import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/ui.dart';
import 'package:ui/src/settings/settings_controls.dart';

void main() {
  Future<AppSettings> showSettings(
    WidgetTester tester, {
    String os = 'ios',
    SettingSection? section = SettingSection.display,
    ValueListenable<Map<String, String>>? displayChoicesListenable,
    Set<SettingCapability> available = const {
      SettingCapability.multipleDisplays,
    },
    Map<String, String> displays = const {
      '': 'Default',
      'Touchscreen': 'Touchscreen',
    },
  }) async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: SettingsScreen(
          settings: settings,
          section: section,
          available: available,
          capabilities: CapabilityReport(
            hardwareDecode: false,
            decoders: [],
            hdrOutput: false,
            hdrFormats: [],
            displayModeSwitching: false,
            audioPassthrough: false,
            passthroughFormats: [],
            diagnostics: {'os': os},
          ),
          displayChoices: displays,
          displayChoicesListenable: displayChoicesListenable,
        ),
      ),
    );
    return settings;
  }

  const monitorKey = ValueKey('setting-display.monitor');
  Finder monitor() => find.byKey(monitorKey);

  testWidgets('iOS single screen offers Default and Touchscreen', (
    tester,
  ) async {
    await showSettings(tester);
    final row = tester.widget<SettingRow>(monitor());
    expect(row.choices, {'': 'Default', 'Touchscreen': 'Touchscreen'});
    await tester.ensureVisible(monitor());
    await tester.tap(monitor());
    await tester.pumpAndSettle();
    expect(find.text('Default'), findsWidgets);
    expect(find.text('Touchscreen'), findsOneWidget);
    expect(find.text('External'), findsNothing);
  });

  testWidgets('iOS connected external screen persists its actual monitor key', (
    tester,
  ) async {
    final settings = await showSettings(
      tester,
      displays: const {
        '': 'Default',
        'Touchscreen': 'Touchscreen',
        'External': 'External',
      },
    );
    await tester.ensureVisible(monitor());
    await tester.tap(monitor());
    await tester.pumpAndSettle();
    expect(find.text('External'), findsOneWidget);
    await tester.tap(find.text('External'));
    await tester.pumpAndSettle();
    expect(
      settings.values.read<String>(settingById('display.monitor')),
      'External',
    );
  });

  testWidgets('iOS Touchscreen choice persists its actual monitor key', (
    tester,
  ) async {
    final settings = await showSettings(tester);
    await tester.ensureVisible(monitor());
    await tester.tap(monitor());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Touchscreen'));
    await tester.pumpAndSettle();
    expect(
      settings.values.read<String>(settingById('display.monitor')),
      'Touchscreen',
    );
  });

  testWidgets('Display category forwards monitor choices', (tester) async {
    await showSettings(tester, section: null);
    await tester.tap(find.byKey(const ValueKey('section-display')));
    await tester.pumpAndSettle();
    expect(tester.widget<SettingRow>(monitor()).choices, {
      '': 'Default',
      'Touchscreen': 'Touchscreen',
    });
  });

  testWidgets('Pushed Display category updates on external disconnect', (
    tester,
  ) async {
    final displays = ValueNotifier<Map<String, String>>({
      '': 'Default',
      'Touchscreen': 'Touchscreen',
      'External': 'External',
    });
    addTearDown(displays.dispose);
    await showSettings(
      tester,
      section: null,
      displayChoicesListenable: displays,
    );
    await tester.tap(find.byKey(const ValueKey('section-display')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingRow>(monitor()).choices,
      containsPair('External', 'External'),
    );
    displays.value = {'': 'Default', 'Touchscreen': 'Touchscreen'};
    await tester.pump();
    expect(tester.widget<SettingRow>(monitor()).choices, {
      '': 'Default',
      'Touchscreen': 'Touchscreen',
    });
  });

  testWidgets('Android without monitor capability omits the picker', (
    tester,
  ) async {
    await showSettings(tester, os: 'android', available: const {});
    expect(monitor(), findsNothing);
  });
}
