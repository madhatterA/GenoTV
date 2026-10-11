import 'dart:ffi';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import '../aria2_backend.dart';
import '../../cache/range_ops.dart';
import '../aria2_window.dart';
import '../http_options.dart';
import 'aria2_ffi_session.dart';

const _statePaused = 2;
const _stateComplete = 3;
const _stateRemoved = 5;

/// [Aria2Backend] backed by the in-process libaria2 shim (statically linked on
/// iOS, `libtransport_aria2_shim.dylib` on macOS). No aria2c program exists.
final class Aria2FfiBackend implements Aria2Backend {
  Aria2FfiBackend({this.library, AppLogger? logger})
    : _logger = logger?.scoped('transport.http.aria2_ffi');
  final DynamicLibrary? library;
  final AppLogger? _logger;
  final Map<String, _Job> _jobs = <String, _Job>{};
  Aria2FfiSession? _session;
  bool started = false;
  int _nextJob = 0;
  @override
  Future<void> start() async {
    if (started) return;
    try {
      final session = Aria2FfiSession(library ?? openAria2Library());
      final startupError = session.error;
      if (startupError.isNotEmpty) {
        session.dispose();
        throw Aria2FfiException('create session', startupError);
      }
      _session = session;
      started = true;
    } catch (error, stack) {
      _logger?.error(
        'libaria2 session unavailable',
        error: error,
        stack: stack,
      );
      throw TransportFailure.engineUnavailable(cause: error, stack: stack);
    }
  }

  @override
  Future<String> addDownload(
    SourceSpec spec,
    String outPath, {
    int? totalBytes,
    ByteRange? initialWindow,
    TransportOptions options = const TransportOptions(),
  }) async {
    await start();
    final output = File(outPath);
    if (totalBytes != null) {
      if (totalBytes <= 0) {
        throw ArgumentError('bounded download requires its size');
      }
      final job = _Job(spec, output, options)
        ..totalBytes = totalBytes
        ..desired = initialWindow;
      final control = File('$outPath.aria2');
      var reusable = false;
      if (await control.exists() && await output.exists()) {
        try {
          final record =
              jsonDecode(await control.readAsString()) as Map<String, dynamic>;
          if (record['total'] == totalBytes) {
            var ranges = RangeSet.empty();
            final length = await output.length();
            for (final pair in record['ranges'] as List) {
              final range = ByteRange(pair[0] as int, pair[1] as int);
              if (range.start < 0 ||
                  range.endInclusive >= totalBytes ||
                  range.endInclusive >= length) {
                throw const FormatException('invalid cached HTTP range');
              }
              ranges = ranges.add(range);
            }
            job.copied = ranges;
            reusable = true;
          }
        } on FormatException {
          // Native aria2 control files and corrupt coverage cannot be reused.
        } on TypeError {
          // A coverage record with the wrong schema cannot claim file bytes.
        }
      }
      if (!reusable) {
        if (await output.exists()) await output.delete();
        if (await control.exists()) await control.delete();
      }
      await File('$outPath.evicted').writeAsString('1', flush: true);
      await _saveCoverage(job);
      final jobId = 'bounded-${_nextJob++}';
      _jobs[jobId] = job;
      await job.run(() => _queueBounded(job));
      return jobId;
    }
    if (!options.verifyTls) {
      // aria2 reads check-certificate once, when its session is created.
      throw TransportFailure.engineUnavailable(
        cause:
            'certificate checking cannot be switched off for a download of '
            'unknown size',
      );
    }
    final session = _requireSession();
    final gid = await _retryBusy(
      () => session.addUri(
        spec.uri,
        directory: output.parent.path,
        output: output.uri.pathSegments.last,
        headers: originHeaders(spec, options),
        options: {...aria2StreamingOptions, ...aria2OriginOptions(options)},
      ),
    );
    final jobId = '$gid';
    _jobs[jobId] = _Job(spec, output, options);
    return jobId;
  }

  @override
  Future<void> updateOptions(TransportOptions options) async {
    final limit = aria2TransferOptions(options)['max-download-limit'] ?? '0';
    for (final entry in _jobs.entries) {
      final job = entry.value..options = options;
      await job.run(() async {
        final gid =
            job.window?.gid ??
            (job.totalBytes == null ? int.tryParse(entry.key) : null);
        if (gid == null) return;
        await _retryBusy(
          () =>
              _requireSession().changeOption(gid, 'max-download-limit', limit),
        );
      });
    }
  }

