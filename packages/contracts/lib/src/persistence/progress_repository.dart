import 'playback_progress.dart';

/// Provided by `packages/persistence` (Part 01). The UI never touches the
/// database — every access goes through this repository
/// (`planning/CONTRACTS.md` §7, decision D5).
abstract interface class ProgressRepository {
  /// Never throws for "not found" — returns null.
  Future<PlaybackProgress?> get(String mediaId);
  Future<void> upsert(PlaybackProgress progress);

  /// Recent, not completed.
  Future<List<PlaybackProgress>> continueWatching({int limit = 20});

  /// All watch history (finished or in progress), newest updatedAt first,
  /// bounded by [limit].
  Future<List<PlaybackProgress>> history({int limit = 20});
  Future<void> clear(String mediaId);
  Stream<PlaybackProgress> watch(String mediaId);
}
