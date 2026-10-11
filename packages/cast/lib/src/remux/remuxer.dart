import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'remux_bindings.dart';
import 'remux_library.dart';

enum RemuxOutcome { completed, cancelled }

final class RemuxException implements Exception {
  const RemuxException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => 'Remux failed ($code): $message';
}

final class RemuxProgress {
  const RemuxProgress(this.position, this.duration, this.packets);
  final Duration position;

  /// Zero means the demuxer could not determine the duration.
  final Duration duration;
  final int packets;
}

/// In-process, stream-copy remuxing. Always await [RemuxTask.done], even after
/// cancelling: native resources are released before that future completes.
final class RemuxStream {
  const RemuxStream({
    required this.index,
    required this.type,
    required this.codec,
    this.attachedPicture = false,
  });
  final int index;
  final String type;
  final String codec;
  final bool attachedPicture;
}

final class Remuxer {
  Remuxer({String? libraryPath}) : _path = libraryPath ?? remuxLibraryPath() {
    _bindings = RemuxBindings(_path);
  }
  final String _path;
  late final RemuxBindings _bindings;
  int get liveJobs => _bindings.liveJobs();

  Future<List<RemuxStream>> probe(String input) {
    if (input.isEmpty || input.contains('\u0000')) {
      throw ArgumentError('Probe input must be nonempty without NUL');
    }
    final path = _path;
    return Isolate.run(() {
      final bindings = RemuxBindings(path);
      final job = bindings.create();
      if (job == nullptr) throw StateError('Probe allocation failed');
      try {
        final count = bindings.withString(
          input,
          (value) => bindings.probe(job, value),
        );
        if (count < 0) throw RemuxException(count, bindings.error(job));
        return List<RemuxStream>.unmodifiable([
          for (var index = 0; index < count; index++)
            RemuxStream(
              index: index,
              type: bindings.readString(bindings.streamType(job, index)),
              codec: bindings.readString(bindings.streamCodec(job, index)),
              attachedPicture: bindings.streamAttachedPicture(job, index) != 0,
            ),
        ]);
      } finally {
        bindings.destroy(job);
      }
    });
  }

  RemuxTask start({
    required String input,
    required String output,
    required String format,
    required List<int> keepStreams,
    List<String> subtitleInputs = const [],
    Duration? maxDuration,
  }) {
    for (final value in [input, output, format, ...subtitleInputs]) {
      if (value.isEmpty || value.contains('\u0000')) {
        throw ArgumentError(
          'Remux paths and format must be nonempty without NUL',
        );
      }
    }
    if (input == output ||
        keepStreams.isEmpty ||
        keepStreams.any((index) => index < 0 || index > 0x7fffffff) ||
        keepStreams.toSet().length != keepStreams.length ||
        (maxDuration != null && maxDuration.inMicroseconds <= 0)) {
      throw ArgumentError(
        'Distinct paths, unique nonnegative streams and a positive duration are required',
      );
    }
    final job = _bindings.create();
    if (job == nullptr) throw StateError('Remux job allocation failed');
    try {
      final code = _bindings.withString(
        input,
        (source) => _bindings.withString(
          output,
          (target) => _bindings.withString(
            format,
            (container) => _bindings.configure(
              job,
              source,
              target,
              container,
              maxDuration?.inMicroseconds ?? 0,
            ),
          ),
        ),
      );
      _check(job, code);
      for (final index in keepStreams) {
        _check(job, _bindings.keep(job, index));
      }
      for (final path in subtitleInputs) {
        _check(
          job,
          _bindings.withString(path, (value) => _bindings.subtitle(job, value)),
        );
      }
      return RemuxTask._(_path, _bindings, job);
    } catch (_) {
      _bindings.destroy(job);
      rethrow;
    }
  }

  void _check(Pointer<Void> job, int code) {
    if (code < 0) throw RemuxException(code, _bindings.error(job));
  }
}

final class RemuxTask {
  RemuxTask._(this._path, this._bindings, this._job) {
    done = _execute();
  }
  final String _path;
  final RemuxBindings _bindings;
  final Pointer<Void> _job;
  final _events = StreamController<RemuxProgress>.broadcast();
  bool _released = false;
  late final Future<RemuxOutcome> done;
  Stream<RemuxProgress> get progress => _events.stream;

  void cancel() {
    if (!_released) _bindings.cancel(_job);
  }

  void _publish() => _events.add(
    RemuxProgress(
      Duration(microseconds: _bindings.position(_job)),
      Duration(microseconds: _bindings.duration(_job)),
      _bindings.packets(_job),
    ),
  );

  Future<RemuxOutcome> _execute() async {
    Timer? timer;
    try {
      // Give the caller time to subscribe or cancel before opening any files.
      await Future<void>.delayed(Duration.zero);
      timer = Timer.periodic(
        const Duration(milliseconds: 10),
        (_) => _publish(),
      );
      final code = await _runInIsolate(_path, _job.address);
      _publish();
      if (code < 0) throw RemuxException(code, _bindings.error(_job));
      return code == 1 ? RemuxOutcome.cancelled : RemuxOutcome.completed;
    } finally {
      timer?.cancel();
      _released = true;
      _bindings.destroy(_job);
      unawaited(_events.close());
    }
  }
}

// This top-level closure captures only sendable values, never the native library
// or the task's stream controller. Both isolates address the same native heap.
Future<int> _runInIsolate(String path, int address) => Isolate.run(
  () => RemuxBindings(path).run(Pointer<Void>.fromAddress(address)),
);
