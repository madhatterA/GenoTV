import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:platform_services/platform_services.dart';

/// Real engine: generated 1 s clips, plan applied to mpv, readback of every
/// option, and the output channel count the engine actually used.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Set<String> engineDecoders;
  final log = StringBuffer();

  setUpAll(() async {
    final path = Platform.environment['PLAYBACK_LIBMPV'];
    if (path == null || !File(path).existsSync()) {
      throw StateError(
        'PLAYBACK_LIBMPV must name the repo-built app mpv library',
      );
    }
    mk.MediaKit.ensureInitialized(libmpv: path);
    dir = await Directory.systemTemp.createTemp('audio-plan-');
    final probe = mk.Player(
      configuration: const mk.PlayerConfiguration(vo: 'null'),
    );
    try {
      final raw = await (probe.platform as mk.NativePlayer).getProperty(
        'decoder-list',
      );
      engineDecoders = {
        for (final d in jsonDecode(raw) as List) (d as Map)['codec'] as String,
      };
    } finally {
      await probe.dispose();
    }
  });

  tearDownAll(() {
    final out = Platform.environment['AUDIO_PLAN_LOG'];
    if (out != null) File(out).writeAsStringSync(log.toString());
  });

  // ffmpeg encoder, mpv codec name, source channels, container
  const clips = [
    ('ac3', 'ac3', 6, 'mkv'),
    ('eac3', 'eac3', 6, 'mkv'),
    ('dca', 'dts', 6, 'mkv'),
    ('truehd', 'truehd', 6, 'mkv'),
    ('flac', 'flac', 6, 'mkv'),
  ];

  for (final (encoder, codec, channels, ext) in clips) {
    for (final link in [AudioLink.arc, AudioLink.optical, AudioLink.pcmOnly]) {
      test('$codec ${channels}ch on ${link.name}: mpv accepts the plan', () async {
        final clip = '${dir.path}/$codec.$ext';
        final gen = await Process.run('ffmpeg', [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:duration=1:sample_rate=48000',
          '-af',
          'pan=5.1|${List.generate(channels, (i) => 'c$i=c0').join('|')}',
          '-c:a',
          encoder,
          '-strict',
          '-2',
          '-y',
          clip,
        ]);
        expect(gen.exitCode, 0, reason: gen.stderr.toString());

        final model = AudioCapabilityModel(
          link: link,
          deviceFormats: {...AudioFormat.values},
        );
        final plan = planAudio(
          Track(id: '1', type: TrackType.audio, codec: codec),
          model,
          channels: channels,
          decoders: engineDecoders,
        );

        if (plan.step == AudioPlanStep.unplayable) {
          expect(engineDecoders, isNot(contains(codec)));
          expect(
            plan.reason,
            contains("can't be decoded on this player build"),
          );
          log.writeln(
            '$codec ${link.name}: step=unplayable reason="${plan.reason}" (engine decoder-list has no $codec)',
          );
          return;
        }
        final player = mk.Player(
          configuration: const mk.PlayerConfiguration(vo: 'null'),
        );
        final native = player.platform as mk.NativePlayer;
        try {
          await native.setProperty('ao', 'null');
          await native.setProperty('audio-spdif', plan.audioSpdif);
          await native.setProperty('audio-channels', plan.audioChannels);
          await native.setProperty('af', plan.af);
          await player.open(mk.Media(clip), play: true);
          await Future<void>.delayed(const Duration(milliseconds: 800));
          expect(await native.getProperty('audio-spdif'), plan.audioSpdif);
          expect(
            await native.getProperty('audio-channels'),
            plan.audioChannels,
          );
          if (plan.af.isNotEmpty) {
            expect(await native.getProperty('af'), contains(plan.af));
          }
          final out = await native.getProperty(
            'audio-out-params/channel-count',
          );
          final codecName = await native.getProperty('audio-codec-name');
          log.writeln(
            '$codec ${link.name}: step=${plan.step.name} spdif="${plan.audioSpdif}" '
            'audio-channels=${plan.audioChannels} af="${plan.af}" lost=${plan.lost} '
            '| mpv: decoder=$codecName out-channels=$out',
          );
          if (plan.step == AudioPlanStep.stereo) expect(out, '2');
        } finally {
          await player.dispose();
        }
      });
    }
  }
}
