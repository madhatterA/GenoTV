import 'playback_failure.dart';
import 'track.dart';

/// The player's state, as reported on [PlaybackController.state].
///
/// [bufferedAhead] is the engine's demuxer cache — how much of the stream
/// mpv has decoded and cached ahead of the current position. It is **not**
/// the downloader's byte availability; the transport contract's
/// `SourceStatus.available` is the other number. The two answer different
/// questions and the UI must show them differently
/// (`research/technical/MPV_PLAYBACK.md`) — this comment is load-bearing,
/// it is the thing that stops Part 04 rendering one and calling it the
/// other.
class PlaybackState {
  const PlaybackState({
    required this.position,
    required this.duration,
    required this.bufferedAhead,
    required this.isPlaying,
    required this.isBuffering,
    required this.isCompleted,
    required this.rate,
    required this.tracks,
    required this.selected,
    required this.chapters,
    this.failure,
    this.bufferingProgress,
  });

  factory PlaybackState.initial() => const PlaybackState(
        position: Duration.zero,
        duration: Duration.zero,
        bufferedAhead: Duration.zero,
        isPlaying: false,
        isBuffering: false,
        isCompleted: false,
        rate: 1.0,
        tracks: TrackList(),
        selected: TrackSelection(),
        chapters: <Chapter>[],
      );

  final Duration position;
  final Duration duration;

  /// The engine's demuxer cache. See the class doc comment.
  final Duration bufferedAhead;
  final bool isPlaying;
  final bool isBuffering;
  final bool isCompleted;
  final double rate;
  final TrackList tracks;
  final TrackSelection selected;
  final List<Chapter> chapters;
  final PlaybackFailure? failure;

  /// Readiness to resume playback, 0..1, from mpv's `cache-buffering-state`.
  /// Only meaningful while [isBuffering]; null until mpv reports.
  final double? bufferingProgress;

  PlaybackState copyWith({
    Duration? position,
    Duration? duration,
    Duration? bufferedAhead,
    bool? isPlaying,
    bool? isBuffering,
    bool? isCompleted,
    double? rate,
    TrackList? tracks,
    TrackSelection? selected,
    List<Chapter>? chapters,
    PlaybackFailure? failure,
    double? bufferingProgress,
  }) {
    return PlaybackState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedAhead: bufferedAhead ?? this.bufferedAhead,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isCompleted: isCompleted ?? this.isCompleted,
      rate: rate ?? this.rate,
      tracks: tracks ?? this.tracks,
      selected: selected ?? this.selected,
      chapters: chapters ?? this.chapters,
      failure: failure ?? this.failure,
      bufferingProgress: bufferingProgress ?? this.bufferingProgress,
    );
  }
}
