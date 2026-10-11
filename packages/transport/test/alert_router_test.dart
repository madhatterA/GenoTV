import 'package:contracts/contracts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/src/torrent/alert_router.dart';

void main() {
  test('metadata and play-head completion move metadata to ready', () {
    final router = AlertRouter();
    router.route(const TorrentAlert(TorrentAlertKind.metadataReceived));
    router.waitAt(7);
    router.route(const TorrentAlert(TorrentAlertKind.pieceFinished, piece: 6));
    expect(router.state, SourceState.buffering);
    router.route(const TorrentAlert(TorrentAlertKind.pieceFinished, piece: 7));
    expect(router.state, SourceState.ready);
  });

  test('stall and no peers use distinct typed failures', () {
    final start = DateTime.utc(2026);
    final stalled = AlertRouter()..waitAt(3, now: start);
    stalled.checkStall(now: start.add(torrentStallThreshold));
    expect(stalled.failure?.code, 'transport.torrent.stalled');

    final noPeers = AlertRouter();
    noPeers.route(
      const TorrentAlert(TorrentAlertKind.metadataReceived),
      now: start,
    );
    noPeers.updatePeers(0, now: start);
    noPeers.updatePeers(0, now: start.add(torrentNoPeersThreshold));
    expect(noPeers.failure?.code, 'transport.torrent.no_peers');
  });

  test('tracker errors are nonfatal and file errors preserve the cause', () {
    final router = AlertRouter();
    router.route(
      const TorrentAlert(TorrentAlertKind.trackerError, error: 'tracker'),
    );
    expect(router.failure, isNull);
    const cause = 'error=28 no space left';
    router.route(const TorrentAlert(TorrentAlertKind.fileError, error: cause));
    expect(router.failure?.code, 'transport.torrent.file_error');
    expect(router.failure?.cause, cause);
  });

  test('routes a burst of 10000 piece alerts without losing state', () {
    final router = AlertRouter()
      ..route(const TorrentAlert(TorrentAlertKind.metadataReceived))
      ..waitAt(9999);
    for (var piece = 0; piece < 10000; piece++) {
      router.route(TorrentAlert(TorrentAlertKind.pieceFinished, piece: piece));
    }
    expect(router.state, SourceState.ready);
  });

  test('a piece already on disk never stalls; a stall ends with the next wait', () {
    final start = DateTime.utc(2026);
    final have = AlertRouter()..waitAt(3, have: true, now: start);
    have.checkStall(now: start.add(torrentStallThreshold * 3));
    expect(have.failure, isNull);
    expect(have.state, SourceState.ready);

    final r = AlertRouter()..waitAt(3, now: start);
    r.checkStall(now: start.add(torrentStallThreshold));
    expect(r.state, SourceState.stalled);
    r.waitAt(4, now: start.add(torrentStallThreshold));
    expect(r.failure, isNull); // status ctor: failure iff failed/stalled
    expect(r.state, SourceState.buffering);
    r.route(const TorrentAlert(TorrentAlertKind.pieceFinished, piece: 4));
    expect(r.state, SourceState.ready);
  });

  test('a real failure is not cleared by a later wait', () {
    final r = AlertRouter()
      ..route(const TorrentAlert(TorrentAlertKind.torrentError, error: 'x'))
      ..waitAt(1);
    expect(r.state, SourceState.failed);
    expect(r.failure, isNotNull);
  });

  test('pieces finishing elsewhere keep a waiting stream from stalling', () {
    final start = DateTime.utc(2026);
    final r = AlertRouter()..waitAt(3, now: start);
    final later = start.add(torrentStallThreshold - const Duration(seconds: 1));
    r.route(const TorrentAlert(TorrentAlertKind.pieceFinished, piece: 9), now: later);
    r.checkStall(now: start.add(torrentStallThreshold));
    expect(r.failure, isNull);
    r.checkStall(now: later.add(torrentStallThreshold));
    expect(r.state, SourceState.stalled);
  });
}
