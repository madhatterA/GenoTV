import 'playback_failure.dart';
import 'track.dart';

/// Discrete playback events, delivered on [PlaybackController.events] and
/// never coalesced (unlike [PlaybackController.state]). `sealed` so Part 04
/// can `switch` over every subtype exhaustively, without a default arm.
sealed class PlaybackEvent {
  const PlaybackEvent();
}

/// Emitted **before** the engine is asked to seek, so the source layer can
/// reprioritise ahead of it. The seek itself is not authoritative — the
/// Range request the engine issues afterward is
/// (`planning/CONTRACTS.md` §9 "seek, end to end").
final class SeekRequested extends PlaybackEvent {
  const SeekRequested(this.to);
  final Duration to;
}

final class SeekCompleted extends PlaybackEvent {
  const SeekCompleted(this.at);
  final Duration at;
}

final class MediaOpened extends PlaybackEvent {
  const MediaOpened({required this.duration, required this.tracks});
  final Duration duration;
  final TrackList tracks;
}

final class PlaybackEnded extends PlaybackEvent {
  const PlaybackEnded();
}

final class PlaybackFailed extends PlaybackEvent {
  const PlaybackFailed(this.failure);
  final PlaybackFailure failure;
}
