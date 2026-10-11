import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:ui/ui.dart';
import 'package:video_player/ui_bindings.dart';

const _touchscreen = {
  'supported': true,
  'choices': {'': 'Default', 'Touchscreen': 'Touchscreen'},
  'selected': 'Touchscreen',
};
const _external = {
  'supported': true,
  'choices': {
    '': 'Default',
    'Touchscreen': 'Touchscreen',
    'External': 'External',
  },
  'selected': 'External',
};

final class _ScreenChannel implements PlatformChannel {
  Object? response = _touchscreen;
  PlatformException? failure;
  final eventsController = StreamController<Object?>.broadcast();

  @override
  Future<Object?> invoke(String method, [Object? arguments]) async {
    if (failure case final error?) throw error;
    return response;
  }

  @override
  Stream<Object?> get events => eventsController.stream;

  @override
  Future<void> dispose() => eventsController.close();
}

void main() {
  late AppSettings settings;
  late _ScreenChannel channel;

  setUp(() async {
    settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    channel = _ScreenChannel();
  });
  tearDown(() async {
    await channel.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppStrings.localizationsDelegates,
        supportedLocales: AppStrings.supportedLocales,
        theme: AppTheme.dark(tv: false),
        home: Scaffold(
          body: SettingsDestination(
            settings: settings,
            probe: () async => CapabilityReport(
              hardwareDecode: true,
              decoders: const ['h264'],
              hdrOutput: false,
              hdrFormats: const [],
              displayModeSwitching: false,
              audioPassthrough: false,
              passthroughFormats: const [],
              diagnostics: const {'os': 'ios'},
            ),
            displayScreens: DisplayScreenService(channel: channel),
            logger: MemoryLogger(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saved disconnected External normalizes to Touchscreen', (
    tester,
  ) async {
    await settings.values.write(settingById('display.monitor'), 'External');
    await open(tester);
    expect(
      settings.values.read<String>(settingById('display.monitor')),
      'Touchscreen',
    );
    final screen = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(screen.displayChoices, {
      '': 'Default',
      'Touchscreen': 'Touchscreen',
    });
    expect(screen.available, contains(SettingCapability.multipleDisplays));
    await tester.tap(find.byKey(const ValueKey<String>('section-display')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('setting-display.monitor')),
      findsOneWidget,
    );
  });

  testWidgets('disconnect updates the open display page choices', (
    tester,
  ) async {
    channel.response = _external;
    await settings.values.write(settingById('display.monitor'), 'External');
    await open(tester);
    await tester.tap(find.byKey(const ValueKey<String>('section-display')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).displayChoices,
      contains('External'),
    );
    channel.response = _touchscreen;
    channel.eventsController.add({
      'event': 'displayScreensChanged',
      ..._touchscreen,
    });
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('setting-display.monitor')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('choice-option-External')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('choice-option-Touchscreen')),
      findsOneWidget,
    );
  });

  testWidgets('selection failure surfaces ErrorView', (tester) async {
    channel.response = _external;
    await settings.values.write(settingById('display.monitor'), 'External');
    await open(tester);
    channel.failure = PlatformException(code: 'display.unavailable');
    await settings.values.write(settingById('display.monitor'), 'Touchscreen');
    await tester.pumpAndSettle();
    expect(find.byType(ErrorView), findsOneWidget);
    expect(find.byType(SettingsScreen), findsNothing);
  });
}
