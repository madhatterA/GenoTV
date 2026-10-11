import 'dart:io';

import 'package:path_provider/path_provider.dart' as path_provider;

import '../failure/app_failure.dart';
import '../failure/failure_logging.dart';
import '../logging/app_logger.dart';

/// Raised when `path_provider` cannot resolve one of [AppPaths]' directories.
/// `packages/core` owns this leaf directly — resolving storage paths is
/// core's own concern, unlike a torrent or an HTTP range, which core must
/// never learn about.
final class StoragePathFailure extends AppFailure {
  const StoragePathFailure({
    required this.label,
    required super.cause,
    super.stack,
  }) : super(
          code: FailureCodes.corePathsUnavailable,
          message: 'Could not resolve the $label directory',
        );

  final String label;
}

/// Where this app puts files, on all four target platforms.
///
/// Every getter resolves through one of two `path_provider` functions, both
/// app-private on every platform this workspace targets and neither ever
/// throwing `UnsupportedError` here (unlike `getDownloadsDirectory()` /
/// `getExternalStorageDirectory()`, which this class deliberately avoids —
/// Android scoped storage would otherwise refuse a write in a way that looks
/// like a network bug, not a storage one):
///
/// - `getApplicationSupportDirectory()` — durable, survives OS cache
///   clears. Maps to `NSApplicationSupportDirectory` on iOS/macOS,
///   `PathUtils.getFilesDir` on Android.
/// - `getApplicationCacheDirectory()` — may be cleared by the OS at any
///   time. Maps to a platform cache directory (`NSCachesDirectory`-adjacent
///   on iOS/macOS, `Context.getCacheDir` on Android).
class AppPaths {
  AppPaths({required AppLogger logger}) : _logger = logger.scoped('core.paths');

  final AppLogger _logger;

  /// App-private support files: settings, and (durable, so placed here
  /// rather than under [cache]) torrent resume state and logs.
  Future<Directory> get support =>
      _resolveRoot(path_provider.getApplicationSupportDirectory, 'support');

  /// General-purpose cache. May be cleared by the OS at any time.
  Future<Directory> get cache => _subdirectory(_cacheRoot, 'cache');

  /// Downloaded/streamed media bytes. Deliberately under the app-private
  /// cache root, not external storage — see class doc comment.
  Future<Directory> get mediaCache => _subdirectory(_cacheRoot, 'media');

  /// Torrent resume data (piece bitfields, fastresume). Durable, not
  /// cache — losing it forces a costly re-hash of the swarm on next launch.
  Future<Directory> get torrentState => _subdirectory(support, 'torrent');

  /// Structured log output, for a future Phase that adds file logging.
  Future<Directory> get logs => _subdirectory(support, 'logs');

  Future<Directory> get _cacheRoot =>
      _resolveRoot(path_provider.getApplicationCacheDirectory, 'cache');

  Future<Directory> _resolveRoot(
    Future<Directory> Function() resolver,
    String label,
  ) async {
    try {
      final dir = await resolver();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (e, stack) {
      final failure = StoragePathFailure(label: label, cause: e, stack: stack);
      _logger.failure(failure);
      throw failure;
    }
  }

  Future<Directory> _subdirectory(Future<Directory> base, String name) async {
    try {
      final root = await base;
      final dir = Directory('${root.path}${Platform.pathSeparator}$name');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      return dir;
    } catch (e, stack) {
      if (e is StoragePathFailure) rethrow;
      final failure = StoragePathFailure(label: name, cause: e, stack: stack);
      _logger.failure(failure);
      throw failure;
    }
  }
}
