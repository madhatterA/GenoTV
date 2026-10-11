import 'package:ui/src/components/app_switch.dart';
import 'package:contracts/contracts.dart' show AudioDevice, AudioDeviceKind;
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui/src/settings/settings_catalog.dart';
import 'package:ui/ui.dart';

import 'support/settings_shell_host.dart';
import 'support/surface_size.dart';

final Set<SettingCapability> _all = SettingCapability.values.toSet();

Finder _key(String key) => find.byKey(ValueKey<String>(key));

Future<void> _openSection(WidgetTester tester, SettingSection s) async {
  if (_key('section-${s.name}').evaluate().isEmpty) {
    Navigator.of(tester.element(find.byType(SettingsScreen).last)).pop();
    await tester.pumpAndSettle();
  }
  await tester.tap(_key('section-${s.name}'));
  await tester.pumpAndSettle();
}

/// Keys of the schema rows currently built.
Set<String> _renderedIds(WidgetTester tester) => {
  for (final w in tester.widgetList(
    find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('setting-'),
    ),
  ))
    (w.key as ValueKey<String>).value.substring('setting-'.length),
};

/// The nearest keyed ancestor of the focused widget: the control it belongs to.
String? _focusedKey() {
  String? found;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((e) {
    final key = e.widget.key;
    if (key is ValueKey<String>) {
      found = key.value;
      return false;
    }
    return true;
  });
  return found;
}

void audioSettingsTests() {
  testWidgets(
    'audio devices use real IDs and missing saved choice shows Auto note',
    (tester) async {
      await setLogicalSize(tester, const Size(1280, 3000));
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('audio.outputDevice'),
        'coreaudio/missing',
      );
      await pumpSettings(
        tester,
        settings,
        available: _all,
        audioDevices: [
          AudioDevice(
            id: 'coreaudio/speakers',
            name: 'Mac speakers',
            kind: AudioDeviceKind.speaker,
          ),
        ],
      );
      await _openSection(tester, SettingSection.audio);
      expect(
        find.text('Saved audio device unavailable; using Auto.'),
        findsOneWidget,
      );
      await tester.tap(_key('setting-audio.outputDevice'));
      await tester.pumpAndSettle();
      expect(find.text('Mac speakers'), findsOneWidget);
      expect(_key('choice-option-coreaudio/speakers'), findsOneWidget);
      await tester.tap(_key('choice-option-coreaudio/speakers'));
      await tester.pumpAndSettle();
      expect(
        settings.values.read<String>(settingById('audio.outputDevice')),
        'coreaudio/speakers',
      );
      expect(
        find.text('Saved audio device unavailable; using Auto.'),
        findsNothing,
      );
    },
  );
  testWidgets(
    'Enabled without receiver carriers shows note even with metadata checked',
    (tester) async {
      await setLogicalSize(tester, const Size(1280, 3000));
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(true);
      await settings.values.write(settingById('audio.passthrough'), 'Enabled');
      for (final id in ['dolbyDigital', 'ddPlus', 'dts', 'trueHd', 'dtsHd']) {
        await settings.values.write(
          settingById('audio.receiver.$id'),
          'Disabled',
        );
      }
      await settings.values.write(
        settingById('audio.receiver.atmos'),
        'Enabled',
      );
      await pumpSettings(tester, settings, available: _all);
      await _openSection(tester, SettingSection.audio);
      expect(
        find.textContaining('No receiver formats selected'),
        findsOneWidget,
      );
      await tester.tap(_key('setting-audio.receiver.dolbyDigital'));
      await tester.pumpAndSettle();
      await tester.tap(_key('choice-option-Enabled'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No receiver formats selected'), findsNothing);
    },
  );
}

void cacheSettingsTests() {
  testWidgets('cache size limit offers five choices; Clear cache shows freed', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 3000));
    var calls = 0;
    await pumpSettings(
      tester,
      AppSettings(MemorySettingsStore()),
      available: _all,
      onClearCache: () async {
        calls++;
        return 1536 * 1024 * 1024;
      },
    );
    await _openSection(tester, SettingSection.streaming);
    final def = settingById('streaming.cacheSizeLimit');
    expect(def.choices, ['Auto', '2 GB', '5 GB', '10 GB', '20 GB']);
    expect(_renderedIds(tester), contains(def.id));
    await tester.tap(_key('clear-cache'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Freed 1.5 GB'), findsOneWidget);
  });
}

