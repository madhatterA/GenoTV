import 'package:contracts/contracts.dart';
import 'package:media_kit/media_kit.dart' as mk;

TrackList mapTracks(mk.Tracks tracks) => TrackList(
  video: tracks.video.where(_isReal).map(_video).toList(growable: false),
  audio: tracks.audio.where(_isReal).map(_audio).toList(growable: false),
  subtitle: tracks.subtitle
      .where(_isReal)
      .map(_subtitle)
      .toList(growable: false),
);

bool _isReal(dynamic track) => track.id != 'auto' && track.id != 'no';

Track _video(mk.VideoTrack track) => Track(
  id: track.id,
  type: TrackType.video,
  title: track.title,
  language: track.language,
  codec: track.codec,
  isDefault: track.isDefault ?? false,
);

Track _audio(mk.AudioTrack track) => Track(
  id: track.id,
  type: TrackType.audio,
  title: track.title,
  language: track.language,
  codec: track.codec,
  isDefault: track.isDefault ?? false,
);

Track _subtitle(mk.SubtitleTrack track) => Track(
  id: track.id,
  type: TrackType.subtitle,
  title: track.title,
  language: track.language,
  codec: track.codec,
  isDefault: track.isDefault ?? false,
);

TrackChoice _choice(String id) => switch (id) {
  'auto' => const TrackChoice.auto(),
  'no' => const TrackChoice.off(),
  _ => TrackChoice.specific(id),
};

TrackSelection mapSelection(mk.Track track) => TrackSelection(
  video: _choice(track.video.id),
  audio: _choice(track.audio.id),
  subtitle: _choice(track.subtitle.id),
);
