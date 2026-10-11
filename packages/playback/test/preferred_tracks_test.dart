import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:playback/playback.dart';
import 'package:playback/src/controller/media_kit_playback_controller.dart';
import 'package:playback/src/surface/surface_output.dart';

PlayerLanguage _lang(String code) =>
    playerLanguages.firstWhere((l) => l.code == code);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
  });

  test(
    'preferred languages select the matching tracks of a real clip',
    () async {
      final directory = await Directory.systemTemp.createTemp('preferred-');
      addTearDown(() => directory.delete(recursive: true));
      File('${directory.path}/eng.srt')
          .writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nHello\n');
      File('${directory.path}/per.srt')
          .writeAsStringSync('1\n00:00:00,000 --> 00:00:01,000\nسلام\n');
      final clip = File('${directory.path}/clip.mkv');
      final generated = await Process.run('ffmpeg', [
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
        '-i',
        '${directory.path}/eng.srt',
        '-i',
        '${directory.path}/per.srt',
        '-map',
        '0:v',
        '-map',
        '1:a',
        '-map',
        '2:a',
        '-map',
        '3:0',
        '-map',
        '4:0',
        '-c:v',
        'mpeg4',
        '-c:a',
        'aac',
        '-c:s',
        'srt',
        '-metadata:s:a:0',
        'language=eng',
        '-metadata:s:a:1',
        'language=per',
        '-metadata:s:s:0',
        'language=eng',
        '-metadata:s:s:1',
        'language=per',
        '-y',
        clip.path,
      ]);
      expect(generated.exitCode, 0, reason: generated.stderr.toString());

      final player = mk.Player(
        configuration: const mk.PlayerConfiguration(vo: 'null'),
      );
      final controller = MediaKitPlaybackController(
        logger: MemoryLogger(),
        player: player,
        output: SurfaceOutput(
          attach: () async => throw UnsupportedError('headless track test'),
          texture: () async {},
          logger: MemoryLogger(),
          onError: (error, stack) => fail('Unexpected surface error: $error'),
        ),
      );
      try {
        await controller.open(clip.uri);
        await applyPreferredTracks(
          controller,
          audio: _lang('fa'),
          subtitle: _lang('fa'),
        );
        final tracks = controller.currentState.tracks;
        final selected = controller.currentState.selected;
        String? languageOf(List<Track> list, TrackChoice c) =>
            list.firstWhere((t) => t.id == c.id).language;
        expect(
          tracks.audio.map((t) => t.language),
          containsAll(['eng', 'per']),
        );
        expect(selected.audio.mode, TrackSelectionMode.specific);
        expect(languageOf(tracks.audio, selected.audio), 'per');
        expect(selected.subtitle.mode, TrackSelectionMode.specific);
        expect(languageOf(tracks.subtitle, selected.subtitle), 'per');

        final savedAudio = tracks.audio.firstWhere((t) => t.language == 'eng');
        final savedSubtitle = tracks.subtitle.firstWhere(
          (t) => t.language == 'eng',
        );
        await applyPreferredTracks(
          controller,
          audio: _lang('fa'),
          subtitle: _lang('fa'),
          savedAudioTrackId: savedAudio.id,
          savedSubtitleTrackId: savedSubtitle.id,
        );
        expect(
          controller.currentState.selected.audio,
          TrackChoice.specific(savedAudio.id),
        );
        expect(
          controller.currentState.selected.subtitle,
          TrackChoice.specific(savedSubtitle.id),
        );

        // Missing saved IDs fall back independently to the preferred languages.
        await applyPreferredTracks(
          controller,
          audio: _lang('fa'),
          subtitle: _lang('fa'),
          savedAudioTrackId: 'missing',
          savedSubtitleTrackId: 'missing',
        );
        expect(controller.currentState.selected, selected);

        // Saved choices are restored even when no language default is set.
        await applyPreferredTracks(
          controller,
          savedAudioTrackId: savedAudio.id,
          savedSubtitleTrackId: savedSubtitle.id,
        );
        final restored = controller.currentState.selected;
        expect(restored.audio, TrackChoice.specific(savedAudio.id));
        expect(restored.subtitle, TrackChoice.specific(savedSubtitle.id));

        // No Arabic track: the current choice is left alone.
        await applyPreferredTracks(controller, audio: _lang('ar'));
        expect(controller.currentState.selected, restored);
      } finally {
        await controller.dispose();
      }
    },
  );
}
