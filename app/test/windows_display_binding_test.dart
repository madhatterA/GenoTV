import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:ui/ui.dart';
import 'package:video_player/ui_bindings.dart';

// Kodi Windows 4.1: Default (the primary monitor) + friendly monitor names.
const _single = {
  'supported': true,
  'choices': {'': 'Default', 'Surface Display': 'Surface Display'},
  'selected': '',
};

final class _ScreenChannel implements PlatformChannel {
  Object? response = _single;
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
              diagnostics: const {'os': 'windows'},
            ),
            displayScreens: DisplayScreenService(channel: channel),
            logger: MemoryLogger(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saved monitor that is gone falls back to Default (primary)', (
    tester,
  ) async {
    await settings.values.write(settingById('display.monitor'), 'DELL U2720Q');
    await open(tester);
    expect(settings.values.read<String>(settingById('display.monitor')), '');
    final screen = tester.widget<SettingsScreen>(find.byType(SettingsScreen));
    expect(screen.displayChoices, {
      '': 'Default',
      'Surface Display': 'Surface Display',
    });
    expect(screen.available, contains(SettingCapability.multipleDisplays));
    await tester.tap(find.byKey(const ValueKey<String>('section-display')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('setting-display.monitor')),
      findsOneWidget,
    );
  });
}
