import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/lt_bindings.dart';
import 'package:transport/src/torrent/lt_ffi_session.dart';

void main() {
  test(
    'every native output allocation preserves canaries',
    () async {
      final libraryPath = '${Directory.current.path}/macos/libs/libtransport_lt_shim.dylib';
      if (!File(libraryPath).existsSync()) fail('missing packaged native artifact: $libraryPath');
      final library = DynamicLibrary.open(libraryPath);
      final bindings = LtBindings(library);
      final fixture = await Process.start('python3', <String>[
        'tool/libtorrent_magnet_fixture.py',
      ], workingDirectory: Directory.current.path);
      final magnet = Completer<String>();
      final stdoutSub = fixture.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('magnet=') && !magnet.isCompleted) {
              magnet.complete(line.substring(7));
            }
          });
      final stderrSub = fixture.stderr.drain<void>();
      final cache = await Directory.systemTemp.createTemp('transport-ffi-canary-');
      LtFfiSession? session;
      LtTorrent? torrent;
      try {
        session = LtFfiSession(library: library);
        torrent = session.addMagnet(
          await magnet.future.timeout(const Duration(seconds: 30)),
          savePath: cache.path,
        );
        final metadataDeadline = DateTime.now().add(const Duration(seconds: 60));
        while (!torrent.metadataReady && DateTime.now().isBefore(metadataDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(torrent.metadataReady, isTrue, reason: session.error);

        withCanary<LtFileInfo>(sizeOf<LtFileInfo>(), (p) {
          final path = _guarded<Utf8>(4096);
          try {
            expect(bindings.fileInfo(torrent!.nativeHandle, 0, p.cast<LtFileInfo>(), path.pointer, 4096), greaterThanOrEqualTo(0));
            path.check();
          } finally {
            path.free();
          }
        });
        final pieces = torrent.pieceCount;
        withCanary<Uint8>(pieces, (p) {
          expect(bindings.copyBitfield(torrent!.nativeHandle, p, pieces), greaterThanOrEqualTo(0));
        });
        withCanary<Int32>(sizeOf<Int32>(), (peers) {
          withCanary<Int32>(sizeOf<Int32>(), (state) {
            withCanary<Int64>(sizeOf<Int64>(), (done) {
              withCanary<Int64>(sizeOf<Int64>(), (total) {
                withCanary<Int32>(sizeOf<Int32>(), (rate) {
                  expect(bindings.status(torrent!.nativeHandle, peers.cast(), state.cast(), done.cast(), total.cast(), rate.cast()), 0);
                });
              });
            });
          });
        });
        withCanary<LtAlert>(sizeOf<LtAlert>() * 256, (records) {
          final messages = _guarded<Utf8>(16 * 1024);
          try {
            expect(bindings.popAlerts(session!.nativeHandle, records.cast(), 256, messages.pointer, 16 * 1024), greaterThanOrEqualTo(0));
            messages.check();
          } finally {
            messages.free();
          }
        });

        torrent.setPiecePriority(0, 7);
        torrent.setPieceDeadline(0, 0);
        final pieceDeadline = DateTime.now().add(const Duration(seconds: 60));
        while (!torrent.pieceAvailable(0) && DateTime.now().isBefore(pieceDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(torrent.pieceAvailable(0), isTrue, reason: session.error);
        withCanary<Uint8>(4096, (out) {
          expect(bindings.read(torrent!.nativeHandle, 0, 0, out, 4096), 4096);
        });
        withCanary<Uint8>(1024 * 1024, (resume) {
          expect(bindings.saveResume(torrent!.nativeHandle, resume, 1024 * 1024), greaterThan(0));
        });
      } finally {
        await torrent?.close();
        await session?.dispose();
        // Terminate before waiting for pipe EOF; the fixture may still be running.
        fixture.kill(ProcessSignal.sigterm);
        await stdoutSub.cancel();
        await fixture.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
          fixture.kill(ProcessSignal.sigkill);
          return -9;
        });
        await stderrSub;
        await cache.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

void withCanary<T extends NativeType>(int bytes, void Function(Pointer<Uint8>) body) {
  const guardBytes = 32;
  final allocation = calloc<Uint8>(bytes + guardBytes * 2);
  final view = allocation.asTypedList(bytes + guardBytes * 2);
  view.fillRange(0, view.length, 0xA5);
  final payload = allocation + guardBytes;
  try {
    body(payload);
    expect(view.sublist(0, guardBytes), everyElement(0xA5));
    expect(view.sublist(guardBytes + bytes), everyElement(0xA5));
  } finally {
    calloc.free(allocation);
  }
}

_Guarded<T> _guarded<T extends NativeType>(int bytes) {
  final allocation = calloc<Uint8>(bytes + 64);
  final view = allocation.asTypedList(bytes + 64);
  view.fillRange(0, view.length, 0xA5);
  return _Guarded(allocation, (allocation + 32).cast<T>(), view, bytes);
}

final class _Guarded<T extends NativeType> {
  _Guarded(this._allocation, this.pointer, this._view, this._bytes);
  final Pointer<Uint8> _allocation;
  final Pointer<T> pointer;
  final Uint8List _view;
  final int _bytes;
  void check() {
    expect(_view.sublist(0, 32), everyElement(0xA5));
    expect(_view.sublist(32 + _bytes), everyElement(0xA5));
  }
  void free() => calloc.free(_allocation);
}
