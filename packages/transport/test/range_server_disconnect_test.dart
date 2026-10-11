import 'dart:async';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/http/http_sparse_source.dart';
import 'package:transport/src/server/fake_sparse_source.dart';
import 'package:transport/src/server/sparse_source.dart';
import 'package:transport/src/server/range_server.dart';

const _mib = 1024 * 1024;

Future<List<int>> _get(Uri uri, String range) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    return await response.expand((c) => c).toList();
  } finally {
    client.close(force: true);
  }
}

/// Emits slowly so the response is still mid-body when the client leaves.
class _SlowSource extends FakeSparseSource {
  _SlowSource(super.bytes);
  @override
  Stream<List<int>> read(ByteRange range) async* {
    await for (final chunk in super.read(range)) {
      yield chunk;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

void main() {
  test(
    'client dropping the socket mid-body is logged, not an unhandled error',
    () async {
      final errors = <Object>[];
      final logger = MemoryLogger();
      await runZonedGuarded(() async {
        final server = await RangeServer.start(logger: logger);
        final big = _SlowSource(List<int>.filled(32 * _mib, 7));
        final small = FakeSparseSource(List<int>.generate(64, (i) => i));
        final bigUri = server.register(big);
        final smallUri = server.register(small);
        final socket = await Socket.connect(bigUri.host, bigUri.port);
        socket.write(
          'GET ${bigUri.path} HTTP/1.1\r\nHost: x\r\nRange: bytes=0-\r\n\r\n',
        );
        final got = Completer<void>();
        socket.listen((_) {
          if (!got.isCompleted) got.complete();
        }, onError: (_) {});
        await got.future;
        socket.destroy();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(
          await _get(smallUri, 'bytes=0-9'),
          List<int>.generate(10, (i) => i),
        );
        await server.close();
      }, (e, s) => errors.add(e));
      expect(errors, isEmpty);
      expect(
        logger.records.any(
          (r) => r.level == LogLevel.info && r.message.contains('disconnected'),
        ),
        isTrue,
      );
      expect(logger.records.where((r) => r.level == LogLevel.error), isEmpty);
    },
  );

  test('disposing the source while a response waits ends it cleanly', () async {
    final errors = <Object>[];
    final logger = MemoryLogger();
    await runZonedGuarded(() async {
      final server = await RangeServer.start(logger: logger);
      final source = FakeSparseSource(
        List<int>.filled(8 * _mib, 1),
        available: const [ByteRange(0, 4 * _mib - 1)],
      );
      final uri = server.register(source);
      final other = server.register(
        FakeSparseSource(List<int>.generate(64, (i) => i)),
      );
      final pending = _get(
        uri,
        'bytes=0-',
      ).then<Object?>((_) => null, onError: (Object e) => e);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await source.dispose();
      await pending;
      expect(await _get(other, 'bytes=0-9'), List<int>.generate(10, (i) => i));
      await server.close();
    }, (e, s) => errors.add(e));
    expect(errors, isEmpty);
    expect(
      logger.records.any(
        (r) => r.level == LogLevel.info && r.message.contains('disposed'),
      ),
      isTrue,
    );
    expect(logger.records.where((r) => r.level == LogLevel.error), isEmpty);
  });

  test(
    'HttpSparseSource.waitFor ends with SparseSourceDisposed on dispose',
    () async {
      final dir = await Directory.systemTemp.createTemp('http-sparse-dispose-');
      try {
        final source = HttpSparseSource(
          file: File('${dir.path}/x.partial'),
          totalBytes: 100,
        );
        final waiting = source.waitFor(const ByteRange(0, 9));
        final result = expectLater(
          waiting,
          throwsA(isA<SparseSourceDisposed>()),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await source.dispose();
        await result;
        await expectLater(
          source.waitFor(const ByteRange(0, 9)),
          throwsA(isA<SparseSourceDisposed>()),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
