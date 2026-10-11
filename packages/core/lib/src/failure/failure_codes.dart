/// Code namespace registry. Each prefix below is owned by the named Part,
/// which extends [AppFailure] inside its own package to add leaves under it.
/// `packages/core` must never learn what a torrent is — these are namespace
/// roots for documentation and reference, not an exhaustive leaf list.
abstract final class FailureCodes {
  FailureCodes._();

  /// Owned by Part 02 (`packages/playback`).
  static const String playbackPrefix = 'playback';

  /// Owned by Part 03 (`packages/transport`).
  static const String transportHttpPrefix = 'transport.http';
  static const String transportTorrentPrefix = 'transport.torrent';
  static const String transportRangePrefix = 'transport.range';

  /// Owned by Part 05 (`packages/platform_services`).
  static const String platformPrefix = 'platform';

  /// Owned by Part 07 (`app/`).
  static const String appPrefix = 'app';

  /// Declared in `packages/core` itself — general enough that more than one
  /// Part needs it. Nothing else belongs here.
  static const String appUnexpected = 'app.unexpected';
  static const String appCancelled = 'app.cancelled';

  /// `AppPaths` failing to resolve a directory — core's own concern, so it
  /// gets its own prefix rather than borrowing Part 05's `platform.*`.
  static const String corePathsUnavailable = 'core.paths.unavailable';
}
