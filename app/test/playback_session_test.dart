import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:video_player/platform_policy.dart';
import 'package:video_player/playback_insight.dart';
import 'package:video_player/playback_session.dart';
import 'package:platform_services/platform_services.dart'
    show DiagnosticsCollector;

const _media = MediaItem(
  id: 'session-media',
  title: 'Session media',
  kind: MediaKind.movie,
);

SourceSpec _spec({int? bytes = 8000000000}) => SourceSpec(
  kind: SourceKind.httpUrl,
  uri: Uri.parse('https://example.invalid/session.mp4'),
  expectedBytes: bytes,
);

void main() {
  test('seek bridge estimates, clamps, and forwards one hint', () async {
    final source = _RecordingSource();
    final controller = FakePlaybackController();
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(),
      controllerFactory: () => controller,
    );

    await session.start();
    controller.setDuration(const Duration(hours: 2));
    await controller.seek(const Duration(minutes: 30));
    await Future<void>.delayed(Duration.zero);
    await controller.seek(const Duration(hours: 3));
    await Future<void>.delayed(Duration.zero);

    expect(source.handles.single.recordedSeekHints, [2000000000, 8000000000]);
    await session.dispose();
  });

  test('null byte size and zero duration produce no hint', () async {
    final source = _RecordingSource();
    final controller = FakePlaybackController();
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(bytes: null),
      controllerFactory: () => controller,
    );

    await session.start();
    await controller.seek(const Duration(minutes: 1));
    await Future<void>.delayed(Duration.zero);
    expect(source.handles.single.recordedSeekHints, isEmpty);
    await session.dispose();
  });

  test('resume seek is observed before controller.open completes', () async {
    final source = _RecordingSource();
    final controller = _StartAtController();
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(),
      controllerFactory: () => controller,
    );

    await session.start(resumeAt: const Duration(minutes: 30));
    await Future<void>.delayed(Duration.zero);

    expect(source.handles.single.recordedSeekHints, [2000000000]);
    await session.dispose();
  });

  test('transport failure wins over playback failure', () async {
    final source = _RecordingSource();
    final controller = FakePlaybackController();
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(),
      controllerFactory: () => controller,
    );

    await session.start();
    final transport = const TransportFailure.torrentNoPeers();
    source.handles.single.failWith(transport);
    controller.failWith(
      const PlaybackFailure.decodeFailed(cause: 'decoder failure'),
    );
    await pumpEventQueue(times: 10);
    expect(session.snapshot.failure, same(transport));
    await session.dispose();
  });

  test('state bridge stays bounded for a playback burst', () async {
    final source = _RecordingSource();
    final controller = FakePlaybackController();
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(),
      controllerFactory: () => controller,
    );
    var updates = 0;
    final subscription = session.updates.listen((_) => updates++);

    await session.start();
    await pumpEventQueue(times: 5);
    final baseline = updates;
    for (var index = 0; index < 100; index++) {
      controller.advanceTo(Duration(milliseconds: index * 100));
    }
    await pumpEventQueue(times: 20);

    expect(updates - baseline, 100);
    await subscription.cancel();
    await session.dispose();
  });

  test('dispose orders controller before stream handle', () async {
    final order = <String>[];
    final source = _RecordingSource(order: order);
    final controller = _RecordingController(order);
    final session = PlaybackSession(
      media: _media,
      streamSource: source,
      source: _spec(),
      controllerFactory: () => controller,
    );

    await session.start();
    await session.dispose();

    expect(order, ['controller.dispose', 'handle.dispose']);
  });

  test(
    'dispose without progress persistence completes without a write wait',
    () async {
      final controller = _RecordingController(<String>[]);
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(),
        source: _spec(),
        controllerFactory: () => controller,
      );

      await session.start();
      await session.dispose();
      expect(session.controller, isNull);
    },
  );

  test(
    'async progress persistence completes before controller teardown',
    () async {
      final order = <String>[];
      final progress = _BlockingProgressRepository(order);
      final controller = _RecordingController(order);
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(order: order),
        source: _spec(),
        progress: progress,
        controllerFactory: () => controller,
      );

      await session.start();
      final disposal = session.dispose();
      await progress.started.future;
      expect(order, isNot(contains('controller.dispose')));
      progress.release.complete();
      await disposal;
      expect(order, contains('progress.upsert'));
      expect(
        order.indexOf('progress.upsert'),
        lessThan(order.indexOf('controller.dispose')),
      );
    },
  );

  test(
    'switchSource disposes the old pair and resumes at current position',
    () async {
      final order = <String>[];
      final source = _RecordingSource(order: order);
      final controllers = <_RecordingController>[];
      final session = PlaybackSession(
        media: _media,
        streamSource: source,
        source: _spec(),
        controllerFactory: () {
          final controller = _RecordingController(order);
          controllers.add(controller);
          return controller;
        },
      );

      await session.start();
      controllers.single.advanceTo(const Duration(minutes: 12));
      await session.switchSource(
        SourceSpec(
          kind: SourceKind.localFile,
          uri: Uri.parse('file:///session.mp4'),
          expectedBytes: 400,
        ),
      );

      expect(order.take(2), ['controller.dispose', 'handle.dispose']);
      expect(controllers[1].lastStartAt, const Duration(minutes: 12));
      await session.dispose();
    },
  );

  for (final entry in {
    'Auto': null,
    '2 GB': 2 * 1024 * 1024 * 1024,
    '5 GB': 5 * 1024 * 1024 * 1024,
    '10 GB': 10 * 1024 * 1024 * 1024,
    '20 GB': 20 * 1024 * 1024 * 1024,
  }.entries) {
    test('cache size limit ${entry.key} reaches the transport', () async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('streaming.cacheSizeLimit'),
        entry.key,
      );
      final source = _RecordingSource();
      final session = PlaybackSession(
        media: _media,
        streamSource: source,
        source: _spec(),
        controllerFactory: FakePlaybackController.new,
        settings: settings,
      );

      await session.start();

      expect(source.options.single.cacheLimitBytes, entry.value);
      await session.dispose();
    });
  }

  test(
    'opening applies preferred languages and default subtitle size',
    () async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.setPreferredAudioLanguage('fa');
      await settings.setPreferredSubtitleLanguage('fa');
      await settings.setDefaultSubtitleSize('Large');
      final controller = FakePlaybackController();
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(),
        source: _spec(),
        controllerFactory: () => controller,
        settings: settings,
      );

      await session.start();
      controller.setTracks(
        const TrackList(
          audio: [
            Track(id: 'a1', type: TrackType.audio, language: 'eng'),
            Track(id: 'a2', type: TrackType.audio, language: 'per'),
          ],
          subtitle: [
            Track(id: 's1', type: TrackType.subtitle, language: 'eng'),
            Track(id: 's2', type: TrackType.subtitle, language: 'fas'),
          ],
        ),
      );
      await session.defaultsDone;

      expect(controller.openedEngineOptions.single['sub-font-size'], '52.5');
      expect(controller.openedEngineOptions.single['sub-scale'], '1');
      final selected = controller.currentState.selected;
      expect(selected.audio, const TrackChoice.specific('a2'));
      expect(selected.subtitle, const TrackChoice.specific('s2'));
      await session.dispose();
    },
  );

  for (final ids in [
    ('a1', 's1', 'a1', 's1'),
    ('a1', null, 'a1', 's2'),
    (null, 's1', 'a2', 's1'),
    ('missing', 'missing', 'a2', 's2'),
    (null, null, 'a2', 's2'),
  ]) {
    test('resume restores saved choices before defaults: $ids', () async {
      final progress = FakeProgressRepository();
      await progress.upsert(
        PlaybackProgress(
          mediaId: _media.id,
          position: const Duration(seconds: 200),
          duration: const Duration(seconds: 1000),
          updatedAt: DateTime.utc(2026, 10, 2),
          completed: false,
          audioTrackId: ids.$1,
          subtitleTrackId: ids.$2,
        ),
      );
      final settings = AppSettings(MemorySettingsStore());
      await settings.setPreferredAudioLanguage('fa');
      await settings.setPreferredSubtitleLanguage('fa');
      final controller = _RecordingController([]);
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(),
        source: _spec(),
        controllerFactory: () => controller,
        settings: settings,
        progress: progress,
      );
      addTearDown(session.dispose);

      await session.start();
      controller.setTracks(
        const TrackList(
          audio: [
            Track(id: 'a1', type: TrackType.audio, language: 'eng'),
            Track(id: 'a2', type: TrackType.audio, language: 'per'),
          ],
          subtitle: [
            Track(id: 's1', type: TrackType.subtitle, language: 'eng'),
            Track(id: 's2', type: TrackType.subtitle, language: 'fas'),
          ],
        ),
      );
      await session.defaultsDone;

      expect(controller.lastStartAt, const Duration(seconds: 200));
      expect(
        controller.currentState.selected.audio,
        TrackChoice.specific(ids.$3),
      );
      expect(
        controller.currentState.selected.subtitle,
        TrackChoice.specific(ids.$4),
      );
    });
  }

  test(
    'audio plan is applied on open and on track change; display matched from '
    'the first frame rate and restored on dispose',
    () async {
      final controller = FakePlaybackController();
      final display = FakeDisplayModeService(
        modes: const [
          DisplayMode(
            width: 1920,
            height: 1080,
            refreshHz: 24,
            isCurrent: false,
          ),
        ],
      );
      final audio = FakeAudioOutputService();
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(),
        source: _spec(),
        controllerFactory: () => controller,
        policy: PlatformPolicy(
          capabilities: FakePlatformCapabilities(
            report: CapabilityReport(
              hardwareDecode: true,
              decoders: const ['h264'],
              hdrOutput: false,
              hdrFormats: const [],
              displayModeSwitching: true,
              audioPassthrough: false,
              passthroughFormats: const [],
              diagnostics: const {},
            ),
          ),
          displayModes: display,
          audio: audio,
          events: const Stream.empty(),
          mediaCommands: const Stream.empty(),
          acquireKeepAwake: () async => () async {},
          clearMediaSession: () async {},
          diagnostics: DiagnosticsCollector(os: 'test', appVersion: 'test'),
          displayModeMatchingEnabled: true,
        ),
      );
      await session.start();
      await Future<void>.delayed(Duration.zero);
      expect(display.lastLease, isNull);

      controller.emitMediaInfo(const MediaInfo(width: 1920));
      controller.emitMediaInfo(
        const MediaInfo(frameRate: 23.976, width: 1920, height: 1080),
      );
      await Future<void>.delayed(Duration.zero);
      expect(display.lastLease, isNotNull);
      expect(display.lastLease!.released, isFalse);

      controller.setTracks(
        const TrackList(
          audio: [
            Track(id: 'a1', type: TrackType.audio, codec: 'ac3'),
            Track(id: 'a2', type: TrackType.audio, codec: 'dts'),
          ],
        ),
      );
      await controller.selectTrack(
        const TrackSelection(
          video: TrackChoice.auto(),
          audio: TrackChoice.specific('a1'),
          subtitle: TrackChoice.off(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.selectTrack(
        const TrackSelection(
          video: TrackChoice.auto(),
          audio: TrackChoice.specific('a2'),
          subtitle: TrackChoice.off(),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(controller.recordedAudioOutput.map((p) => p.audioSpdif), [
        'ac3',
        'dts',
      ]);

      final lease = display.lastLease!;
      await session.dispose();
      expect(lease.released, isTrue);
    },
  );

  test('default preferences select available audio and keep absent forced subtitles Off', () async {
    final controller = FakePlaybackController();
    final session = PlaybackSession(
      media: _media,
      streamSource: _RecordingSource(),
      source: _spec(),
      controllerFactory: () => controller,
      settings: AppSettings(MemorySettingsStore()),
    );

    await session.start();
    controller.setTracks(
      const TrackList(
        audio: [Track(id: 'a1', type: TrackType.audio, language: 'eng')],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await session.defaultsDone;
    expect(
      controller.currentState.selected.audio,
      const TrackChoice.specific('a1'),
    );
    expect(controller.currentState.selected.subtitle, const TrackChoice.off());
    await session.dispose();
  });

  group('background preload', () {
    const next = MediaItem(id: 'next', title: 'Next', kind: MediaKind.episode);

    Future<
      (
        PlaybackSession,
        _RecordingSource,
        FakePlaybackController,
        int Function(),
      )
    >
    build({required bool preload}) async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('performance.backgroundPreload'),
        preload,
      );
      await settings.values.write(settingById('playback.autoPlayNext'), true);
      final source = _RecordingSource();
      final controller = FakePlaybackController();
      var resolved = 0;
      final session = PlaybackSession(
        media: _media,
        streamSource: source,
        source: _spec(),
        controllerFactory: () => controller,
        settings: settings,
        nextSource: (_, _) async {
          resolved++;
          return (
            media: next,
            source: SourceSpec(
              kind: SourceKind.httpUrl,
              uri: Uri.parse('https://example.invalid/next.mp4'),
            ),
          );
        },
      );
      await session.start();
      controller.setDuration(const Duration(minutes: 100));
      return (session, source, controller, () => resolved);
    }

    test('opens the next source at 90 % and reuses it', () async {
      final (session, source, controller, resolved) = await build(
        preload: true,
      );
      controller.advanceTo(const Duration(minutes: 80));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.handles, hasLength(1));
      controller.advanceTo(const Duration(minutes: 91));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.handles, hasLength(2));
      controller.emitEvent(const PlaybackEnded());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(session.media.id, 'next');
      expect(source.handles, hasLength(2));
      expect(resolved(), 1);
      await session.dispose();
    });

    test('Off keeps today\'s behaviour', () async {
      final (session, source, controller, _) = await build(preload: false);
      controller.advanceTo(const Duration(minutes: 95));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(source.handles, hasLength(1));
      await session.dispose();
    });
  });

  test(
    'custom mpv options: rejected lines are listed, playback opens',
    () async {
      final settings = AppSettings(MemorySettingsStore());
      await settings.values.write(
        settingById('advanced.customMpvOptions'),
        '# note\nsharpen=0.5\nno-such-option=1\nbroken line',
      );
      final controller = FakePlaybackController()
        ..rejectedUserOptions['no-such-option'] = 'property not found (-8)';
      final insight = PlaybackInsight();
      final session = PlaybackSession(
        media: _media,
        streamSource: _RecordingSource(),
        source: _spec(),
        controllerFactory: () => controller,
        settings: settings,
        insight: insight,
      );

      await session.start();

      expect(controller.recordedUserOptions.single, {
        'sharpen': '0.5',
        'no-such-option': '1',
      });
      expect(insight.customOptionsNote.value, contains('no-such-option'));
      expect(
        insight.customOptionsNote.value,
        contains('property not found (-8)'),
      );
      expect(insight.customOptionsNote.value, contains('broken line'));
      controller.emitDiagnostics({'video-codec': 'h264'});
      await Future<void>.delayed(Duration.zero);
      expect(insight.rows.value['Video codec'], 'h264');
      await session.dispose();
      expect(insight.rows.value, {'Playback': 'Not playing'});
    },
  );
}

class _RecordingSource implements StreamSource {
  _RecordingSource({this.order});

  final List<String>? order;
  final handles = <_RecordingHandle>[];
  final options = <TransportOptions>[];

  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) async {
    this.options.add(options);
    final handle = _RecordingHandle(spec.expectedBytes, order);
    handles.add(handle);
    return handle;
  }

  @override
  Future<int> clearCache() async => 0;
}

