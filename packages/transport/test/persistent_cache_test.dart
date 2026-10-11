import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/fakes/fake_repositories.dart';
import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

const _mib = 1024 * 1024;
const _total = 20 * _mib;

Uint8List _bytes(int start, int count) {
  final out = Uint8List(count);
  for (var i = 0; i < count; i++) {
    final at = start + i;
    out[i] = (at * 31 + (at >> 8)) & 0xff;
  }
  return out;
}

String _sourceSha(int total) => sha256.convert(_bytes(0, total)).toString();

Future<String> _fileSha(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Bytes of a range read through the local range server, as sha256.
Future<String> _readSha(HttpClient client, Uri uri, int total) async {
  final req = await client.getUrl(uri);
  req.headers.set('range', 'bytes=0-${total - 1}');
  final res = await req.close();
  return (await sha256.bind(res).first).toString();
}

Future<void> _untilComplete(StreamHandle handle, int total) => handle.status
    .firstWhere((s) => s.available.containsRange(ByteRange(0, total - 1)))
    .timeout(const Duration(seconds: 30));

File _partial(Directory cache) => cache
    .listSync()
    .whereType<File>()
    .firstWhere((f) => f.path.endsWith('.partial'));

void main() {
  late Directory cache;
  late HttpServer origin;
  var requests = 0;
  late FakeTransportStateRepository state;
  late HttpClient client;

  SourceSpec spec(String name) => SourceSpec(
    kind: SourceKind.httpUrl,
    uri: Uri.parse('http://127.0.0.1:${origin.port}/$name'),
  );

  setUp(() async {
    cache = await Directory.systemTemp.createTemp('persistent-cache-');
    state = FakeTransportStateRepository();
    client = HttpClient();
    requests = 0;
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((req) async {
      requests++;
      final m = RegExp(
        r'bytes=(\d+)-(\d*)',
      ).firstMatch(req.headers.value('range') ?? '');
      final start = m == null ? 0 : int.parse(m[1]!);
      final end = m == null || m[2]!.isEmpty ? _total - 1 : int.parse(m[2]!);
      req.response.headers.set('accept-ranges', 'bytes');
      if (m != null) {
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set('content-range', 'bytes $start-$end/$_total');
      }
      req.response.contentLength = end - start + 1;
      if (req.method != 'HEAD') {
        try {
          for (var at = start; at <= end; at += _mib) {
            req.response.add(_bytes(at, (end - at + 1).clamp(0, _mib)));
            await req.response.flush();
          }
        } on Object {
          // client closed mid-range
        }
      }
      await req.response.close().catchError((Object _) => req.response);
    });
  });

  tearDown(() async {
    client.close(force: true);
    await origin.close(force: true);
    await cache.delete(recursive: true);
  });

  test('HTTP: whole file kept, replayed offline, expired and evicted', () async {
    final expected = _sourceSha(_total);
    const big = TransportOptions(cacheLimitBytes: 64 * _mib);
    var source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: cache,
      state: state,
    );
    var handle = await source.open(spec('a.bin'), options: big);
    // (a) read only the first 1 MB; the transport still fetches everything.
    final req = await client.getUrl(handle.playbackUri);
    req.headers.set('range', 'bytes=0-${_mib - 1}');
    await (await req.close()).drain<void>();
    await _untilComplete(handle, _total);
    expect(await _fileSha(_partial(cache)), expected);
    // (b) close the stream and the transport.
    await handle.dispose();
    await source.dispose();
    expect(_partial(cache).existsSync(), isTrue, reason: 'kept after close');

    // (c) new transport, origin stopped: the full file plays from disk.
    final before = requests;
    final offline = spec('a.bin');
    await origin.close(force: true);
    source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: cache,
      state: state,
    );
    handle = await source.open(offline, options: big);
    expect(await _readSha(client, handle.playbackUri, _total), expected);
    expect(requests, before, reason: 'no request reached the origin');
    await handle.dispose();
    await source.dispose();
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('HTTP: 7-day expiry and oldest-first eviction', () async {
    const big = TransportOptions(cacheLimitBytes: 64 * _mib);
    Future<void> play(StreamSourceImpl s, String name, {bool keep = false}) async {
      final handle = await s.open(spec(name), options: big);
      await _untilComplete(handle, _total);
      if (!keep) await handle.dispose();
    }

    var source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: cache,
      state: state,
    );
    await play(source, 'old.bin');
    await play(source, 'a.bin');
    await source.dispose();
    // (d) old.bin was last played 8 days ago.
    final old = (await state.get(deriveSourceKey(spec('old.bin'))))!;
    await state.upsert(
      DownloadRecord(
        sourceKey: old.sourceKey,
        kind: old.kind,
        filePath: old.filePath,
        totalBytes: old.totalBytes,
        validator: old.validator,
        lastUsedAt: DateTime.now().toUtc().subtract(const Duration(days: 8)),
      ),
    );
    source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: cache,
      state: state,
    );
    await play(source, 'b.bin');
    expect(File(old.filePath!).existsSync(), isFalse, reason: '8 days old');
    final a = (await state.get(deriveSourceKey(spec('a.bin'))))!;
    expect(File(a.filePath!).existsSync(), isTrue);

    // (e) limit for two files: with c.bin open (never deleted), opening the
    // next one removes the oldest closed entry first.
    await play(source, 'c.bin', keep: true);
    final c = (await state.get(deriveSourceKey(spec('c.bin'))))!;
    final b = (await state.get(deriveSourceKey(spec('b.bin'))))!;
    final tight = TransportOptions(cacheLimitBytes: 2 * _total + _mib);
    final next = await source.open(spec('d.bin'), options: tight);
    expect(File(a.filePath!).existsSync(), isFalse, reason: 'oldest evicted');
    expect(File(b.filePath!).existsSync(), isTrue);
    expect(File(c.filePath!).existsSync(), isTrue, reason: 'open stream kept');
    await next.dispose();
    await source.dispose();
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('torrent: whole file kept and replayed with the seeder gone', () async {
    final media = File('${cache.path}/seed/clip.bin')
      ..createSync(recursive: true);
    final raf = media.openSync(mode: FileMode.write);
    for (var at = 0; at < _total; at += _mib) {
      raf.writeFromSync(_bytes(at, _mib));
    }
    raf.closeSync();
    final seeder = await Process.start('python3', [
      'test/harness/torrent_seeder.py',
      media.path,
    ]);
    addTearDown(() => seeder.kill(ProcessSignal.sigkill));
    final magnet = Completer<String>();
    seeder.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('magnet=') && !magnet.isCompleted) {
            magnet.complete(line.substring(7));
          }
        });
    unawaited(seeder.stderr.drain<void>());
    final dir = Directory('${cache.path}/cache')..createSync();
    final torrent = SourceSpec(
      kind: SourceKind.torrentMagnet,
      uri: Uri.parse(await magnet.future.timeout(const Duration(seconds: 30))),
    );
    const big = TransportOptions(cacheLimitBytes: 64 * _mib);
    var source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: dir,
      state: state,
    );
    var handle = await source
        .open(torrent, options: big)
        .timeout(const Duration(seconds: 60));
    final req = await client.getUrl(handle.playbackUri);
    req.headers.set('range', 'bytes=0-${_mib - 1}');
    await (await req.close()).drain<void>();
    await _untilComplete(handle, _total);
    final onDisk = File('${dir.path}/clip.bin');
    final expected = _sourceSha(_total);
    expect(await _fileSha(onDisk), expected);
    await handle.dispose();
    await source.dispose();

    seeder.kill(ProcessSignal.sigkill);
    await seeder.exitCode;
    source = StreamSourceImpl(
      logger: MemoryLogger(),
      cacheDir: dir,
      state: state,
    );
    handle = await source
        .open(torrent, options: big)
        .timeout(const Duration(seconds: 60));
    expect(await _readSha(client, handle.playbackUri, _total), expected);
    await handle.dispose();
    await source.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
