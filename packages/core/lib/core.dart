/// Logging, failure taxonomy, configuration and storage paths.
///
/// Owned by Part 01. See `planning/part-01-*/PART.md`.
library;

export 'src/config/app_paths.dart';
export 'src/config/app_settings.dart';
export 'src/config/recent_links.dart';
export 'src/config/settings_schema.dart';
export 'src/config/settings_store.dart';
export 'src/config/settings_values.dart';
export 'src/failure/app_failure.dart';
export 'src/failure/failure_logging.dart';
export 'src/logging/app_logger.dart';
export 'src/logging/console_logger.dart';
export 'src/logging/file_log_sink.dart';
export 'src/logging/memory_logger.dart';
export 'src/torrent_title/parse_torrent_title.dart';
export 'src/torrent_title/relevance_scorer.dart';
export 'src/net/backup_route.dart';
