import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/player_settings.dart';
import 'package:video_player/playback_session.dart';

import 'support/subtitle_clip.dart';

void main() {
  late Directory dir;
  late File clip, cp;
  final rows = <String>[];
  setUpAll(() async {
    final fixture = await subtitleClip();
    dir = fixture.$1;
    clip = fixture.$2;
    cp = fixture.$3;
  });
  tearDownAll(() async {
    try {
      await File('${dir.path}/readback.md').writeAsString(
        '| Setting | Value | Property | Expected | Got | Result |\n'
        '| --- | --- | --- | --- | --- | --- |\n${rows.join('\n')}\n',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('every subtitle def and choice reads back while playing', () async {
    final settings = AppSettings(MemorySettingsStore());
    final (controller, backend) = subtitleEngine();
    bool same(String expected, String got) =>
        expected.toLowerCase() == got.toLowerCase() ||
        (num.tryParse(expected) != null &&
            num.tryParse(got) != null &&
            (num.parse(expected) - num.parse(got)).abs() < 0.00001);
    try {
      await controller.open(
        clip.uri,
        engineOptions: subtitleEngineOptionsFor(settings.values),
      );
      await controller.play();
      for (final def in subtitleSettingDefs) {
        final choices = switch (def.kind) {
          SettingKind.toggle => <Object>[true, false],
          SettingKind.choice => <Object>[...def.choices],
          SettingKind.text => <Object>['', 'Arial', 'Helvetica'],
          SettingKind.number => <Object>[
            for (
              var i = 0;
              i <= ((def.max! - def.min!) / def.step!).round();
              i++
            )
              double.parse((def.min! + i * def.step!).toStringAsFixed(4)),
          ],
          _ => throw StateError('Uncovered mapped setting ${def.id}'),
        };
        for (final value in choices) {
          await settings.values.write(def, value);
          final options = subtitleEngineOptionsFor(
            settings.values,
            scope: {def},
          );
          await controller.setEngineOptions(options);
          for (final entry in options.entries) {
            final got = await backend.getProperty(entry.key);
            final ok = same(entry.value, got);
            rows.add(
              '| ${def.id} | $value | ${entry.key} | ${entry.value} | $got | ${ok ? 'PASS' : 'FAIL'} |',
            );
            expect(ok, true, reason: '${def.id}=$value ${entry.key}: $got');
          }
        }
      }
    } finally {
      await controller.dispose();
      settings.values.dispose();
    }
  });
  test('Persian CP1256 external SRT decodes with Auto and explicit CP1256', () async {
    final output = <String>[];
    for (final encoding in ['auto', 'cp1256']) {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(settingById('subtitles.encoding'), encoding);
      final (controller, backend) = subtitleEngine();
      try {
        await controller.open(
          clip.uri,
          engineOptions: subtitleEngineOptionsFor(settings.values),
        );
        await controller.addExternalSubtitle(cp.uri);
        expect(await backend.getProperty('sub-codepage'), 'cp1256');
        await controller.seek(const Duration(milliseconds: 300));
        await controller.play();
        await controller.state
            .firstWhere((s) => s.position > const Duration(milliseconds: 300))
            .timeout(const Duration(seconds: 3));
        await controller.pause();
        final text = await backend.getProperty('sub-text');
        output.add(
          '$encoding: expected=$persianText; got=$text; ${text.trim() == persianText ? 'PASS' : 'FAIL'}',
        );
        await File('${dir.path}/encoding.txt')
            .writeAsString('${output.join('\n')}\n');
        expect(text.trim(), persianText, reason: encoding);
        await controller.setEngineOptions({'sub-codepage': 'auto'});
        expect(await backend.getProperty('sub-codepage'), 'cp1256');
        await controller.seek(const Duration(milliseconds: 400));
        await controller.play();
        await controller.state
            .firstWhere((s) => s.position > const Duration(milliseconds: 400))
            .timeout(const Duration(seconds: 3));
        await controller.pause();
        expect((await backend.getProperty('sub-text')).trim(), persianText);
      } finally {
        await controller.dispose();
        settings.values.dispose();
      }
    }
  });
  test('saved subtitle Off survives the Kodi default change', () async {
    final store = MemorySettingsStore();
    await store.write('playback.preferredSubtitleLanguage', '');
    final settings = AppSettings(store);
    await settings.load();
    expect(settings.values.read<String>(preferredSubtitleLanguageSetting), '');
    await settings.values.write(preferredSubtitleLanguageSetting, '');
    expect(store.read('playback.preferredSubtitleLanguage'), '');
    settings.values.dispose();
  });
  test('Kodi defaults preserve saved user values', () async {
    final store = MemorySettingsStore();
    final settings = AppSettings(store);
    expect(
      settings.values.read<String>(preferredSubtitleLanguageSetting),
      'forced_only',
    );
    expect(
      settings.values.read<bool>(
        settingById('languages.preferForcedSubtitles'),
      ),
      isTrue,
    );
    final options = subtitleEngineOptionsFor(settings.values);
    expect(options['sub-font'], 'DejaVu Sans');
    expect(options['sub-font-size'], '42.0');
    expect(options['sub-border-size'], '2.5');
    expect(options['sub-margin-y'], '36');
    await store.write('subtitles.font', 'Arial');
    await store.write('subtitles.border', '7');
    await store.write('subtitles.position', '80');
    await store.write('playback.preferredSubtitleLanguage', 'fr');
    await store.write('languages.preferForcedSubtitles', 'false');
    await settings.load();
    final saved = subtitleEngineOptionsFor(settings.values);
    expect(saved['sub-font'], 'Arial');
    expect(saved['sub-border-size'], '7.0');
    expect(saved['sub-pos'], '80');
    expect(settings.preferredSubtitleLanguage, 'fr');
    expect(
      settings.values.read<bool>(
        settingById('languages.preferForcedSubtitles'),
      ),
      isFalse,
    );
    settings.values.dispose();
  });
  test('session applies look live and freezes track rules until next video', () async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.values.write(settingById('subtitles.delay'), 0.5);
    await settings.values.write(settingById('subtitles.position'), 80.0);
    final (controller, backend) = subtitleEngine(resolve: clip.uri);
    final session = PlaybackSession(
      media: const MediaItem(id: 'live', title: 'live', kind: MediaKind.movie),
      streamSource: FakeStreamSource(),
      source: SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://test/clip'),
      ),
      controllerFactory: () => controller,
      settings: settings,
      logger: MemoryLogger(),
    );
    try {
      await session.start();
      await session.defaultsDone;
      expect(await backend.getProperty('sub-delay'), '0.500000');
      expect(await backend.getProperty('sub-pos'), '80');
      final originalAudio = await backend.getProperty('aid');
      await settings.setPreferredAudioLanguage('fr');
      await settings.values.write(settingById('subtitles.delay'), 1.0);
      await settings.values.write(settingById('subtitles.position'), 70.0);
      // setEngineOptions uses the same serialized tail as the change listener.
      await Future<void>.value();
      await controller.setEngineOptions({});
      expect(await backend.getProperty('sub-delay'), '1.000000');
      expect(await backend.getProperty('sub-pos'), '70');
      expect(await backend.getProperty('aid'), originalAudio);
    } finally {
      await session.dispose();
      settings.values.dispose();
    }
  });
}
