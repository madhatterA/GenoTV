import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

String _cell(Object? v) => '$v'.replaceAll('|', '/');

Object _nonDefault(SettingDef d) {
  switch (d.kind) {
    case SettingKind.toggle:
      return d.defaultValue != 'true';
    case SettingKind.number:
      final v = double.parse(d.defaultValue);
      return v + d.step! <= d.max! ? v + d.step! : v - d.step!;
    case SettingKind.choice:
      return d.choices.isEmpty
          ? 'device'
          : d.choices.firstWhere((c) => c != d.defaultValue);
    case SettingKind.list:
      final all = d.choices.toList();
      return d.defaultValue == all.join(',') ? <String>[] : all;
    case SettingKind.text:
      if (d.id == 'languages.trackPriority') return 'lang:fr,channels';
      return '${d.defaultValue}x';
    case SettingKind.path:
      return '${d.defaultValue}x';
    case SettingKind.page:
      throw StateError('no value');
  }
}

void main() {
  for (final entry in {
    'audio.outputMode': 'Optimized',
    'audio.deviceKeepAlive': 'true',
    'playback.autoPlayNext': 'false',
  }.entries) {
    test('Kodi default ${entry.key}; stored choices retained', () async {
      final def = settingById(entry.key);
      expect(def.defaultValue, entry.value);
      final store = MemorySettingsStore();
      await store.write(
        def.id,
        def.kind == SettingKind.toggle ? 'false' : def.choices.first,
      );
      final values = SettingsValues(store);
      expect(
        values.read<Object>(def),
        def.kind == SettingKind.toggle ? false : def.choices.first,
      );
      values.dispose();
    });
  }

  final source = File('test/fixtures/settings_source_items.txt')
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();

  test('every owner §1 item is claimed; every setting claims real items', () {
    expect(
      source.toSet(),
      hasLength(source.length),
      reason: 'fixture lines unique',
    );
    final claims = <String, List<SettingDef>>{};
    for (final d in settingDefs) {
      expect(d.sourceItems, isNotEmpty, reason: '${d.id} claims no item');
      for (final item in d.sourceItems) {
        claims.putIfAbsent(item, () => []).add(d);
      }
    }
    expect(
      claims.keys.where((k) => !source.contains(k)),
      isEmpty,
      reason: 'claimed items not in the source',
    );
    expect(
      source.where((s) => !claims.containsKey(s)),
      isEmpty,
      reason: 'source items nobody claims',
    );
    // Several defs may split one source item, but then they claim exactly it
    // (no def spans two different source items while sharing a line).
    for (final defs in claims.values) {
      for (final d in defs) {
        expect(d.sourceItems, defs.first.sourceItems, reason: d.id);
      }
    }
    expect(settingDefs.map((d) => d.id).toSet(), hasLength(settingDefs.length));
  });

  test(
    'defs are well formed: defaults valid, choices present, tiers per prefix',
    () {
      final values = SettingsValues(
        MemorySettingsStore(),
        logger: MemoryLogger(),
      );
      for (final d in settingDefs) {
        if (d.kind == SettingKind.choice && d.id != 'audio.outputDevice') {
          expect(d.choices, isNotEmpty, reason: d.id);
        }
        if (d.kind == SettingKind.number) {
          expect(d.min, isNotNull, reason: '${d.id} min');
          expect(d.max, isNotNull, reason: '${d.id} max');
          expect(d.step, isNotNull, reason: '${d.id} step');
          expect(d.unit, isNotNull, reason: '${d.id} unit');
          final v = double.parse(d.defaultValue);
          expect(v, inInclusiveRange(d.min!, d.max!), reason: d.id);
        }
        if (d.kind == SettingKind.page) continue;
        expect(() => values.read<Object>(d), returnsNormally, reason: d.id);
        final prefix = d.sourceItems.first.split(' | ').last;
        // Receiver codecs are unprefixed in the source but only matter with
        // passthrough (Advanced): owner ruling.
        final expected = prefix.startsWith('Receiver supports:')
            ? SettingTier.advanced
            : prefix.startsWith('Exp:')
            ? SettingTier.expert
            : prefix.startsWith('Adv:')
            ? SettingTier.advanced
            : SettingTier.basic;
        if (d.sourceItems.length == 1 && d.section != SettingSection.advanced) {
          expect(d.tier, expected, reason: d.id);
        }
      }
    },
  );

  Future<void> roundTrip(
    SettingsStore Function() open,
    Future<void> Function() flush,
  ) async {
    final store = open();
    await store.load();
    final values = SettingsValues(store, logger: MemoryLogger());
    for (final d in settingDefs.where((d) => d.kind != SettingKind.page)) {
      final defaultValue = values.read<Object>(d);
      await values.write(d, defaultValue);
      expect(values.read<Object>(d), defaultValue, reason: '${d.id} default');
      final other = _nonDefault(d);
      await values.write(d, other);
      final back = values.read<Object>(d);
      expect(
        back,
        other is num ? other.toDouble() : other,
        reason: '${d.id} non-default',
      );
      await values.reset(d);
      expect(values.read<Object>(d), defaultValue, reason: '${d.id} reset');
      await values.write(d, other);
    }
    await flush();
  }

  test(
    'every def round-trips default and non-default in MemorySettingsStore',
    () async {
      final store = MemorySettingsStore();
      await roundTrip(() => store, () async {});
    },
  );

  test(
    'every def round-trips default and non-default in JsonSettingsStore',
    () async {
      final dir = await Directory.systemTemp.createTemp('settings-schema-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/settings.json');
      late JsonSettingsStore store;
      await roundTrip(
        () => store = JsonSettingsStore(file: file, logger: MemoryLogger()),
        () => store.dispose(),
      );
      final reopened = JsonSettingsStore(file: file, logger: MemoryLogger());
      await reopened.load();
      final values = SettingsValues(reopened, logger: MemoryLogger());
      for (final d in settingDefs.where((d) => d.kind != SettingKind.page)) {
        final other = _nonDefault(d);
        expect(
          values.read<Object>(d),
          other is num ? other.toDouble() : other,
          reason: '${d.id} persisted',
        );
      }
      await reopened.dispose();
    },
  );

  test(
    'invalid stored value warns and yields the default; invalid write throws',
    () async {
      final store = MemorySettingsStore();
      final logger = MemoryLogger();
      final values = SettingsValues(store, logger: logger);
      final speed = settingById('playback.speed');
      await store.write(speed.id, 'fast');
      expect(values.read<double>(speed), 1.0);
      expect(
        logger.records.where((r) => r.level == LogLevel.warn),
        hasLength(1),
      );
      expect(() => values.write(speed, 'fast'), throwsArgumentError);
      expect(
        () => values.write(settingById('playback.resume'), 'Sometimes'),
        throwsArgumentError,
      );
      expect(
        () => values.read<Object>(settingById('advanced.diagnostics')),
        throwsArgumentError,
      );
    },
  );

  test('changes stream emits written and reset definitions', () async {
    final values = SettingsValues(
      MemorySettingsStore(),
      logger: MemoryLogger(),
    );
    final seen = <String>[];
    final sub = values.changes.listen((d) => seen.add(d.id));
    await values.write(settingById('playback.autoPlayNext'), false);
    await values.reset(settingById('playback.autoPlayNext'));
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(seen, ['playback.autoPlayNext', 'playback.autoPlayNext']);
  });

  test('writes the generated settings table', () {
    final b = StringBuffer()
      ..writeln(
        '| id | section(s) | tier | kind | choices | default | requires | apply | target |',
      )
      ..writeln('| --- | --- | --- | --- | --- | --- | --- | --- | --- |');
    for (final d in settingDefs) {
      final sections = [d.section, ...d.alsoIn].map((s) => s.name).join(', ');
      final target = switch (d.target) {
        MpvProperty(:final name) => 'mpv: $name',
        TransportOption(:final name) => 'transport: $name',
        PlatformCall(:final name) => 'platform: $name',
        AppBehaviour(:final name) => 'app: $name',
      };
      b.writeln(
        '| ${_cell(d.id)} | $sections | ${d.tier.name} | ${d.kind.name} | '
        '${_cell(d.choices.join(' / '))} | ${_cell(d.defaultValue)} | ${d.requires.name} | '
        '${d.apply.name} | ${_cell(target)} |',
      );
    }
    final dir = Directory.systemTemp.createTempSync('settings-table-');
    try {
      final out = File('${dir.path}/settings_table.md');
      out.writeAsStringSync(b.toString());
      expect(out.existsSync(), isTrue);
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('language and size choices follow the player lists', () {
    expect(
      preferredAudioLanguageSetting.choices,
      playerLanguages.map((l) => l.code),
    );
    expect(defaultSubtitleSizeSetting.choices, subtitleSizes.keys);
  });

  test('app.language: system default, en/fa, outside the Kodi source list', () {
    expect(appLanguageSetting.id, 'app.language');
    expect(appLanguageSetting.choices, ['system', 'en', 'fa']);
    expect(appLanguageSetting.defaultValue, 'system');
    expect(settingDefs.any((d) => d.id == 'app.language'), isFalse);
  });

  test('keys of removed settings are dropped silently on load', () async {
    final store = MemorySettingsStore();
    for (final key in retiredSettingKeys) {
      await store.write(key, 'On');
    }
    await store.write('video.decoder', 'hardware');
    await AppSettings(store).load();
    for (final key in retiredSettingKeys) {
      expect(store.read(key), isNull, reason: key);
    }
    expect(store.read('video.decoder'), 'hardware');
    for (final id in retiredSettingKeys) {
      expect(settingDefs.map((d) => d.id), isNot(contains(id)));
    }
  });
}
