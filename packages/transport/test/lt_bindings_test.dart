// Phase 02 proof: dart:ffi bindings over the Phase 01 C ABI, exercised directly
// (no TorrentSession/LtFfiSession wrapper — that is Phase 03's own layer).
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/lt_bindings.dart';

void main() {
  final libraryPath =
      '${Directory.current.path}/macos/libs/libtransport_lt_shim.dylib';

  test('library loads on the host platform', () {
    expect(
      File(libraryPath).existsSync(),
      isTrue,
      reason: 'missing packaged native artifact: $libraryPath',
    );
    final library = DynamicLibrary.open(libraryPath);
    final bindings = LtBindings(library);
    final session = bindings.create();
    expect(session, isNot(equals(nullptr)));
    bindings.destroy(session);
  });

  test('round-trip: struct data read via raw bindings matches a real local magnet', () async {
    final library = DynamicLibrary.open(libraryPath);
    final bindings = LtBindings(library);
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    final magnetCompleter = Completer<String>();
    final stdoutSub = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=') && !magnetCompleter.isCompleted) {
            magnetCompleter.complete(line.substring('magnet='.length));
          }
        });
    final stderrSub = fixture.stderr.drain<void>();
    final cache = await Directory.systemTemp.createTemp(
      'transport-lt-bindings-',
    );
    final session = bindings.create();
    Pointer<Void> torrent = nullptr;
    try {
      final magnet = await magnetCompleter.future.timeout(
        const Duration(seconds: 30),
      );
      final magnetPtr = magnet.toNativeUtf8();
      final pathPtr = cache.path.toNativeUtf8();
      try {
        torrent = bindings.addMagnet(
          session,
          magnetPtr,
          magnet.length,
          pathPtr,
          cache.path.length,
          1,
        );
      } finally {
        calloc.free(magnetPtr);
        calloc.free(pathPtr);
      }
      expect(torrent, isNot(equals(nullptr)));

      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (bindings.metadataReady(torrent) != 1 &&
          DateTime.now().isBefore(deadline)) {
        final alerts = calloc<LtAlert>(64);
        final messages = calloc<Uint8>(4096);
        bindings.popAlerts(session, alerts, 64, messages.cast<Utf8>(), 4096);
        calloc.free(alerts);
        calloc.free(messages);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        bindings.metadataReady(torrent),
        1,
        reason: 'metadata never arrived within 60s',
      );

      // The fixture always seeds a single-file torrent named "seed" — assert the
      // struct fields the Phase 01 C harness itself reads for the same kind of
      // fixture: a positive piece length/count, one file, and a 40-char hex hash.
      final pieceLength = bindings.pieceLength(torrent);
      final pieceCount = bindings.pieceCount(torrent);
      final fileCount = bindings.fileCount(torrent);
      expect(pieceLength, greaterThan(0));
      expect(pieceCount, greaterThan(0));
      expect(fileCount, 1);
      for (var piece = 0; piece < pieceCount; piece++) {
        expect(
          bindings.pieceAvailable(torrent, piece),
          0,
          reason: 'metadata-only magnet must not download payload',
        );
      }
      // Replacing one torrent must preserve another torrent's close barrier.
      final otherMagnet =
          'magnet:?xt=urn:btih:1111111111111111111111111111111111111111'
              .toNativeUtf8();
      final otherPath = cache.path.toNativeUtf8();
      try {
        final other = bindings.addMagnet(
          session,
          otherMagnet,
          otherMagnet.length,
          otherPath,
          cache.path.length,
          1,
        );
        expect(other, isNot(equals(nullptr)));
        bindings.closeTorrent(other);
        expect(
          bindings.initializeDownload(session, torrent, 0, 0, pieceCount),
          0,
        );
        expect(bindings.closeComplete(other), 1);
      } finally {
        calloc.free(otherMagnet);
        calloc.free(otherPath);
      }

      final hashBuf = calloc<Uint8>(41);
      try {
        final hashLen = bindings.infoHash(torrent, hashBuf.cast<Utf8>(), 41);
        expect(hashLen, 40);
        final hash = hashBuf.cast<Utf8>().toDartString();
        expect(hash, matches(RegExp(r'^[0-9a-f]{40}$')));
      } finally {
        calloc.free(hashBuf);
      }
    } finally {
      bindings.destroy(session);
      // Terminate before waiting for pipe EOF; the fixture may still be running.
      fixture.kill(ProcessSignal.sigterm);
      await stdoutSub.cancel();
      await fixture.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
      await stderrSub;
      await cache.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a freed session handle, passed to the raw FFI surface, returns a typed error and does not crash', () {
    final library = DynamicLibrary.open(libraryPath);
    final bindings = LtBindings(library);
    final session = bindings.create();
    bindings.destroy(session);

    // Calling through the raw FFI surface with a handle the shim has already
    // freed proves the native-side registry guard (lt_shim.cpp's live_sessions/
    // live_torrents check), not any Dart-side guard — LtBindings has none.
    // transport_lt_session_last_error, called with a destroyed session pointer,
    // must return the "no such live session" path (0, empty buffer) rather than
    // dereferencing freed memory.
    final buf = calloc<Uint8>(64);
    try {
      final len = bindings.lastError(session, buf.cast<Utf8>(), 64);
      expect(len, 0);
    } finally {
      calloc.free(buf);
    }

    // A second destroy() of the same already-freed handle must also be a no-op,
    // not a double-free: the shim's session_destroy checks live_sessions.erase()
    // and returns immediately if the handle is already gone.
    expect(() => bindings.destroy(session), returnsNormally);

    // addMagnet against the freed session handle must return an error (null),
    // not attempt to touch the deleted Session object.
    final magnetPtr =
        'magnet:?xt=urn:btih:0000000000000000000000000000000000000000'
            .toNativeUtf8();
    final pathPtr = '/tmp'.toNativeUtf8();
    try {
      final result = bindings.addMagnet(session, magnetPtr, 60, pathPtr, 4, 0);
      expect(result, equals(nullptr));
    } finally {
      calloc.free(magnetPtr);
      calloc.free(pathPtr);
    }
  });

  test('a freed torrent handle, passed to the raw FFI surface, returns a typed error and does not crash', () async {
    final library = DynamicLibrary.open(libraryPath);
    final bindings = LtBindings(library);
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_magnet_fixture.py',
    ], workingDirectory: Directory.current.path);
    final magnetCompleter = Completer<String>();
    final stdoutSub = fixture.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=') && !magnetCompleter.isCompleted) {
            magnetCompleter.complete(line.substring('magnet='.length));
          }
        });
    final stderrSub = fixture.stderr.drain<void>();
    final cache = await Directory.systemTemp.createTemp(
      'transport-lt-bindings-freed-',
    );
    final session = bindings.create();
    try {
      final magnet = await magnetCompleter.future.timeout(
        const Duration(seconds: 30),
      );
      final magnetPtr = magnet.toNativeUtf8();
      final pathPtr = cache.path.toNativeUtf8();
      Pointer<Void> torrent;
      try {
        torrent = bindings.addMagnet(
          session,
          magnetPtr,
          magnet.length,
          pathPtr,
          cache.path.length,
          1,
        );
      } finally {
        calloc.free(magnetPtr);
        calloc.free(pathPtr);
      }
      expect(torrent, isNot(equals(nullptr)));

      // transport_lt_torrent_remove marks the torrent `closing` and asks
      // libtorrent to remove it asynchronously, but deliberately keeps the
      // Torrent* itself in the shim's live_torrents registry until session
      // teardown (lt_shim.cpp comment: "Keep the torrent_handle alive until
      // session destruction... dropping the last handle immediately can race
      // peer/disk callbacks"). So immediately after remove(), calls against
      // this handle are still routed through the registry (no dereference of
      // freed memory) but are rejected because `closing` is set.
      final removed = bindings.removeTorrent(session, torrent, 0);
      expect(removed, 0);
      expect(bindings.fileCount(torrent), -1);
      expect(bindings.pieceLength(torrent), -1);
      expect(bindings.metadataReady(torrent), -1);

      // The torrent pointer is only actually erased from live_torrents when
      // the owning session is destroyed (transport_lt_session_destroy). That
      // is the genuine "freed handle" case: valid() no longer finds it, and
      // every call short-circuits before touching the pointed-to memory.
      bindings.destroy(session);
      expect(bindings.fileCount(torrent), -1);
      expect(bindings.pieceLength(torrent), -1);
      expect(bindings.metadataReady(torrent), 0);
      expect(bindings.pieceAvailable(torrent, 0), 0);
    } finally {
      // Terminate before waiting for pipe EOF; the fixture may still be running.
      fixture.kill(ProcessSignal.sigterm);
      await stdoutSub.cancel();
      await fixture.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        },
      );
      await stderrSub;
      await cache.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 1)));
}
