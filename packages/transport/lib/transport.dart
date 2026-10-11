/// aria2 HTTP streaming, libtorrent, and the local range server.
///
/// Owned by Part 03. See `planning/part-03-*/PART.md`.
library;

export 'package:contracts/contracts.dart';

import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'src/stream_source_impl.dart';

export 'src/stream_source_impl.dart';
export 'src/server/demand.dart';
export 'src/server/fake_sparse_source.dart';
export 'src/server/range_parser.dart';
export 'src/server/range_server.dart';
export 'src/server/sparse_source.dart';
export 'src/local/local_file_handle.dart';
export 'src/torrent/piece_mapper.dart';
export 'src/torrent/piece_scheduler.dart';
export 'src/torrent/torrent_metadata.dart';
export 'src/torrent/media_file_selector.dart';
export 'src/torrent/alert_router.dart';
export 'src/torrent/torrent_sparse_source.dart';
export 'src/torrent/torrent_session.dart';
export 'src/torrent/lt_ffi_session.dart';
export 'src/http/aria2_availability.dart';
export 'src/http/remote_http_source.dart';
export 'src/http/http_validator.dart';
export 'src/http/range_support_probe.dart';
export 'src/http/ffi/aria2_ffi_bindings.dart';
export 'src/http/ffi/aria2_ffi_session.dart';
export 'src/http/ffi/aria2_ffi_backend.dart';
export 'src/http/aria2_backend.dart';
export 'src/http/http_options.dart';
export 'src/torrent/torrent_options.dart';
export 'src/http/http_backend_factory.dart';
export 'src/http/http_sparse_source.dart';
export 'src/cache/fs_native.dart';

StreamSource createStreamSource({
  required AppLogger logger,
  required Directory cacheDir,
  TransportStateRepository? state,
}) => StreamSourceImpl(logger: logger, cacheDir: cacheDir, state: state);
