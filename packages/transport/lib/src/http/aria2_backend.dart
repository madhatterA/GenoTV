import 'package:contracts/contracts.dart';

/// Options shared by the process and iOS FFI aria2 backends.
const aria2StreamingOptions = <String, String>{
  'continue': 'true',
  'allow-overwrite': 'false',
  'auto-file-renaming': 'false',
  'file-allocation': 'none',
  'split': '4',
  'max-connection-per-server': '4',
  'min-split-size': '1M',
  'stream-piece-selector': 'inorder',
};

class BackendStatus {
  BackendStatus({
    this.totalBytes,
    RangeSet? available,
    this.bytesPerSecond = 0,
    this.peersOrConnections = 0,
    this.paused = false,
    this.error,
  }) : available = available ?? RangeSet.empty();
  final int? totalBytes;
  final RangeSet available;
  final double bytesPerSecond;
  final int peersOrConnections;

  /// The main download is paused (by the cache limit or a seek window).
  final bool paused;
  final Object? error;
}

abstract interface class Aria2Backend {
  Future<void> start();
  Future<String> addDownload(
    SourceSpec spec,
    String outPath, {
    int? totalBytes,
    ByteRange? initialWindow,
    TransportOptions options = const TransportOptions(),
  });

  /// Applies changed live settings (the download rate cap) to the running
  /// jobs and to windows opened later.
  Future<void> updateOptions(TransportOptions options);
  Future<BackendStatus> status(String jobId);

  /// Cached bytes plus the current bounded staging request, counted once.
  int reservedBytes(String jobId);
  Set<String> get activeWindowPaths;
  Stream<RangeSet> availabilityChanges(String jobId);
  ///
  /// With [updateAhead], [copyAll] also moves every downloaded byte of the
  /// window into the file at once (the whole item is being kept), not only
  /// what a reader asked for.
  Future<void> changeWindow(
    String jobId,
    ByteRange range, {
    bool updateAhead = false,
    bool copyAll = false,
  });

  /// Pauses or resumes the main download. No effect while a seek window owns
  /// the pause.
  Future<void> setPaused(String jobId, {required bool paused});

  /// Marks [range] as no longer on disk, so a later read re-fetches it.
  Future<void> forget(String jobId, ByteRange range);
  Future<void> remove(String jobId);
  Future<void> stop();
}
