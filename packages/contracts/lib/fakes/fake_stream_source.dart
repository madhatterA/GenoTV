import 'dart:async';

import 'package:contracts/contracts.dart';

import 'src/replay_latest_broadcast.dart';

/// Controllable, deterministic [StreamHandle] fake. No `Future.delayed`
/// anywhere — a test drives every state change explicitly.
class FakeStreamHandle implements StreamHandle {
  FakeStreamHandle({this.totalBytes}) {
    // A freshly opened handle starts resolving, organically — a real
    // implementation reports readiness promptly too, so the "replays the
    // latest value to a late subscriber" contract test has something to
    // observe without a fake-only driver call.
    emitStatus(SourceStatus(
      state: SourceState.resolving,
      available: RangeSet.empty(),
      totalBytes: totalBytes,
      bytesPerSecond: 0,
      peersOrConnections: 0,
    ));
  }

  final Uri _uri = Uri.parse('http://127.0.0.1:0/fake-stream');
  @override
  int? totalBytes;

  bool _disposed = false;
  final ReplayLatestBroadcast<SourceStatus> _statusReplay = ReplayLatestBroadcast<SourceStatus>();

  /// Every offset passed to [seekHint], in order. Clamped values, not raw
  /// ones — see [seekHint]'s doc comment for which behaviour this fake
  /// pins.
  final List<int> recordedSeekHints = [];

  @override
  Uri get playbackUri {
    if (_disposed) throw StateError('playbackUri used after dispose()');
    return _uri;
  }

  @override
  Stream<SourceStatus> get status => _statusReplay.stream;

  /// Forces a status onto [status]. No-op after [dispose] — a disposed
  /// handle emits nothing more.
  void emitStatus(SourceStatus status) {
    if (_disposed) return;
    _statusReplay.add(status);
  }

  /// Convenience: marks [range] as available, keeping the rest of the
  /// current status unchanged.
  void completeRange(ByteRange range) {
    final current = _lastOrDefault();
    emitStatus(SourceStatus(
      state: SourceState.buffering,
      available: current.available.add(range),
      totalBytes: totalBytes ?? current.totalBytes,
      bytesPerSecond: current.bytesPerSecond,
      peersOrConnections: current.peersOrConnections,
    ));
  }

  void failWith(TransportFailure failure) {
    final current = _lastOrDefault();
    emitStatus(SourceStatus(
      state: SourceState.failed,
      available: current.available,
      totalBytes: totalBytes ?? current.totalBytes,
      bytesPerSecond: 0,
      peersOrConnections: current.peersOrConnections,
      failure: failure,
    ));
  }

  SourceStatus _lastOrDefault() => _statusReplay.hasValue
      ? _statusReplay.latest
      : SourceStatus(
          state: SourceState.resolving,
          available: RangeSet.empty(),
          totalBytes: totalBytes,
          bytesPerSecond: 0,
          peersOrConnections: 0,
        );

  @override
  Future<void> seekHint(int byteOffset) async {
    if (_disposed) throw StateError('seekHint used after dispose()');
    // Pinned behaviour: clamps to totalBytes rather than ignoring or
    // throwing — never throws for an offset beyond totalBytes
    // (`planning/CONTRACTS.md` §2 StreamHandle doc comment).
    final bytes = totalBytes;
    final clamped = (bytes != null && byteOffset > bytes) ? bytes : (byteOffset < 0 ? 0 : byteOffset);
    recordedSeekHints.add(clamped);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _statusReplay.clear();
    await _statusReplay.close();
  }
}

/// Controllable [StreamSource] fake. Opening the same [SourceSpec] twice
/// (by equality) returns the same [FakeStreamHandle] instead of a
/// competing one — the dedup half of invariant §2.1 ("identical demand is
/// deduplicated").
class FakeStreamSource implements StreamSource {
  final Map<SourceSpec, FakeStreamHandle> _handles = {};

  /// When true, [open] never completes — for testing a loading UI.
  bool neverCompletesOpen = false;

  /// Options passed to the most recent [open].
  TransportOptions? lastOptions;

  /// How many times [clearCache] was called.
  int clearCacheCalls = 0;

  @override
  Future<StreamHandle> open(
    SourceSpec spec, {
    TransportOptions options = const TransportOptions(),
  }) {
    lastOptions = options;
    if (neverCompletesOpen) return Completer<StreamHandle>().future;
    final existing = _handles[spec];
    if (existing != null) return Future.value(existing);
    final handle = FakeStreamHandle(totalBytes: spec.expectedBytes);
    _handles[spec] = handle;
    return Future.value(handle);
  }

  @override
  Future<int> clearCache() async {
    clearCacheCalls++;
    return 0;
  }
}
