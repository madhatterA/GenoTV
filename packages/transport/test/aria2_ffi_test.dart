import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/http/ffi/aria2_ffi_bindings.dart';
import 'package:transport/src/http/ffi/aria2_ffi_backend.dart';
import 'package:transport/src/http/ffi/aria2_ffi_session.dart';

void main() {
  test('aria2 status struct matches the C ABI size and fields', () {
    expect(sizeOf<Aria2DownloadStatus>(), 48);
    final pointer = calloc<Aria2DownloadStatus>();
    try {
      pointer.ref
        ..state = 1
        ..errorCode = 2
        ..connections = 3
        ..pieceLength = 4
        ..pieceCount = 5
        ..totalLength = 6
        ..completedLength = 7
        ..downloadRate = 8
        ..bitfieldLength = 9;
      expect(pointer.ref.state, 1);
      expect(pointer.ref.errorCode, 2);
      expect(pointer.ref.connections, 3);
      expect(pointer.ref.pieceLength, 4);
      expect(pointer.ref.pieceCount, 5);
      expect(pointer.ref.totalLength, 6);
      expect(pointer.ref.completedLength, 7);
      expect(pointer.ref.downloadRate, 8);
      expect(pointer.ref.bitfieldLength, 9);
    } finally {
      calloc.free(pointer);
    }
  });

  test('native bitfield bytes use the shared range converter', () {
    final status = Aria2FfiStatus(
      state: 1,
      errorCode: 0,
      connections: 1,
      pieceLength: 4,
      pieceCount: 3,
      totalLength: 12,
      completedLength: 8,
      downloadRate: 1,
      bitfield: const <int>[0xa0],
    );
    expect(
      status.available.ranges.map(
        (range) => '${range.start}-${range.endInclusive}',
      ),
      <String>['0-3', '8-11'],
    );
  });

  test(
    'paused native session releases the API lock for immediate resume',
    () async {
      final server = await _serve(List<int>.filled(4 * 1024 * 1024, 7));
      final directory = await Directory.systemTemp.createTemp('aria2-resume-');
      final session = Aria2FfiSession(openAria2Library());
      try {
        final gid = await _retryBusy(
          () => session.addUri(
            _serverUri(server, '/payload'),
            directory: directory.path,
            output: 'payload.bin',
          ),
        );
        await _waitForStatus(session, gid, (s) => s.totalLength > 0);
        await _retryBusy(() => session.setPaused(gid, paused: true));
        await _waitForStatus(session, gid, (s) => s.state == 2);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final watch = Stopwatch()..start();
        await _retryBusy(() => session.status(gid));
        await _retryBusy(() => session.setPaused(gid, paused: false));
        expect(watch.elapsedMilliseconds, lessThan(250));
      } finally {
        session.dispose();
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );

  if (Platform.isIOS) {
    test(
      'physical iPhone downloads, changes an option, and matches sha256',
      () async {
        final payload = List<int>.generate(
          1024 * 1024,
          (index) => index & 0xff,
        );
        final server = await _serve(payload);
        final directory = await Directory.systemTemp.createTemp('aria2-ffi-');
        final session = Aria2FfiSession(DynamicLibrary.process());
        try {
          final gid = await _retryBusy(
            () => session.addUri(
              _serverUri(server, '/payload'),
              directory: directory.path,
              output: 'payload.bin',
            ),
          );
          await _waitForStatus(
            session,
            gid,
            (status) => status.totalLength == payload.length,
          );
          await _retryBusy(
            () => session.changeOption(gid, 'stream-piece-selector', 'inorder'),
          );
          final complete = await _waitForStatus(
            session,
            gid,
            (status) => status.completedLength == payload.length,
          );
          expect(complete.failure, isNull);
          expect(
            complete.available.containsRange(ByteRange(0, payload.length - 1)),
            isTrue,
          );
          final downloaded = await File('${directory.path}/payload.bin')
              .readAsBytes();
          expect(sha256.convert(downloaded), sha256.convert(payload));
        } finally {
          session.dispose();
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test(
      'physical iPhone reports 404 and malformed URI as typed failures',
      () async {
        final server = await _serve(const <int>[]);
        final directory = await Directory.systemTemp.createTemp('aria2-ffi-');
        final session = Aria2FfiSession(DynamicLibrary.process());
        try {
          final missingGid = await _retryBusy(
            () => session.addUri(
              _serverUri(server, '/missing'),
              directory: directory.path,
              output: 'missing.bin',
            ),
          );
          final missing = await _waitForStatus(
            session,
            missingGid,
            (status) => status.failure != null,
          );
          expect(missing.failure, isA<Aria2FfiException>());

          Aria2FfiException? malformedFailure;
          try {
            final malformedGid = await _retryBusy(
              () => session.addUri(
                Uri.parse('unsupported:malformed'),
                directory: directory.path,
                output: 'malformed.bin',
              ),
            );
            final malformed = await _waitForStatus(
              session,
              malformedGid,
              (status) => status.failure != null,
            );
            malformedFailure = malformed.failure;
          } on Aria2FfiException catch (error) {
            malformedFailure = error;
          }
          expect(malformedFailure, isA<Aria2FfiException>());
        } finally {
          session.dispose();
          await server.close(force: true);
          await directory.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('physical iPhone create and destroy 20 times without RSS growth', () {
      Aria2FfiSession(DynamicLibrary.process()).dispose();
      final before = ProcessInfo.currentRss;
      for (var index = 0; index < 20; index++) {
        Aria2FfiSession(DynamicLibrary.process()).dispose();
      }
      final after = ProcessInfo.currentRss;
      stdout.writeln(
        'aria2 lifecycle RSS before=$before after=$after delta=${after - before}',
      );
      expect(after - before, lessThan(32 * 1024 * 1024));
    }, timeout: const Timeout(Duration(minutes: 1)));
  }
}

Future<HttpServer> _serve(List<int> payload) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    if (request.uri.path != '/payload') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    request.response.contentLength = payload.length;
    for (var offset = 0; offset < payload.length; offset += 16 * 1024) {
      final next = offset + 16 * 1024;
      final end = next < payload.length ? next : payload.length;
      request.response.add(payload.sublist(offset, end));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await request.response.close();
  });
  return server;
}

Uri _serverUri(HttpServer server, String path) =>
    Uri.parse('http://${server.address.address}:${server.port}$path');

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

Future<Aria2FfiStatus> _waitForStatus(
  Aria2FfiSession session,
  int gid,
  bool Function(Aria2FfiStatus status) predicate,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final status = await _retryBusy(() => session.status(gid));
    if (predicate(status)) return status;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw TimeoutException('aria2 status condition was not reached');
}
