import 'dart:io';

import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:platform_services/platform_services.dart';
import 'package:playback/playback.dart';
// The headless engine wiring below is the same the playback package's own
// real-engine tests use.
// ignore: implementation_imports
import 'package:playback/src/controller/media_kit_playback_controller.dart';
// ignore: implementation_imports
import 'package:playback/src/surface/surface_output.dart';
import 'package:video_player/platform_policy.dart';
import 'package:video_player/playback_session.dart';

class _NoChannel implements PlatformChannel {
  @override
  Stream<dynamic> get events => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Speakers extends FakeAudioOutputService {
  _Speakers()
    : super(
        devices: [
          AudioDevice(
            id: 'builtin',
            name: 'Speakers',
            kind: AudioDeviceKind.speaker,
            isCurrent: true,
          ),
        ],
      );

  @override
  AudioPlan plan(
    Track track,
    AudioCapabilityModel model, {
    int? channels,
    Set<String>? decoders,
  }) =>
      AudioOutputServiceImpl(channel: _NoChannel())
          .plan(track, model, channels: channels, decoders: decoders);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late File clip;

  setUpAll(() async {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
    dir = await Directory.systemTemp.createTemp('track-pref-');
    clip = File('${dir.path}/clip.mkv');
    final r = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=size=64x64:rate=24:duration=2',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=2',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=880:duration=2',
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-map',
      '2:a',
      '-filter:a',
      'aformat=channel_layouts=5.1',
      '-c:v',
      'mpeg4',
      '-c:a:0',
      'truehd',
      '-strict',
      'experimental',
      '-c:a:1',
      'ac3',
      '-metadata:s:a:0',
      'language=eng',
      '-metadata:s:a:1',
      'language=eng',
      '-y',
      clip.path,
    ]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
  });
  tearDownAll(() => dir.delete(recursive: true));

  final audio = AudioOutputServiceImpl(channel: _NoChannel());
  final english = playerLanguages.firstWhere((l) => l.code == 'en');
  final links = {
    'built-in speakers': AudioCapabilityModel(
      link: AudioLink.pcmOnly,
      deviceFormats: {},
    ),
    'ARC': AudioCapabilityModel(
      link: AudioLink.arc,
      deviceFormats: {AudioFormat.ac3, AudioFormat.eac3, AudioFormat.dts},
    ),
    'eARC': AudioCapabilityModel(
      link: AudioLink.hdmiEarc,
      deviceFormats: AudioFormat.values.toSet(),
    ),
  };