  /// Current value of an aria2 option of the job's running download (the seek
  /// window while one is active), read from the libaria2 session.
  Future<String> jobOption(String jobId, String name) {
    final job = _jobs[jobId];
    if (job == null) throw StateError('unknown download $jobId');
    final gid = job.window?.gid ?? int.parse(jobId);
    return _retryBusy(() => _requireSession().option(gid, name));
  }

  @override
  Future<BackendStatus> status(String jobId) {
    final job = _jobs[jobId];
    if (job == null) return Future.error(StateError('unknown download $jobId'));
    return job.run(() => _status(job, jobId));
  }

  Future<BackendStatus> _status(_Job job, String jobId) async {
    if (job.totalBytes != null) return _statusBounded(job);
    final gid = int.tryParse(jobId);
    if (gid == null) {
      return BackendStatus(
        error: TransportFailure.engineUnavailable(cause: 'invalid aria2 gid'),
      );
    }
    try {
      final main = await _retryBusy(() => _requireSession().status(gid));
      final window = job.window;
      Aria2FfiStatus? targeted;
      if (window != null) {
        final windowStatus = await _retryBusy(
          () => _requireSession().status(window.gid!),
        );
        targeted = windowStatus;
        if (window.failure != null || windowStatus.failure != null) {
          throw TransportFailure.httpUnreachable(
            cause: window.failure ?? windowStatus.failure,
          );
        }
        await window.copyAvailable(windowStatus.available, job.file);
        for (final range in window.copied.ranges) {
          final copied = ByteRange(
            range.start + window.range.start,
            range.endInclusive + window.range.start,
          );
          job.copied = job.copied.add(copied);
          job.evicted = subtractRange(job.evicted, copied);
        }
        if (windowStatus.state == _stateComplete) {
          await window.close();
          job.window = null;
          if (main.state != _stateComplete) {
            await _retryBusy(
              () => _requireSession().setPaused(gid, paused: false),
            );
          }
        }
      }
      var available = main.available;
      for (final range in job.copied.ranges) {
        available = available.add(range);
      }
      for (final range in job.evicted.ranges) {
        available = subtractRange(available, range);
      }
      return BackendStatus(
        totalBytes: main.totalLength,
        available: available,
        paused: main.state == _statePaused && job.window == null,
        bytesPerSecond: (targeted ?? main).downloadRate.toDouble(),
        peersOrConnections: (targeted ?? main).connections,
        error: main.failure == null
            ? null
            : TransportFailure.httpUnreachable(cause: main.failure!),
      );
    } on Aria2FfiException catch (error, stack) {
      _logger?.warn('libaria2 status failed', error: error, stack: stack);
      return BackendStatus(
        error: TransportFailure.httpUnreachable(cause: error, stack: stack),
      );
    }
  }

  /// Whole-file mode makes the running window the entire file, so a read far
  /// past what that window has fetched so far (an mkv/mp4 index at the end
  /// of the file) still lies "inside" it and would wait for every byte
  /// before it; the player times out first. Such a read re-targets the
  /// download to where it is needed.
  static bool _farAhead(_Job job, ByteRange? active, ByteRange range) {
    if (active == null) return false;
    var front = active.start;
    for (final done in job.copied.ranges) {
      if (done.start <= front && done.endInclusive >= front) {
        front = done.endInclusive + 1;
      }
    }
    return range.start > front + _farAheadSlack;
  }

  static const int _farAheadSlack = 32 * 1024 * 1024;

