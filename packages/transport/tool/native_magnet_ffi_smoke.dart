import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:transport/src/torrent/lt_ffi_session.dart';

Future<void> main() async {
  final fixture = await Process.start('python3', <String>[
    'tool/libtorrent_magnet_fixture.py',
  ]);
  final lines = fixture.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter());
  final magnet = Completer<String>();
  final output = <String>[];
  final subscription = lines.listen((line) {
    output.add(line);
    if (line.startsWith('magnet=') && !magnet.isCompleted) {
      magnet.complete(line.substring(7));
    }
  });
  final errors = fixture.stderr.transform(utf8.decoder).listen(output.add);
  final cache = await Directory.systemTemp.createTemp('transport-native-ffi-');
  LtFfiSession? session;
  LtTorrent? torrent;
  try {
    final uri = await magnet.future.timeout(const Duration(seconds: 30));
    session = LtFfiSession();
    torrent = session.addMagnet(uri, savePath: cache.path);
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (!torrent.metadataReady && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!torrent.metadataReady) {
      throw StateError('metadata timeout: ${torrent.status.peers} peers ${session.error}');
    }
    final file = torrent.file(0);
    while (!torrent.pieceAvailable(0) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final bytes = Uint8List(4096);
    final count = torrent.read(0, 0, bytes);
    if (count != bytes.length) throw StateError('short native read: $count');
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] != i % 251) throw StateError('checksum mismatch at $i');
    }
    final seekOffset = 24 * 1024 * 1024;
    final seekPiece = seekOffset ~/ torrent.pieceLength;
    torrent.setPiecePriority(seekPiece, 7);
    torrent.setPieceDeadline(seekPiece, 0);
    while (!torrent.pieceAvailable(seekPiece) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final seekBytes = Uint8List(4096);
    final seekCount = torrent.read(0, seekOffset, seekBytes);
    if (seekCount != seekBytes.length) {
      throw StateError('short native seek read: $seekCount');
    }
    for (var i = 0; i < seekBytes.length; i++) {
      if (seekBytes[i] != (i + seekOffset) % 251) {
        throw StateError('seek checksum mismatch at $i');
      }
    }
    stdout.writeln('native magnet ffi passed: ${file.path} ${file.size} bytes');
  } finally {
    await torrent?.close();
    await session?.dispose();
    await subscription.cancel();
    await errors.cancel();
    fixture.kill(ProcessSignal.sigterm);
    await fixture.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      fixture.kill(ProcessSignal.sigkill);
      return -9;
    });
    await cache.delete(recursive: true);
    if (output.any((line) => line.contains('torrent fixture did not resolve'))) {
      stderr.writeln(output.join('\n'));
    }
  }
}
