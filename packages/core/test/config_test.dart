import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Fakes path_provider's platform channel with two temp directories, so
/// `AppPaths` can be exercised without a real device/simulator.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.supportRoot, this.cacheRoot);

  final Directory supportRoot;
  final Directory cacheRoot;

  @override
  Future<String?> getApplicationSupportPath() async => supportRoot.path;

  @override
  Future<String?> getApplicationCachePath() async => cacheRoot.path;
}

class _FailingPathProviderPlatform extends PathProviderPlatform {
  @override
  Future<String?> getApplicationCachePath() async =>
      throw StateError('cache unavailable');

  @override
  Future<String?> getApplicationSupportPath() async =>
      throw StateError('support unavailable');
}

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('core_config_test_');
    PathProviderPlatform.instance = _FakePathProviderPlatform(
      Directory('${tempRoot.path}/support'),
      Directory('${tempRoot.path}/cache'),
    );
  });

  tearDown(() {
    tempRoot.deleteSync(recursive: true);
  });

  group('AppPaths', () {
    test('returns distinct, creatable directories', () async {
      final paths = AppPaths(logger: MemoryLogger());

      final support = await paths.support;
      final cache = await paths.cache;
      final mediaCache = await paths.mediaCache;
      final torrentState = await paths.torrentState;
      final logs = await paths.logs;

      final resolved = <Directory>[
        support,
        cache,
        mediaCache,
        torrentState,
        logs,
      ];
      expect(resolved.map((d) => d.path).toSet(), hasLength(5));
      for (final dir in resolved) {
        expect(dir.existsSync(), isTrue);
      }
    });

    test('calling a getter twice does not fail', () async {
      final paths = AppPaths(logger: MemoryLogger());

      final first = await paths.cache;
      final second = await paths.cache;

      expect(first.path, second.path);
      expect(second.existsSync(), isTrue);
    });

    test('resolver failures surface as a typed storage path failure', () async {
      PathProviderPlatform.instance = _FailingPathProviderPlatform();
      final paths = AppPaths(logger: MemoryLogger());

      await expectLater(paths.cache, throwsA(isA<StoragePathFailure>()));
    });
  });

  group('JsonSettingsStore', () {
    test('round-trips a value across a load()', () async {
      final file = File('${tempRoot.path}/settings.json');
      final store = JsonSettingsStore(file: file, logger: MemoryLogger());

      await store.write('ui.theme', 'dark');
      await store.dispose();

      final reloaded = JsonSettingsStore(file: file, logger: MemoryLogger());
      await reloaded.load();

      expect(reloaded.read('ui.theme'), 'dark');
    });

    test('a debounced write is flushed by dispose()', () async {
      final file = File('${tempRoot.path}/settings.json');
      final store = JsonSettingsStore(
        file: file,
        logger: MemoryLogger(),
        debounce: const Duration(seconds: 30),
      );

      await store.write('ui.theme', 'dark');
      expect(file.existsSync(), isFalse);

      await store.dispose();

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('dark'));
    });
  });

  group('AppSettings defaults', () {
    test(
      'reading an absent key returns the supplied default, not null-crash',
      () {
        final settings = AppSettings(MemorySettingsStore());

        expect(settings.lastVolume, 1.0);
        expect(settings.verboseLogging, isFalse);
      },
    );

    test('set/get round-trips through the store', () async {
      final settings = AppSettings(MemorySettingsStore());

      await settings.setLastVolume(0.5);
      await settings.setVerboseLogging(true);

      expect(settings.lastVolume, 0.5);
      expect(settings.verboseLogging, isTrue);
    });

    test('last volume rejects values outside the engine range', () async {
      final settings = AppSettings(MemorySettingsStore());

      expect(
        () => settings.setLastVolume(-0.01),
        throwsA(isA<ArgumentError>()),
      );
      expect(() => settings.setLastVolume(1.01), throwsA(isA<ArgumentError>()));
    });
  });

  group('AppSettings language and subtitle defaults', () {
    test('defaults are original audio, forced-only subtitles, Normal size', () {
      final settings = AppSettings(MemorySettingsStore());

      expect(settings.preferredAudioLanguage, isNull);
      expect(settings.preferredSubtitleLanguage, 'forced_only');
      expect(settings.defaultSubtitleSize, 'Normal');
    });

    test('values persist across a new AppSettings instance', () async {
      final dir = await Directory.systemTemp.createTemp('lang-settings-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/settings.json');
      JsonSettingsStore open() =>
          JsonSettingsStore(file: file, logger: MemoryLogger());

      final first = open();
      await first.load();
      final written = AppSettings(first);
      await written.setPreferredAudioLanguage('fa');
      await written.setPreferredSubtitleLanguage('en');
      await written.setDefaultSubtitleSize('Large');
      await first.dispose();

      final second = open();
      await second.load();
      final reread = AppSettings(second);
      expect(reread.preferredAudioLanguage, 'fa');
      expect(reread.preferredSubtitleLanguage, 'en');
      expect(reread.defaultSubtitleSize, 'Large');

      await reread.setPreferredSubtitleLanguage(null);
      expect(reread.preferredSubtitleLanguage, isNull);
      await second.dispose();
    });

    test('unknown language or size is rejected; tags match by alias', () {
      final settings = AppSettings(MemorySettingsStore());

      expect(
        () => settings.setPreferredAudioLanguage('xx'),
        throwsArgumentError,
      );
      expect(
        () => settings.setDefaultSubtitleSize('Huge'),
        throwsArgumentError,
      );
      final persian = playerLanguages.firstWhere((l) => l.code == 'fa');
      expect(persian.matches('per'), isTrue);
      expect(persian.matches('FA-IR'), isTrue);
      expect(persian.matches('eng'), isFalse);
      expect(persian.matches(null), isFalse);
    });
  });
}