  @override
  Future<void> changeWindow(
    String jobId,
    ByteRange range, {
    bool updateAhead = false,
    bool copyAll = false,
  }) {
    final job = _jobs[jobId];
    if (job != null && updateAhead) job.copyAll = copyAll;
    if (job != null && job.totalBytes != null && !updateAhead) {
      job.demand = range;
    }
    if (job != null && job.totalBytes != null) {
      return job.run(() async {
        if (!updateAhead && job.desired == null) return;
        if (range.start < 0 || range.endInclusive >= job.totalBytes!) {
          throw RangeError('window exceeds download size');
        }
        if (updateAhead) {
          job.desired = range;
          final active = job.window?.range;
          if (active != null &&
              (range.endInclusive < active.start ||
                  range.start > active.endInclusive ||
                  active.endInclusive > range.endInclusive)) {
            await _cancelWindow(job);
          }
        } else if (!job.copied.containsRange(range)) {
          final active = job.window?.range;
          final desired = job.desired;
          if (active == null ||
              range.start < active.start ||
              range.start > active.endInclusive ||
              _farAhead(job, active, range)) {
            if (desired == null ||
                _farAhead(job, active, range) ||
                range.start < desired.start ||
                range.start > desired.endInclusive) {
              final length = desired?.length ?? range.length;
              job.desired = ByteRange(
                range.start,
                (range.start + length - 1).clamp(
                  range.endInclusive,
                  job.totalBytes! - 1,
                ),
              );
            }
            await _cancelWindow(job);
          }
        }
        await _queueBounded(job);
        if (!updateAhead) await _statusBounded(job);
      });
    }
    final gid = int.tryParse(jobId);
    if (job == null || gid == null) {
      return Future.error(StateError('unknown download $jobId'));
    }
    return job.run(() async {
      var main = await _retryBusy(() => _requireSession().status(gid));
      if (main.failure != null) {
        throw TransportFailure.httpUnreachable(cause: main.failure);
      }
      if (range.start == 0) {
        await _cancelWindow(job);
        if (main.state == _statePaused) await _resume(gid);
        return;
      }
      main = await _waitFor(gid, (s) => s.totalLength > 0, poll: true);
      if (range.start < 0 || range.endInclusive >= main.totalLength) {
        throw RangeError('window exceeds download size');
      }
      var available = main.available;
      for (final copied in job.copied.ranges) {
        available = available.add(copied);
      }
      for (final gone in job.evicted.ranges) {
        available = subtractRange(available, gone);
      }
      if (available.containsRange(range)) return;
      if (job.window?.range == range) return;
      await _cancelWindow(job);
      if (main.state != _statePaused && main.state != _stateComplete) {
        try {
          await _retryBusy(
            () => _requireSession().setPaused(gid, paused: true),
          );
        } on Aria2FfiException {
          // The job may have finished or paused itself meanwhile; the wait
          // below accepts those states and rethrows anything else.
        }
      }
      main = await _waitFor(
        gid,
        (s) => s.state == _statePaused || s.state == _stateComplete,
      );
      // A finished download only has the range unless it was evicted.
      if (main.state == _stateComplete && job.evicted.ranges.isEmpty) return;
      Aria2Window? window;
      try {
        window = await Aria2Window.open(
          job.spec,
          range,
          main.totalLength,
          job.file.parent,
          job.options,
        );
        job.window = window;
        window.gid = await _retryBusy(
          () => _requireSession().addUri(
            window!.uri,
            directory: window.file.parent.path,
            output: window.file.uri.pathSegments.last,
            options: _windowOptions(job),
          ),
        );
      } catch (_) {
        job.window = null;
        await window?.close();
        if (main.state != _stateComplete) await _resume(gid);
        rethrow;
      }
    });
  }

  @override
  Future<void> setPaused(String jobId, {required bool paused}) {
    final job = _jobs[jobId];
    if (job != null && job.totalBytes != null) {
      return job.run(() async {
        if (paused) {
          job.desired = null;
          await _cancelWindow(job);
        } else {
          await _queueBounded(job);
        }
      });
    }
    final gid = int.tryParse(jobId);
    if (job == null || gid == null) {
      return Future.error(StateError('unknown download $jobId'));
    }
    return job.run(() async {
      if (job.window != null) return;
      final main = await _retryBusy(() => _requireSession().status(gid));
      if (main.state == _stateComplete || main.state == _stateRemoved) return;
      if (paused == (main.state == _statePaused)) return;
      await _retryBusy(() => _requireSession().setPaused(gid, paused: paused));
    });
  }

  @override
  Future<void> forget(String jobId, ByteRange range) {
    final job = _jobs[jobId];
    if (job == null) return Future.error(StateError('unknown download $jobId'));
    return job.run(() async {
      job.copied = subtractRange(job.copied, range);
      // ponytail: an alive seek window is never inside an evicted range
      // (it sits at the play head, eviction happens a back window away).
      job.evicted = job.evicted.add(range);
      if (job.totalBytes != null) await _saveCoverage(job);
    });
  }

