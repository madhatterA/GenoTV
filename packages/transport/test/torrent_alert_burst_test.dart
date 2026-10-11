// Real-fixture proof for Phase 08 item 4: alert drop counter is zero under a
// real, high-volume native alert burst (not the Dart-level synthetic burst
// already covered by alert_router_test.dart's 10,000-alert routing test).
//
// tool/libtorrent_multifile_fixture.py takes an optional piece-length argument
// (added for this proof): a small piece length over the fixture's ~101 MiB
// Movie.mkv produces thousands of real piece_finished alerts from a genuine
// local libtorrent download, without needing a bigger fixture file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/lt_ffi_session.dart';
import 'package:transport/src/torrent/media_file_selector.dart';
import 'package:transport/src/torrent/piece_mapper.dart';
import 'package:transport/src/torrent/torrent_metadata.dart';
import 'package:transport/src/torrent/torrent_sparse_source.dart';

const int _alertsDroppedKind = 10; // TRANSPORT_LT_ALERT_ALERTS_DROPPED, lt_shim.h
const int _pieceFinishedKind = 2; // TRANSPORT_LT_ALERT_PIECE_FINISHED

void main() {
  test('native alert burst: full-file download produces thousands of real alerts, zero drops', () async {
    // 8 KiB pieces over ~101 MiB -> ~12,900 real piece_finished alerts from
    // Movie.mkv alone, plus Sample/sample.mkv's own pieces -- comfortably over
    // the Phase's literal 10,000-alert burst target, all genuine native
    // libtorrent alerts popped through transport_lt_pop_alerts, not synthetic
    // Dart values.
    final fixture = await Process.start('python3', <String>[
      'tool/libtorrent_multifile_fixture.py',
      '8192',
    ], workingDirectory: Directory.current.path);
    final jsonCompleter = Completer<Map<String, dynamic>>();
    final stdoutSub = fixture.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      if (line.startsWith('{') && !jsonCompleter.isCompleted) jsonCompleter.complete(jsonDecode(line) as Map<String, dynamic>);
    });
    final stderrSub = fixture.stderr.drain<void>();
    try {
      final info = await jsonCompleter.future.timeout(const Duration(seconds: 30));
      final cache = await Directory.systemTemp.createTemp('transport-alert-burst-');
      final session = LtFfiSession();
      try {
        final torrent = session.addMagnet(info['magnet'] as String, savePath: cache.path);
        try {
          final deadline = DateTime.now().add(const Duration(seconds: 30));
          while (!torrent.metadataReady && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          expect(torrent.metadataReady, isTrue, reason: session.error);

          final alertCounts = <int, int>{};
          var droppedCount = 0;
          final sub = session.alerts.listen((event) {
            alertCounts[event.kind] = (alertCounts[event.kind] ?? 0) + 1;
            if (event.kind == _alertsDroppedKind) droppedCount++;
          });
          try {
            final files = [
              for (var i = 0; i < torrent.fileCount; i++)
                () {
                  final f = torrent.file(i);
                  return TorrentFile(path: f.path, offset: f.offset, length: f.size);
                }(),
            ];
            final selected = const MediaFileSelector().select(TorrentMetadata(files: files, pieceLength: torrent.pieceLength));
            final fileIndex = files.indexOf(selected);
            torrent.prioritizeFiles(<int>[for (var i = 0; i < files.length; i++) i == fileIndex ? 7 : 0]);
            final mapper = PieceMapper(pieceLength: torrent.pieceLength, fileOffsetInTorrent: selected.offset, fileLength: selected.length);
            final source = TorrentSparseSource.fromNative(torrent: torrent, fileIndex: fileIndex, mapper: mapper);
            try {
              final fullRange = ByteRange(0, selected.length - 1);
              await source.waitFor(fullRange).timeout(const Duration(minutes: 3));

              // Give the poll-drain timer a few more cycles to flush anything
              // still in libtorrent's own alert queue after the last piece
              // completed.
              await Future<void>.delayed(const Duration(milliseconds: 500));

              final pieceFinishedCount = alertCounts[_pieceFinishedKind] ?? 0;
              final totalAlerts = alertCounts.values.fold(0, (a, b) => a + b);
              printOnFailure('alert counts by kind: $alertCounts');
              printOnFailure('total alerts=$totalAlerts piece_finished=$pieceFinishedCount dropped=$droppedCount '
                  '(alert_queue_size=20000, lt_shim.cpp)');
              expect(droppedCount, 0, reason: 'a nonzero drop count under real load is the defect this proof exists to catch');
              expect(totalAlerts, greaterThanOrEqualTo(10000), reason: 'the Phase names a literal 10,000-alert burst; the 8 KiB piece length must clear it');
            } finally {
              await source.dispose();
            }
          } finally {
            await sub.cancel();
          }
        } finally {
          await torrent.close();
        }
      } finally {
        await session.dispose();
      }
      await cache.delete(recursive: true);
    } finally {
      fixture.kill(ProcessSignal.sigkill);
      await stdoutSub.cancel();
      await stderrSub;
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
