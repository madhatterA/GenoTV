import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:platform_services/platform_services.dart';
import 'package:video_player/platform_policy.dart';
import 'package:video_player/playback_session.dart';

class _Audio extends FakeAudioOutputService {
  _Audio()
    : super(
        devices: [
          AudioDevice(
            id: 'coreaudio/hdmi',
            name: 'HDMI',
            kind: AudioDeviceKind.hdmi,
            isCurrent: true,
          ),
          AudioDevice(
            id: 'coreaudio/speakers',
            name: 'Speakers',
            kind: AudioDeviceKind.speaker,
          ),
        ],
      );

  bool delay = false;
  final pending = <Completer<List<AudioDevice>>>[];

  @override
  Future<List<AudioDevice>> devices() {
    if (!delay) return super.devices();
    final reply = Completer<List<AudioDevice>>();
    pending.add(reply);
    return reply.future;
  }

  Future<void> reply(int index) async {
    pending[index].complete(await super.devices());
    await pumpEventQueue(times: 5);
  }
}

void main() {
  late AppSettings settings;
  late _Audio audio;
  late FakePlaybackController controller;
  late PlaybackSession session;

  setUp(() async {
    settings = AppSettings(MemorySettingsStore());
    await settings.values.write(
      settingById('audio.passthroughDevice'),
      'coreaudio/hdmi',
    );
    audio = _Audio();
    controller = FakePlaybackController();
    session = PlaybackSession(
      media: const MediaItem(
        id: 'audio',
        title: 'Audio',
        kind: MediaKind.movie,
      ),
      streamSource: FakeStreamSource(),
      source: SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('https://example.invalid/audio.wav'),
      ),
      controllerFactory: () => controller,
      settings: settings,
      logger: MemoryLogger(),
      policy: PlatformPolicy(
        capabilities: FakePlatformCapabilities(),
        displayModes: FakeDisplayModeService(),
        audio: audio,
        events: const Stream.empty(),
        mediaCommands: const Stream.empty(),
        acquireKeepAwake: () async => () async {},
        clearMediaSession: () async {},
        diagnostics: DiagnosticsCollector(os: 'test', appVersion: 'test'),
      ),
    );
    controller.setTracks(
      const TrackList(
        audio: [Track(id: 'a', type: TrackType.audio, codec: 'aac')],
      ),
    );
    await session.start();
    await session.defaultsDone;
    await controller.selectTrack(
      const TrackSelection(
        video: TrackChoice.auto(),
        audio: TrackChoice.specific('a'),
        subtitle: TrackChoice.off(),
      ),
    );
    await pumpEventQueue(times: 5);
  });

  tearDown(() async {
    await session.dispose();
    settings.values.dispose();
  });

  test(
    'older device reply cannot overwrite newer media channel plan',
    () async {
      audio.delay = true;
      controller.emitMediaInfo(const MediaInfo(audioChannels: 8));
      await pumpEventQueue(times: 5);
      final old = audio.pending.length;
      expect(old, greaterThan(0));
      controller.emitMediaInfo(const MediaInfo(audioChannels: 2));
      await pumpEventQueue(times: 5);
      expect(audio.pending.length, greaterThan(old));
      await audio.reply(audio.pending.length - 1);
      final applied = controller.recordedEngineOptions.length;
      expect(controller.recordedEngineOptions.last['audio-channels'], 'stereo');
      for (var i = 0; i < audio.pending.length - 1; i++) {
        await audio.reply(i);
      }
      expect(controller.recordedEngineOptions.length, applied);
    },
  );

  test('separate HDMI passthrough survives stereo PCM route and saved-device changes', () async {
    controller.emitMediaInfo(const MediaInfo(audioChannels: 2));
    await pumpEventQueue(times: 5);
    await settings.values.write(
      settingById('audio.outputDevice'),
      'coreaudio/speakers',
    );
    await pumpEventQueue(times: 5);
    expect(
      controller.recordedEngineOptions.last['audio-device'],
      'coreaudio/speakers',
    );
    expect(controller.recordedEngineOptions.last['audio-channels'], 'stereo');
    controller.setTracks(
      const TrackList(
        audio: [Track(id: 'ac3', type: TrackType.audio, codec: 'ac3')],
      ),
    );
    await controller.selectTrack(
      const TrackSelection(
        video: TrackChoice.auto(),
        audio: TrackChoice.specific('ac3'),
        subtitle: TrackChoice.off(),
      ),
    );
    await pumpEventQueue(times: 5);
    expect(
      controller.recordedEngineOptions.last['audio-device'],
      'coreaudio/hdmi',
    );
    expect(
      controller.recordedEngineOptions.last['audio-spdif'],
      contains('ac3'),
    );
    await settings.values.write(
      settingById('audio.passthroughDevice'),
      'coreaudio/speakers',
    );
    await settings.values.write(settingById('audio.normalizeVolume'), true);
    await pumpEventQueue(times: 5);
    expect(
      controller.recordedEngineOptions.last['audio-device'],
      'coreaudio/hdmi',
    );
    expect(
      controller.recordedEngineOptions.last['audio-spdif'],
      contains('ac3'),
    );
  });

  test('actual stereo metadata replaces assumed multichannel output', () async {
    expect(controller.recordedEngineOptions.last['audio-channels'], '5.1');
    controller.emitMediaInfo(const MediaInfo(audioChannels: 2));
    await pumpEventQueue(times: 5);
    expect(controller.recordedEngineOptions.last['audio-channels'], 'stereo');
  });

  test(
    'live normalization and device selection preserve resolved plan',
    () async {
      await settings.values.write(settingById('audio.normalizeVolume'), true);
      await pumpEventQueue(times: 5);
      final normalized = controller.recordedEngineOptions.last;
      expect(normalized['audio-normalize-downmix'], 'yes');
      expect(normalized['audio-channels'], '5.1');
      await settings.values.write(
        settingById('audio.outputDevice'),
        'coreaudio/hdmi',
      );
      await pumpEventQueue(times: 5);
      expect(
        controller.recordedEngineOptions.last['audio-device'],
        'coreaudio/hdmi',
      );
      expect(
        controller.recordedEngineOptions.last['audio-normalize-downmix'],
        'yes',
      );
      expect(controller.recordedEngineOptions.last['audio-channels'], '5.1');
    },
  );

  test(
    'later live change does not apply next-video or restart choices',
    () async {
      final before = Map<String, String>.of(
        controller.recordedEngineOptions.last,
      );
      for (final entry in <String, Object>{
        'audio.outputMode': 'Fixed',
        'audio.speakerLayout': '7.1',
        'audio.sampleRate': '96000',
        'audio.exclusiveMode': true,
        'audio.deviceKeepAlive': true,
      }.entries) {
        await settings.values.write(settingById(entry.key), entry.value);
      }
      await settings.values.write(settingById('audio.normalizeVolume'), true);
      await pumpEventQueue(times: 5);
      final after = controller.recordedEngineOptions.last;
      for (final key in [
        'audio-channels',
        'audio-samplerate',
        'audio-exclusive',
        'audio-stream-silence',
        'gapless-audio',
        'keep-open',
      ]) {
        expect(after[key], before[key], reason: key);
      }
      expect(after['audio-normalize-downmix'], 'yes');
    },
  );
}