  Future<String?> chosenCodec(
    AudioCapabilityModel model, {
    String? savedCodec,
  }) async {
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    // vo=null disables video, and then mpv ends the file when the default
    // (TrueHD) track cannot be decoded; a real window keeps the video running.
    await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: MemoryLogger(),
        onError: (e, s) => fail('surface error: $e'),
      ),
    );
    try {
      await controller.open(clip.uri);
      final tracks = (await controller.state.firstWhere(
        (s) => s.tracks.audio.isNotEmpty,
      )).tracks.audio;
      expect(tracks.map((t) => t.codec), containsAll(['truehd', 'ac3']));
      final decoders = await engineDecoderCodecs(controller);
      await applyPreferredTracks(
        controller,
        audio: english,
        audioRank: audioRankFor(audio, model, decoders),
        savedAudioTrackId: tracks
            .where((t) => t.codec == savedCodec)
            .firstOrNull
            ?.id,
      );
      final id = controller.currentState.selected.audio.id;
      return tracks.firstWhere((t) => t.id == id).codec;
    } finally {
      await controller.dispose();
    }
  }

  test('built-in speakers: the AC3 track is chosen over TrueHD', () async {
    expect(await chosenCodec(links['built-in speakers']!), 'ac3');
  });

  test('ARC: the AC3 track is chosen over TrueHD', () async {
    expect(await chosenCodec(links['ARC']!), 'ac3');
  });

  test('eARC: the TrueHD track is chosen', () async {
    expect(await chosenCodec(links['eARC']!), 'truehd');
  });

  test('saved playable AC3 overrides the eARC TrueHD default', () async {
    expect(await chosenCodec(links['eARC']!, savedCodec: 'ac3'), 'ac3');
  });

  test('saved undecodable TrueHD falls back to AC3 on speakers', () async {
    expect(
      await chosenCodec(links['built-in speakers']!, savedCodec: 'truehd'),
      'ac3',
    );
  });

  test('session with a TrueHD-first file: AC3 is selected and no failure reaches the viewer', () async {
    final settings = AppSettings(MemorySettingsStore());
    await settings.setPreferredAudioLanguage('en');
    final logger = MemoryLogger();
    late MediaKitPlaybackController controller;
    final speakers = _Speakers();
    late mk.Player enginePlayer;
    final session = PlaybackSession(
      media: const MediaItem(id: 'm', title: 'm', kind: MediaKind.movie),
      streamSource: FakeStreamSource(),
      source: SourceSpec(
        kind: SourceKind.httpUrl,
        uri: Uri.parse('http://127.0.0.1:0/x.mkv'),
      ),
      controllerFactory: () {
        final player = mk.Player(
          configuration: const mk.PlayerConfiguration(vo: 'null'),
        );
        enginePlayer = player;
        (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
        return controller = MediaKitPlaybackController(
          logger: logger,
          player: player,
          resolveUri: (_) => clip.uri,
          output: SurfaceOutput(
            attach: () async => throw UnsupportedError('headless'),
            texture: () async {},
            logger: logger,
            onError: (e, s) => fail('surface error: $e'),
          ),
        );
      },
      policy: PlatformPolicy(
        capabilities: FakePlatformCapabilities(),
        displayModes: FakeDisplayModeService(),
        audio: speakers,
        events: const Stream.empty(),
        mediaCommands: const Stream.empty(),
        acquireKeepAwake: () async => () async {},
        clearMediaSession: () async {},
        diagnostics: DiagnosticsCollector(os: 'test', appVersion: 'test'),
      ),
      settings: settings,
      logger: logger,
    );
    final failures = <PlaybackEvent>[];
    await session.start();
    final sub = controller.events.listen((e) {
      if (e is PlaybackFailed) failures.add(e);
    });
    final state = await controller.state
        .firstWhere(
          (s) =>
              s.tracks.audio.isNotEmpty &&
              s.selected.audio.mode == TrackSelectionMode.specific &&
              s.tracks.audio
                      .firstWhere((t) => t.id == s.selected.audio.id)
                      .codec ==
                  'ac3',
        )
        .timeout(const Duration(seconds: 10));
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(state.selected.audio.mode, TrackSelectionMode.specific);
    expect(failures, isEmpty);
    expect(session.snapshot.failure, isNull);
    // The Info line follows the selected track: AC3 on a stereo-only output.
    expect(session.audioOutput.value, 'AC3 → Stereo');
    // The plan reaches the real engine (mpv read-back), not only the Info line.
    final backend = (enginePlayer.platform as mk.NativePlayer);
    expect(await backend.getProperty('audio-spdif'), '');
    expect(await backend.getProperty('audio-channels'), 'stereo');
    await sub.cancel();
    await session.dispose();
    expect(session.audioOutput.value, isNull);
  });

  test('a TrueHD-only file still reports the decode failure', () async {
    final only = File('${dir.path}/only.mkv');
    final r = await Process.run('ffmpeg', [
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=size=64x64:rate=24:duration=2',
      '-f',
      'lavfi',
      '-i',
      'sine=frequency=440:duration=2',
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-filter:a',
      'aformat=channel_layouts=5.1',
      '-c:v',
      'mpeg4',
      '-c:a',
      'truehd',
      '-strict',
      'experimental',
      '-y',
      only.path,
    ]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: MemoryLogger(),
        onError: (e, s) => fail('surface error: $e'),
      ),
    );
    try {
      await controller.open(only.uri);
      final failed = await controller.state
          .firstWhere((s) => s.failure != null)
          .timeout(const Duration(seconds: 10));
      expect(failed.failure.toString(), contains('truehd'));
    } finally {
      await controller.dispose();
    }
  });

  test('undecodable default that nobody replaces fails when the defaults pass ends', () async {
    final player = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    await (player.platform as mk.NativePlayer).setProperty('vid', 'auto');
    final controller = MediaKitPlaybackController(
      logger: MemoryLogger(),
      player: player,
      output: SurfaceOutput(
        attach: () async => throw UnsupportedError('headless'),
        texture: () async {},
        logger: MemoryLogger(),
        onError: (e, s) => fail('surface error: $e'),
      ),
    );
    try {
      await controller.open(clip.uri);
      await controller.state
          .firstWhere((s) => s.tracks.audio.isNotEmpty)
          .timeout(const Duration(seconds: 10));
      // No preference, no rank: the engine's TrueHD pick stays.
      await applyPreferredTracks(controller);
      final failed = await controller.state
          .firstWhere((s) => s.failure != null)
          .timeout(const Duration(seconds: 10));
      expect(failed.failure.toString(), contains('truehd'));
    } finally {
      await controller.dispose();
    }
  });
}