  @override
  Set<String> get activeWindowPaths => {
    for (final job in _jobs.values)
      if (job.window != null) job.window!.directory.path,
  };
  @override
  Stream<RangeSet> availabilityChanges(String jobId) =>
      _jobs[jobId]!.changes.stream;
  @override
  int reservedBytes(String jobId) {
    final job = _jobs[jobId];
    if (job == null) return 0;
    var occupied = job.copied;
    final window = job.window;
    if (window != null) occupied = occupied.add(window.range);
    return rangesLength(occupied);
  }

  Future<void> _saveCoverage(_Job job) async {
    final control = File('${job.file.path}.aria2');
    await control.writeAsString(
      jsonEncode({
        'total': job.totalBytes,
        'ranges': [
          for (final r in job.copied.ranges) [r.start, r.endInclusive],
        ],
      }),
      flush: true,
    );
  }

  Future<BackendStatus> _statusBounded(_Job job, {bool queue = true}) async {
    final window = job.window;
    Aria2FfiStatus? current;
    if (window != null) {
      final snapshot = await _retryBusy(
        () => _requireSession().status(window.gid!),
      );
      current = snapshot;
      if (window.failure != null || snapshot.failure != null) {
        throw TransportFailure.httpUnreachable(
          cause: window.failure ?? snapshot.failure,
        );
      }
      var wanted = RangeSet.empty();
      final demand = job.demand;
      if (job.copyAll) {
        wanted = snapshot.available;
      } else if (demand != null) {
        wanted = snapshot.available;
        final first = demand.start - window.range.start;
        final last = demand.endInclusive - window.range.start;
        if (first > 0) wanted = subtractRange(wanted, ByteRange(0, first - 1));
        if (last < window.range.length - 1) {
          wanted = subtractRange(
            wanted,
            ByteRange(last + 1, window.range.length - 1),
          );
        }
      }
      await window.copyAvailable(
        wanted,
        job.file,
        releaseCopied: true,
        onCopied: (range) {
          final copied = ByteRange(
            range.start + window.range.start,
            range.endInclusive + window.range.start,
          );
          job.copied = job.copied.add(copied);
          job.evicted = subtractRange(job.evicted, copied);
          job.changes.add(job.copied);
        },
      );
      if (snapshot.state == _stateComplete &&
          window.copied.containsRange(ByteRange(0, window.range.length - 1))) {
        await _cancelWindow(job);
      }
    }
    if (queue) await _queueBounded(job);
    return BackendStatus(
      totalBytes: job.totalBytes,
      available: job.copied,
      paused: job.window == null,
      bytesPerSecond: current?.downloadRate.toDouble() ?? 0,
      peersOrConnections: current?.connections ?? 0,
    );
  }

  Future<void> _queueBounded(_Job job) async {
    if (job.window != null) return;
    final desired = job.desired;
    if (desired == null) return;
    final gap = job.copied.firstGapFrom(desired.start);
    if (gap.start > desired.endInclusive) return;
    final gapEnd = gap.endInclusive;
    final end = gapEnd != null && gapEnd < desired.endInclusive
        ? gapEnd
        : desired.endInclusive;
    final window = await Aria2Window.open(
      job.spec,
      ByteRange(gap.start, end),
      job.totalBytes!,
      job.file.parent,
      job.options,
    );
    job.window = window;
    try {
      window.gid = await _retryBusy(
        () => _requireSession().addUri(
          window.uri,
          directory: window.file.parent.path,
          output: window.file.uri.pathSegments.last,
          options: _windowOptions(job),
        ),
      );
    } catch (_) {
      job.window = null;
      await window.close();
      rethrow;
    }
  }

  /// A window is a loopback download: only limits, connection count,
  /// timeouts and tries apply to it; the origin is reached by the window.
  Map<String, String> _windowOptions(_Job job) => {
    ...aria2StreamingOptions,
    ...aria2TransferOptions(job.options),
  };

