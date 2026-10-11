import 'package:core/core.dart';
import 'package:contracts/fakes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playback/playback.dart';

PlayerLanguage _lang(String code) =>
    playerLanguages.firstWhere((l) => l.code == code);

const _truehd = Track(
  id: 'a1',
  type: TrackType.audio,
  language: 'eng',
  codec: 'truehd',
);
const _commentary = Track(
  id: 'a2',
  type: TrackType.audio,
  language: 'eng',
  codec: 'ac3',
  title: 'Director Commentary',
);
const _ac3 = Track(
  id: 'a3',
  type: TrackType.audio,
  language: 'eng',
  codec: 'ac3',
);

int? _rank(Track t) => t.codec == 'truehd' ? null : (t.id == 'a3' ? 1 : 2);

void main() {
  FakePlaybackController withTracks(List<Track> audio) =>
      FakePlaybackController()..setTracks(TrackList(audio: audio));

  for (final saved in ['a1', 'a2', 'missing']) {
    test(
      'saved audio $saved respects explicit choice and playability',
      () async {
        final c = withTracks([_truehd, _commentary, _ac3]);
        addTearDown(c.dispose);
        await applyPreferredTracks(
          c,
          audio: _lang('en'),
          audioRank: _rank,
          savedAudioTrackId: saved,
        );
        expect(
          c.currentState.selected.audio,
          TrackChoice.specific(saved == 'a2' ? 'a2' : 'a3'),
        );
      },
    );
  }

  test('commentary tracks are skipped while a main track exists', () async {
    final c = withTracks([_commentary, _ac3]);
    await applyPreferredTracks(c, audio: _lang('en'));
    expect(c.currentState.selected.audio, const TrackChoice.specific('a3'));
    // Even with a rank that prefers the commentary.
    final d = withTracks([_commentary, _ac3]);
    await applyPreferredTracks(
      d,
      audio: _lang('en'),
      audioRank: (t) => t.id == 'a2' ? 0 : 5,
    );
    expect(d.currentState.selected.audio, const TrackChoice.specific('a3'));
  });

  test(
    'an unplayable pick is replaced even without a language match',
    () async {
      final c = withTracks([_truehd, _ac3]);
      await c.selectTrack(
        const TrackSelection(audio: TrackChoice.specific('a1')),
      );
      await applyPreferredTracks(c, audioRank: _rank);
      expect(c.currentState.selected.audio, const TrackChoice.specific('a3'));
    },
  );

  test(
    'a manual pick made after the defaults ran is never overridden',
    () async {
      final c = withTracks([_truehd, _ac3]);
      await applyPreferredTracks(c, audio: _lang('en'), audioRank: _rank);
      expect(c.currentState.selected.audio, const TrackChoice.specific('a3'));
      await c.selectTrack(
        const TrackSelection(audio: TrackChoice.specific('a1')),
      );
      c.setTracks(const TrackList(audio: [_truehd, _ac3]));
      await Future<void>.delayed(Duration.zero);
      expect(c.currentState.selected.audio, const TrackChoice.specific('a1'));
    },
  );
}