void main() {
  audioSettingsTests();
  cacheSettingsTests();
  test('settings the bundled engine cannot honour no longer exist', () {
    final ids = settingDefs.map((d) => d.id).toSet();
    expect(ids.intersection(retiredSettingKeys.toSet()), isEmpty);
  });

  testWidgets('tier toggles and capabilities show exactly the schema defs', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 3000));
    for (final (advanced, expert, available)
        in <(bool, bool, Set<SettingCapability>)>[
          (false, false, _all),
          (true, false, _all),
          (true, true, _all),
          (
            false,
            true,
            _all,
          ), // Expert is kept but hidden while Advanced is off.
          (true, true, <SettingCapability>{}),
          (false, false, <SettingCapability>{}),
        ]) {
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(advanced);
      await settings.setShowExpert(expert);
      await pumpSettings(tester, settings, available: available);

      expect(_key('advanced-toggle'), findsOneWidget);
      expect(_key('expert-toggle'), advanced ? findsOneWidget : findsNothing);

      var total = 0;
      for (final section in SettingSection.values) {
        final expected = <String>{
          for (final d in settingDefs)
            if ((d.section == section || d.alsoIn.contains(section)) &&
                (d.requires == SettingCapability.none ||
                    available.contains(d.requires)) &&
                (d.tier == SettingTier.basic ||
                    (d.tier == SettingTier.advanced && advanced) ||
                    (d.tier == SettingTier.expert && advanced && expert)))
              d.id,
        };
        if (section == SettingSection.advanced && !advanced) {
          expect(_key('section-${section.name}'), findsNothing);
          continue;
        }
        expect(_key('section-${section.name}'), findsOneWidget);
        await _openSection(tester, section);
        final rendered = _renderedIds(tester);
        expect(
          rendered,
          expected,
          reason: '$section adv=$advanced exp=$expert',
        );
        expect(find.text('Live'), findsNothing);
        for (final id in expected) {
          final def = settingById(id);
          for (final (apply, label) in [
            (SettingApply.nextVideo, 'Applies on next playback'),
            (SettingApply.restart, 'Restart needed'),
          ]) {
            expect(
              find.descendant(
                of: _key('setting-$id'),
                matching: find.text(label),
              ),
              def.apply == apply && def.kind != SettingKind.page
                  ? findsOneWidget
                  : findsNothing,
            );
          }
        }
        total += rendered.length;
        Navigator.of(tester.element(find.byType(SettingsScreen).last)).pop();
        await tester.pumpAndSettle();
      }
      expect(total, greaterThan(0));
    }
  });

  testWidgets('each value kind persists and survives rebuilding the screen', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 3000));
    final store = MemorySettingsStore();
    final settings = AppSettings(store);
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await pumpSettings(tester, settings, available: _all);

    // toggle (default true), choice, number
    await _openSection(tester, SettingSection.playback);
    await tester.tap(_key('setting-playback.autoPlayNext'));
    await tester.pumpAndSettle();
    await tester.tap(_key('setting-playback.resume'));
    await tester.pumpAndSettle();
    await tester.tap(_key('choice-option-Always'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(_key('Playback speed-Increase'));
      await tester.pumpAndSettle();
    }
    expect(find.text('1.5 ×'), findsOneWidget);
    // text, path
    await _openSection(tester, SettingSection.video);
    await tester.tap(_key('setting-video.decoder'));
    await tester.pumpAndSettle();
    await tester.tap(_key('choice-option-hardware'));
    await tester.pumpAndSettle();
    await _openSection(tester, SettingSection.downloads);
    await tester.enterText(
      find.descendant(
        of: _key('setting-downloads.tracker'),
        matching: find.byType(TextField),
      ),
      '/tmp/dl',
    );
    // list
    await _openSection(tester, SettingSection.languages);
    await tester.tap(_key('list-option-lossless'));
    await tester.pumpAndSettle();
    final values = SettingsValues(store);
    expect(values.read<bool>(settingById('playback.autoPlayNext')), true);
    expect(values.read<String>(settingById('playback.resume')), 'Always');
    expect(values.read<double>(settingById('playback.speed')), 1.5);
    expect(values.read<String>(settingById('video.decoder')), 'hardware');
    expect(values.read<String>(settingById('downloads.tracker')), '/tmp/dl');
    expect(
      values.read<List<String>>(settingById('languages.preferBestAudio')),
      ['lossless'],
    );

    // Rebuild the whole screen over the same store.
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpSettings(tester, AppSettings(store), available: _all);
    await _openSection(tester, SettingSection.playback);
    expect(find.text('Always'), findsOneWidget);
    expect(find.text('1.5 ×'), findsOneWidget);
    expect(
      tester
          .widget<AppSwitch>(
            find.descendant(
              of: _key('setting-playback.autoPlayNext'),
              matching: find.byType(AppSwitch),
            ),
          )
          .value,
      true,
    );
    await _openSection(tester, SettingSection.languages);
    expect(
      find.descendant(
        of: _key('list-option-lossless'),
        matching: find.byIcon(PhosphorIconsFill.checkSquare),
      ),
      findsOneWidget,
    );
  });

  testWidgets('skip-forward keeps its storage key', (tester) async {
    await setLogicalSize(tester, const Size(1280, 800));
    final settings = AppSettings(MemorySettingsStore());
    await pumpSettings(tester, settings);
    await _openSection(tester, SettingSection.playback);
    await tester.tap(_key('skip-forward-setting'));
    await tester.pumpAndSettle();
    await tester.tap(_key('choice-option-60'));
    await tester.pumpAndSettle();
    expect(settings.skipForward, const Duration(seconds: 60));
  });

  testWidgets(
    'Tab and arrows reach every visible control in order; Enter activates',
    (tester) async {
      await setLogicalSize(tester, const Size(1280, 3000));
      final settings = AppSettings(MemorySettingsStore());
      await settings.setShowAdvanced(true);
      await settings.setShowExpert(true);
      await pumpSettings(tester, settings, available: _all);
      await _openSection(tester, SettingSection.languages);

      final defs = visibleSettings(
        SettingSection.languages,
        showAdvanced: true,
        showExpert: true,
        available: _all,
      );
      final expected = <String>[
        for (final d in defs)
          if (d.kind == SettingKind.list)
            for (final o in d.choices) 'list-option-$o'
          else
            'setting-${d.id}',
      ];

      // Start at Back so traversal assertions do not depend on pointer entry focus.
      Focus.of(tester.element(find.byIcon(PhosphorIconsRegular.arrowLeft)))
          .requestFocus();
      await tester.pump();
      expect(_focusedKey(), 'top-back');
      final order = <String>[];
      for (var i = 0; i < expected.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(_focusedKey()!);
      }
      expect(order, expected);

      // Arrow-down (D-pad) moves between category rows.
      Navigator.of(tester.element(find.byType(SettingsScreen).last)).pop();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(_focusedKey(), isNot('section-playback'));

      // Enter on the Advanced toggle activates it.
      await tester.pumpWidget(const SizedBox.shrink());
      final fresh = AppSettings(MemorySettingsStore());
      await pumpSettings(tester, fresh);
      for (var i = 0; i < 20 && _focusedKey() != 'advanced-toggle'; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(_focusedKey(), 'advanced-toggle');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(fresh.showAdvanced, isTrue);
      expect(_key('expert-toggle'), findsOneWidget);
    },
  );

  testWidgets('all widths show categories and push a separate category route', (
    tester,
  ) async {
    for (final (size, platform) in <(Size, PlatformCapabilities)>[
      (const Size(400, 800), const PlatformCapabilities.touch()),
      (const Size(1280, 800), const PlatformCapabilities()),
      (const Size(1920, 1080), const PlatformCapabilities.directionalPad()),
    ]) {
      await setLogicalSize(tester, size);
      await pumpSettings(
        tester,
        AppSettings(MemorySettingsStore()),
        available: _all,
        platform: platform,
      );
      expect(_key('section-video'), findsOneWidget);
      expect(_key('setting-video.aspectRatio'), findsNothing);
      await tester.tap(_key('section-video'));
      await tester.pumpAndSettle();
      expect(_key('setting-video.aspectRatio'), findsOneWidget);
      expect(_key('section-video'), findsNothing);
      final navigator = Navigator.of(
        tester.element(_key('setting-video.aspectRatio')),
      );
      expect(navigator.canPop(), isTrue);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(_key('section-video'), findsOneWidget);
    }
  });

  testWidgets('unset numbers read Auto and step up to the first value', (
    tester,
  ) async {
    await setLogicalSize(tester, const Size(1280, 3000));
    final settings = AppSettings(MemorySettingsStore());
    await settings.setShowAdvanced(true);
    await settings.setShowExpert(true);
    await pumpSettings(tester, settings, available: _all);
    await _openSection(tester, SettingSection.streaming);
    expect(find.text('Auto'), findsWidgets);
    expect(find.text('0 MB'), findsNothing);
    await tester.tap(_key('Buffer size-Increase'));
    await tester.pumpAndSettle();
    expect(find.text('16 MB'), findsOneWidget);
  });

  testWidgets(
    'stepper clamps and only deferred settings show application notes',
    (tester) async {
      await setLogicalSize(tester, const Size(1280, 3000));
      final store = MemorySettingsStore();
      await pumpSettings(tester, AppSettings(store), available: _all);
      await _openSection(tester, SettingSection.playback);
      expect(find.text('Live'), findsNothing);
      expect(find.textContaining('Live settings'), findsNothing);
      for (final def in visibleSettings(
        SettingSection.playback,
        showAdvanced: false,
        showExpert: false,
        available: _all,
      )) {
        expect(
          find.descendant(
            of: _key('setting-${def.id}'),
            matching: find.text('Applies on next playback'),
          ),
          def.apply == SettingApply.nextVideo && def.kind != SettingKind.page
              ? findsOneWidget
              : findsNothing,
        );
      }
      for (var i = 0; i < 20; i++) {
        await tester.tap(_key('Playback speed-Increase'), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(find.text('4 ×'), findsOneWidget);
      for (var i = 0; i < 20; i++) {
        await tester.tap(_key('Playback speed-Decrease'), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(find.text('0.25 ×'), findsOneWidget);
      expect(
        SettingsValues(store).read<double>(settingById('playback.speed')),
        0.25,
      );
    },
  );
}
