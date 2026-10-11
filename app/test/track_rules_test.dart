import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:contracts/fakes.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/playback_session.dart';

import 'support/subtitle_clip.dart';

void main() {
  late Directory dir;
  late File clip;
  final rows = <String>[];
  setUpAll(() async {
    final fixture = await subtitleClip();
    dir = fixture.$1;
    clip = fixture.$2;
  });
  tearDownAll(() async {
    try {
      await File('${dir.path}/track_rules.md').writeAsString(
        '| Settings | Expected audio/sub | Got | Result |\n'
        '| --- | --- | --- | --- |\n${rows.join('\n')}\n',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('real multi-track settings table and disposition flags', () async {
    final cases = <(Map<String, Object>, String, String)>[
      (
        {
          'playback.preferredSubtitleLanguage': 'forced_only',
          'languages.preferForcedSubtitles': true,
        },
        '1',
        '3',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'fr',
          'playback.preferredSubtitleLanguage': 'fr',
        },
        '3',
        '4',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'playback.preferredSubtitleLanguage': 'en',
        },
        '1',
        '1',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferOriginalAudio': true,
        },
        '4',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferBestAudio': <String>['lossless'],
          'audio.passthrough': 'Disabled',
        },
        '1',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferBestAudio': <String>['highest-channel'],
          'audio.passthrough': 'Disabled',
        },
        '1',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferBestAudio': <String>['Atmos'],
          'audio.passthrough': 'Disabled',
        },
        '1',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferBestAudio': <String>['Atmos'],
          'audio.passthrough': 'Enabled',
          'audio.receiver.atmos': 'Disabled',
        },
        '1',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.preferBestAudio': <String>['Atmos'],
          'audio.passthrough': 'Enabled',
          'audio.receiver.atmos': 'Enabled',
          'audio.receiver.trueHd': 'Enabled',
        },
        '2',
        'no',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.hearingImpaired': 'Prefer',
        },
        '1',
        '2',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.hearingImpaired': 'Avoid',
        },
        '1',
        '1',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.hearingImpaired': 'No preference',
        },
        '1',
        '1',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.autoEnable': false,
        },
        '1',
        'no',
      ),
      (
        {
          'subtitles.autoEnable': false,
          'languages.preferForcedSubtitles': true,
        },
        '1',
        '3',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'languages.preferForcedSubtitles': true,
        },
        '1',
        '3',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.forcedBehaviour': 'Always',
        },
        '1',
        '3',
      ),
      (
        {
          'playback.preferredSubtitleLanguage': 'en',
          'subtitles.forcedBehaviour': 'Never',
          'languages.preferForcedSubtitles': true,
        },
        '1',
        '1',
      ),
      (
        {
          'languages.preferBestAudio': <String>['lossless'],
          'audio.passthrough': 'Disabled',
        },
        '3',
        'no',
      ),
      ({'languages.trackPriority': 'lang:fr,channels,default'}, '3', 'no'),
      ({'languages.trackPriority': 'original,lang:en'}, '4', 'no'),
      ({'languages.trackPriority': 'channels,lang:en'}, '3', 'no'),
      (
        {
          'playback.preferredAudioLanguage': 'en',
          'languages.trackPriority': 'default,lossless',
        },
        '1',
        'no',
      ),
      (
        {
          'playback.preferredAudioLanguage': 'de',
          'playback.preferredSubtitleLanguage': 'de',
        },
        '1',
        'no',
      ),
    ];
    for (final (overrides, audio, sub) in cases) {
      final settings = AppSettings(MemorySettingsStore());
      final effective = <String, Object>{
        'playback.preferredSubtitleLanguage': '',
        'languages.preferForcedSubtitles': false,
        ...overrides,
      };
      for (final entry in effective.entries) {
        await settings.values.write(settingById(entry.key), entry.value);
      }
      final (controller, backend) = subtitleEngine(resolve: clip.uri);
      await backend.setProperty('ao', 'null');
      final session = PlaybackSession(
        media: const MediaItem(
          id: 'rules',
          title: 'rules',
          kind: MediaKind.movie,
          originalLanguage: 'ja',
        ),
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
        final raw = (jsonDecode(
          await backend.getProperty('track-list'),
        ) as List).cast<Map>();
        final a = raw.where((t) => t['type'] == 'audio').toList();
        final s = raw.where((t) => t['type'] == 'sub').toList();
        expect(a, hasLength(4));
        expect(s, hasLength(5));
        final probe = await Process.run('ffprobe', [
          '-v',
          'error',
          '-show_streams',
          '-of',
          'json',
          clip.path,
        ]);
        await File('${dir.path}/fixture_probe.json')
            .writeAsString(probe.stdout.toString());
        await File('${dir.path}/track_metadata.json')
            .writeAsString(jsonEncode(raw));
        await File('${dir.path}/mpv_version.txt')
            .writeAsString(await backend.getProperty('mpv-version'));
        expect(a[1]['title'], 'Atmos');
        expect(a.map((t) => t['demux-channel-count']), [2, 8, 6, 2]);
        expect(s[1]['title'], 'English SDH');
        expect(s[2]['forced'], true);
        expect(a[0]['default'], true);
        expect(s[0]['default'], true);
        final decoders = await controller.decoderCodecs();
        if (effective['audio.passthrough'] == 'Disabled') {
          expect(decoders, isNot(contains('truehd')));
          expect(
            audio,
            isNot('2'),
            reason: 'undecodable TrueHD must be skipped',
          );
        }
        if (effective['audio.receiver.trueHd'] == 'Enabled') {
          expect(await backend.getProperty('audio-spdif'), contains('truehd'));
        }
        final gotAudio = await backend.getProperty('aid');
        final gotSub = await backend.getProperty('sid');
        final ok = gotAudio == audio && gotSub == sub;
        if (!ok) {
          await File('${dir.path}/track_failure.txt').writeAsString(
            'settings=$effective\nstateFailure=${controller.currentState.failure}\n'
            'sessionFailure=${session.snapshot.failure}\n'
            'decoders=${await backend.getProperty('decoder-list')}\n',
          );
        }
        rows.add(
          '| $effective | $audio/$sub | $gotAudio/$gotSub | ${ok ? 'PASS' : 'FAIL'} |',
        );
        expect('$gotAudio/$gotSub', '$audio/$sub', reason: '$overrides');
      } finally {
        await session.dispose();
        settings.values.dispose();
      }
    }
  });
  test('legacy hearing-impaired values migrate on load', () async {
    for (final entry in {'true': 'Prefer', 'false': 'No preference'}.entries) {
      final store = MemorySettingsStore();
      await store.write('subtitles.hearingImpaired', entry.key);
      final settings = AppSettings(store);
      await settings.load();
      expect(store.read('subtitles.hearingImpaired'), entry.value);
      expect(
        settings.values.read<String>(settingById('subtitles.hearingImpaired')),
        entry.value,
      );
      settings.values.dispose();
    }
  });
}
