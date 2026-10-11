/// Watch progress for one item.
///
/// [audioTrackId]/[subtitleTrackId] are **stable engine track identity
/// strings**, never indexes — the same rule Part 02 Chapter 03 Phase 01
/// pins on `Track.id`. Persistence is where an index would silently rot
/// between sessions: the engine's track order can differ the next time the
/// same file is opened (`research/ui/interaction-notes/README.md`:
/// "persist only stable track identity").
class PlaybackProgress {
  PlaybackProgress({
    required this.mediaId,
    required this.position,
    required this.duration,
    required this.updatedAt,
    required this.completed,
    this.audioTrackId,
    this.subtitleTrackId,
  }) : assert(updatedAt.isUtc, 'updatedAt must be stored as UTC — convert at the edge');

  final String mediaId;
  final Duration position;
  final Duration duration;

  /// Always UTC (constructor-enforced). A local `DateTime` round-tripped
  /// through storage is a classic off-by-one-hour bug across a timezone or
  /// DST change.
  final DateTime updatedAt;

  /// Watched past the completion threshold. A **stored** boolean, not
  /// computed from `position`/`duration` at read time: the completion
  /// threshold (typically ~90-95% of duration) is a policy Part 07 owns
  /// and may change — old rows must keep the meaning they were written
  /// with.
  final bool completed;
  final String? audioTrackId;
  final String? subtitleTrackId;

  PlaybackProgress copyWith({
    String? mediaId,
    Duration? position,
    Duration? duration,
    DateTime? updatedAt,
    bool? completed,
    String? audioTrackId,
    String? subtitleTrackId,
  }) {
    return PlaybackProgress(
      mediaId: mediaId ?? this.mediaId,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      updatedAt: updatedAt ?? this.updatedAt,
      completed: completed ?? this.completed,
      audioTrackId: audioTrackId ?? this.audioTrackId,
      subtitleTrackId: subtitleTrackId ?? this.subtitleTrackId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaybackProgress &&
          other.mediaId == mediaId &&
          other.position == position &&
          other.duration == duration &&
          other.updatedAt == updatedAt &&
          other.completed == completed &&
          other.audioTrackId == audioTrackId &&
          other.subtitleTrackId == subtitleTrackId);

  @override
  int get hashCode => Object.hash(
        mediaId,
        position,
        duration,
        updatedAt,
        completed,
        audioTrackId,
        subtitleTrackId,
      );
}