  Future<void> _resume(int gid) =>
      _retryBusy(() => _requireSession().setPaused(gid, paused: false));
  Future<Aria2FfiStatus> _waitFor(
    int gid,
    bool Function(Aria2FfiStatus) ready, {
    bool poll = false,
  }) async {
    // ponytail: libaria2 has no per-gid notification in this shim; poll at
    // 50 ms for 5 s. Replace with a native event if the shim grows one.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (true) {
      final status = await _retryBusy(() => _requireSession().status(gid));
      if (ready(status)) return status;
      if (status.failure != null || status.state == _stateRemoved) {
        throw TransportFailure.httpUnreachable(
          cause: status.failure ?? 'download removed',
        );
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TransportFailure.httpUnreachable(
          cause: 'aria2 status wait for $gid timed out',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _cancelWindow(_Job job) async {
    final window = job.window;
    if (window == null) return;
    final gid = window.gid;
    if (gid != null) {
      try {
        await _retryBusy(() => _requireSession().remove(gid));
      } on Aria2FfiException catch (error, stack) {
        _logger?.warn(
          'libaria2 window remove failed',
          error: error,
          stack: stack,
        );
      }
    }
    await window.close();
    job.window = null;
  }

  @override
  Future<void> remove(String jobId) async {
    final job = _jobs[jobId];
    if (job != null && job.totalBytes != null) {
      await job.run(() async {
        await _statusBounded(job, queue: false);
        await _cancelWindow(job);
        await _saveCoverage(job);
        final marker = File('${job.file.path}.evicted');
        if (await marker.exists()) await marker.delete();
        _jobs.remove(jobId);
        await job.close();
      });
      return;
    }
    final gid = int.tryParse(jobId);
    if (job == null || gid == null) return;
    await job.run(() async {
      await _cancelWindow(job);
      try {
        await _retryBusy(() => _requireSession().remove(gid));
      } on Aria2FfiException catch (error, stack) {
        _logger?.warn('libaria2 remove failed', error: error, stack: stack);
      } finally {
        _jobs.remove(jobId);
        await job.close();
      }
    });
  }

  @override
  Future<void> stop() async {
    final session = _session;
    _session = null;
    started = false;
    session?.dispose();
    for (final job in _jobs.values.toList()) {
      await job.run(() async {
        await job.window?.close();
        await job.close();
      });
    }
    _jobs.clear();
  }

  Aria2FfiSession _requireSession() {
    final session = _session;
    if (session == null || session.isDisposed) {
      throw const TransportFailure.engineUnavailable(
        cause: 'libaria2 session is not running',
      );
    }
    return session;
  }

  Future<T> _retryBusy<T>(T Function() operation) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      try {
        return operation();
      } on Aria2FfiException catch (error) {
        if (error.code != -3 || DateTime.now().isAfter(deadline)) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }
  }
}

class _Job {
  _Job(this.spec, this.file, this.options);
  final SourceSpec spec;
  TransportOptions options;
  final File file;
  int? totalBytes;
  ByteRange? desired;
  ByteRange? demand;

  /// Every downloaded byte moves into the file, not only demanded ones.
  bool copyAll = false;
  final changes = StreamController<RangeSet>.broadcast();
  RangeSet copied = RangeSet.empty();
  // Ranges punched out of the file: aria2 still believes it has them.
  RangeSet evicted = RangeSet.empty();
  Aria2Window? window;
  Future<void> _tail = Future.value();
  Future<void> close() async {
    await changes.close();
  }

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    // Each caller receives its failure; queue recovery lets cleanup still run.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

/// Opens the in-process aria2 shim. A platform whose libaria2 is not built
/// yet fails here, naming the missing library; there is no fallback.
DynamicLibrary openAria2Library() {
  if (Platform.isIOS) return DynamicLibrary.process();
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libtransport_aria2_shim.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('transport_aria2_shim.dll');
  }
  if (Platform.isMacOS) {
    const name = 'libtransport_aria2_shim.dylib';
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      for (final path in <String>[
        '${File(Platform.resolvedExecutable).parent.path}/../Frameworks/$name',
        '${Directory.current.path}/macos/libs/$name',
        '${Directory.current.path}/packages/transport/macos/libs/$name',
      ]) {
        if (File(path).existsSync()) return DynamicLibrary.open(path);
      }
      rethrow;
    }
  }
  throw UnsupportedError(
    'libaria2 is not built for ${Platform.operatingSystem} yet '
    '(missing libtransport_aria2 shim)',
  );
}