final class _BlockingProgressRepository implements ProgressRepository {
  _BlockingProgressRepository(this.order);

  final List<String> order;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<PlaybackProgress?> get(String mediaId) async => null;

  @override
  Future<void> upsert(PlaybackProgress progress) async {
    order.add('progress.upsert');
    started.complete();
    await release.future;
  }

  @override
  Future<List<PlaybackProgress>> continueWatching({int limit = 20}) async =>
      const <PlaybackProgress>[];

  @override
  Future<List<PlaybackProgress>> history({int limit = 20}) async =>
      const <PlaybackProgress>[];

  @override
  Future<void> clear(String mediaId) async {}

  @override
  Stream<PlaybackProgress> watch(String mediaId) =>
      const Stream<PlaybackProgress>.empty();
}

class _RecordingHandle extends FakeStreamHandle {
  _RecordingHandle(int? totalBytes, this.order)
    : super(totalBytes: totalBytes) {
    _status.add(_current);
  }

  final List<String>? order;
  final StreamController<SourceStatus> _status =
      StreamController<SourceStatus>.broadcast(sync: true);
  SourceStatus _current = SourceStatus(
    state: SourceState.resolving,
    available: RangeSet.empty(),
    totalBytes: null,
    bytesPerSecond: 0,
    peersOrConnections: 0,
  );

  @override
  Stream<SourceStatus> get status => _status.stream;

  @override
  void failWith(TransportFailure failure) {
    _current = SourceStatus(
      state: SourceState.failed,
      available: _current.available,
      totalBytes: totalBytes,
      bytesPerSecond: 0,
      peersOrConnections: 0,
      failure: failure,
    );
    _status.add(_current);
  }

  @override
  Future<void> dispose() async {
    order?.add('handle.dispose');
    await _status.close();
    await super.dispose();
  }
}

class _RecordingController extends FakePlaybackController {
  _RecordingController(this.order);

  final List<String> order;
  Duration? lastStartAt;

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    lastStartAt = startAt;
    await super.open(
      uri,
      headers: headers,
      startAt: startAt,
      engineOptions: engineOptions,
    );
  }

  @override
  Future<void> dispose() async {
    order.add('controller.dispose');
    await super.dispose();
  }
}

class _StartAtController extends _RecordingController {
  _StartAtController() : super(<String>[]);

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    setDuration(const Duration(hours: 2));
    if (startAt != null) emitEvent(SeekRequested(startAt));
    await super.open(
      uri,
      headers: headers,
      startAt: startAt,
      engineOptions: engineOptions,
    );
  }
}
