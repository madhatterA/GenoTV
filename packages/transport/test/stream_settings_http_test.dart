import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:transport/transport.dart';

import 'support/settings_proof.dart';

SourceSpec _spec(Uri uri, {Map<String, String> headers = const {}}) =>
    SourceSpec(kind: SourceKind.httpUrl, uri: uri, headers: headers);

void main() {
  late Directory cache;
  late ProofOrigin origin;
  setUp(() async {
    cache = await Directory.systemTemp.createTemp('transport-settings-http-');
    origin = await ProofOrigin.start();
  });
  tearDown(() async {
    await origin.close();
    await cache.delete(recursive: true);
  });

  Future<String> readJobOption(
    TransportOptions options,
    String name, {
    bool bounded = true,
  }) async {
    final backend = Aria2FfiBackend();
    try {
      final id = await backend.addDownload(
        _spec(origin.uri),
        '${cache.path}/${name.hashCode}-${options.hashCode}.partial',
        totalBytes: bounded ? origin.size : null,
        initialWindow: bounded ? const ByteRange(0, 2 * 1024 * 1024 - 1) : null,
        options: options,
      );
      return await backend.jobOption(id, name);
    } finally {
      await backend.stop();
    }
  }

  void row(
    String setting,
    String value,
    String sent,
    String got,
    String expected,
  ) {
    readbackRow(
      setting: setting,
      value: value,
      sent: sent,
      readBack: got,
      pass: got == expected,
    );
    expect(got, expected, reason: '$setting=$value');
  }

  test('aria2 job options read back from the real libaria2 session', () async {
    // Auto: aria2StreamingOptions' own split 4.
    row(
      'streaming.maxHttpConnections',
      'Auto (0)',
      'split=4 (today)',
      await readJobOption(const TransportOptions(), 'split'),
      '4',
    );
    row(
      'streaming.maxHttpConnections',
      '8',
      'split=8',
      await readJobOption(
        const TransportOptions(maxHttpConnections: 8),
        'split',
      ),
      '8',
    );
    row(
      'streaming.maxHttpConnections',
      '8',
      'max-connection-per-server=8',
      await readJobOption(
        const TransportOptions(maxHttpConnections: 8),
        'max-connection-per-server',
      ),
      '8',
    );
    row(
      'streaming.connectionTimeout',
      'Auto (0)',
      '(none)',
      await readJobOption(const TransportOptions(), 'connect-timeout'),
      '60',
    );
    row(
      'streaming.connectionTimeout',
      '20',
      'connect-timeout=20',
      await readJobOption(
        const TransportOptions(connectTimeoutSeconds: 20),
        'connect-timeout',
      ),
      '20',
    );
    row(
      'streaming.connectionTimeout',
      '20',
      'timeout=20',
      await readJobOption(
        const TransportOptions(connectTimeoutSeconds: 20),
        'timeout',
      ),
      '20',
    );
    row(
      'streaming.retryCount',
      'Auto (0)',
      '(none)',
      await readJobOption(const TransportOptions(), 'max-tries'),
      '5',
    );
    row(
      'streaming.retryCount',
      '3',
      'max-tries=4',
      await readJobOption(const TransportOptions(retryCount: 3), 'max-tries'),
      '4',
    );
    row(
      'streaming.quality',
      'Auto / Original',
      '(none)',
      await readJobOption(const TransportOptions(), 'max-download-limit'),
      '0',
    );
    row(
      'streaming.quality',
      '4 Mbps',
      'max-download-limit=500000',
      await readJobOption(
        const TransportOptions(streamDownloadBytesPerSecond: 500000),
        'max-download-limit',
      ),
      '500000',
    );
    row(
      'downloads.bandwidthLimit',
      '0',
      '(none)',
      await readJobOption(const TransportOptions(), 'max-download-limit'),
      '0',
    );
    row(
      'downloads.bandwidthLimit',
      '500 KB/s',
      'max-download-limit=512000',
      await readJobOption(
        const TransportOptions(globalDownloadBytesPerSecond: 512000),
        'max-download-limit',
      ),
      '512000',
    );
    row(
      'streaming.quality + downloads.bandwidthLimit',
      '4 Mbps + 500 KB/s',
      'lower wins: 500000',
      await readJobOption(
        const TransportOptions(
          streamDownloadBytesPerSecond: 500000,
          globalDownloadBytesPerSecond: 512000,
        ),
        'max-download-limit',
      ),
      '500000',
    );
  });

  test('origin-facing aria2 options (no bounded window) read back', () async {
    row(
      'streaming.proxy',
      'default',
      '(none)',
      await readJobOption(
        const TransportOptions(),
        'all-proxy',
        bounded: false,
      ),
      '',
    );
    row(
      'streaming.proxy',
      'http://127.0.0.1:9',
      'all-proxy=http://127.0.0.1:9',
      await readJobOption(
        const TransportOptions(proxy: 'http://127.0.0.1:9'),
        'all-proxy',
        bounded: false,
      ),
      'http://127.0.0.1:9/',
    );
    row(
      'streaming.userAgent',
      'Probe/1.0',
      'user-agent=Probe/1.0',
      await readJobOption(
        const TransportOptions(userAgent: 'Probe/1.0'),
        'user-agent',
        bounded: false,
      ),
      'Probe/1.0',
    );
    row(
      'streaming.tls',
      'Verify',
      '(session option, none)',
      await readJobOption(
        const TransportOptions(),
        'check-certificate',
        bounded: false,
      ),
      'true',
    );
    await expectLater(
      readJobOption(
        const TransportOptions(verifyTls: false),
        'check-certificate',
        bounded: false,
      ),
      throwsA(isA<TransportFailure>()),
    );
  });

  test('live rate cap reaches a running aria2 job', () async {
    final backend = Aria2FfiBackend();
    try {
      final id = await backend.addDownload(
        _spec(origin.uri),
        '${cache.path}/live.partial',
        totalBytes: origin.size,
        initialWindow: const ByteRange(0, 2 * 1024 * 1024 - 1),
      );
      expect(await backend.jobOption(id, 'max-download-limit'), '0');
      await backend.updateOptions(
        const TransportOptions(globalDownloadBytesPerSecond: 256000),
      );
      row(
        'downloads.bandwidthLimit (live)',
        '250 KB/s',
        'changeOption max-download-limit=256000',
        await backend.jobOption(id, 'max-download-limit'),
        '256000',
      );
    } finally {
      await backend.stop();
    }
  });

  test('bandwidth cap: measured rate stays within limit + 10 %', () async {
    const limit = 1024 * 1024;
    const window = 4 * 1024 * 1024;
    // Seconds until the first 4 MiB are on disk; the rate is what the cap
    // allowed over that time (4 s at 1 MiB/s).
    Future<double> seconds(TransportOptions options) async {
      final backend = Aria2FfiBackend();
      final watch = Stopwatch()..start();
      try {
        final id = await backend.addDownload(
          _spec(origin.uri),
          '${cache.path}/rate-${options.hashCode}.partial',
          totalBytes: origin.size,
          initialWindow: const ByteRange(0, window - 1),
          options: options,
        );
        await backend.changeWindow(id, const ByteRange(0, window - 1));
        while (true) {
          final have = (await backend.status(id)).available.ranges.fold<int>(
            0,
            (sum, r) => sum + r.length,
          );
          if (have >= window) break;
          await Future<void>.delayed(const Duration(milliseconds: 50));
          if (watch.elapsed > const Duration(seconds: 20)) fail('no progress');
        }
        return watch.elapsedMilliseconds / 1000;
      } finally {
        await backend.stop();
      }
    }

    final free = await seconds(const TransportOptions());
    final capped = await seconds(
      const TransportOptions(streamDownloadBytesPerSecond: limit),
    );
    final rate = window / capped;
    readbackRow(
      setting: 'rate (measured)',
      value: '1 MiB/s cap vs none',
      sent: 'max-download-limit=$limit',
      readBack:
          '${(rate / 1024).round()} KiB/s over ${capped.toStringAsFixed(1)} s '
          '(uncapped: ${free.toStringAsFixed(1)} s)',
      pass: rate <= limit * 1.1,
    );
    expect(rate, lessThanOrEqualTo(limit * 1.1));
    expect(capped, greaterThan(free * 2), reason: 'the cap must slow it');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('user agent and custom headers reach the origin; source headers win', () async {
    final source = StreamSourceImpl(logger: QuietLogger(), cacheDir: cache);
    try {
      final handle = await source.open(
        _spec(origin.uri, headers: {'X-Spec': 'from-source'}),
        options: const TransportOptions(
          userAgent: 'ProofAgent/9.9',
          headers: {'X-Custom': 'abc', 'x-spec': 'from-settings'},
        ),
      );
      await fetchRange(handle.playbackUri, 0, 4096);
      await handle.dispose();
    } finally {
      await source.dispose();
    }
    final head = origin.requests.first;
    final get = origin.requests.lastWhere((r) => r['range'] != null);
    for (final seen in [head, get]) {
      expect(seen['user-agent'], 'ProofAgent/9.9');
      expect(seen['x-custom'], 'abc');
      expect(seen['x-spec'], 'from-source');
    }
    readbackRow(
      setting: 'streaming.userAgent + streaming.headers (origin log)',
      value: 'ProofAgent/9.9 + X-Custom: abc',
      sent: 'HttpClient.userAgent + headers',
      readBack:
          'ua=${get['user-agent']} x-custom=${get['x-custom']} x-spec=${get['x-spec']}',
      pass: true,
    );
  });

  test('proxy: requests arrive at a local proxy and the stream still plays', () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final seen = <String>[];
    proxy.listen((request) async {
      seen.add('${request.method} ${request.uri}');
      final client = HttpClient();
      final upstream = await client.openUrl(request.method, request.uri);
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) upstream.headers.set(HttpHeaders.rangeHeader, range);
      final response = await upstream.close();
      request.response.statusCode = response.statusCode;
      response.headers.forEach(
        (k, v) => k == 'transfer-encoding'
            ? null
            : request.response.headers.set(k, v),
      );
      await request.response.addStream(response);
      await request.response.close();
      client.close();
    });
    final source = StreamSourceImpl(logger: QuietLogger(), cacheDir: cache);
    try {
      final handle = await source.open(
        _spec(origin.uri),
        options: TransportOptions(proxy: 'http://127.0.0.1:${proxy.port}'),
      );
      expect(await fetchRange(handle.playbackUri, 0, 4096), 4096);
      await handle.dispose();
    } finally {
      await source.dispose();
      await proxy.close(force: true);
    }
    expect(seen, contains('HEAD ${origin.uri}'));
    expect(seen.any((l) => l.startsWith('GET ${origin.uri}')), isTrue);
    readbackRow(
      setting: 'streaming.proxy (proxy log)',
      value: 'http://127.0.0.1:<proxy>',
      sent: 'HttpClient.findProxy',
      readBack: seen.take(2).join(' ; '),
      pass: true,
    );
  });

  test('a socks5 proxy on an HTTP source fails loudly', () async {
    final source = StreamSourceImpl(logger: QuietLogger(), cacheDir: cache);
    try {
      final handle = await source.open(
        _spec(origin.uri),
        options: const TransportOptions(proxy: 'socks5://127.0.0.1:1080'),
      );
      expect(handle.status, isNotNull);
      final status = await handle.status.first;
      expect(status.failure, isA<TransportFailure>());
      expect(origin.requests, isEmpty);
    } finally {
      await source.dispose();
    }
  });

  test('max HTTP connections: aria2 never holds more than N at once', () async {
    final slow = await ProofOrigin.start(
      size: 48 * 1024 * 1024,
      chunkDelay: const Duration(milliseconds: 25),
    );
    Future<int> peak(int n) async {
      final backend = Aria2FfiBackend();
      var most = 0;
      try {
        final id = await backend.addDownload(
          _spec(slow.uri),
          '${cache.path}/conn-$n.partial',
          totalBytes: slow.size,
          initialWindow: const ByteRange(0, 32 * 1024 * 1024 - 1),
          options: TransportOptions(maxHttpConnections: n),
        );
        final end = DateTime.now().add(const Duration(seconds: 3));
        while (DateTime.now().isBefore(end)) {
          final seen = (await backend.status(id)).peersOrConnections;
          if (seen > most) most = seen;
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      } finally {
        await backend.stop();
      }
      return most;
    }

    try {
      final capped = await peak(2);
      final auto = await peak(0);
      readbackRow(
        setting: 'streaming.maxHttpConnections (live connections)',
        value: '2 vs Auto',
        sent: 'split / max-connection-per-server',
        readBack: 'peak connections: 2 -> $capped, Auto -> $auto',
        pass: capped <= 2,
      );
      expect(capped, inInclusiveRange(1, 2));
      expect(auto, greaterThan(2), reason: 'control: Auto allows more');
    } finally {
      await slow.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('connection timeout: an unreachable host fails within timeout + 1 s', () async {
    for (final host in ['10.255.255.1', '127.0.0.1']) {
      final port = host == '127.0.0.1' ? 1 : 81;
      final watch = Stopwatch()..start();
      Object? error;
      try {
        await RangeSupportProbe(
          options: const TransportOptions(connectTimeoutSeconds: 2),
        ).probe(_spec(Uri.parse('http://$host:$port/x.bin')));
      } catch (e) {
        error = e;
      }
      watch.stop();
      expect(error, isA<TransportFailure>(), reason: host);
      expect(watch.elapsedMilliseconds, lessThan(3000), reason: host);
      readbackRow(
        setting: 'streaming.connectionTimeout (timing)',
        value: '2 s -> $host:$port',
        sent: 'HttpClient.connectionTimeout',
        readBack:
            '${(error as TransportFailure).code} after ${watch.elapsedMilliseconds} ms',
        pass: true,
      );
    }
  });

  test('TLS: Verify rejects a self-signed origin, Don\'t verify accepts it', () async {
    final key = '${cache.path}/k.pem';
    final crt = '${cache.path}/c.pem';
    final made = await Process.run('openssl', [
      'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', key, //
      '-out', crt, '-days', '1', '-subj', '/CN=localhost',
    ]);
    expect(made.exitCode, 0, reason: '${made.stderr}');
    final context = SecurityContext()
      ..useCertificateChain(crt)
      ..usePrivateKey(key);
    final secure = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    secure.listen((request) async {
      request.response
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..contentLength = 10;
      await request.response.close();
    });
    final uri = Uri.parse('https://127.0.0.1:${secure.port}/m.bin');
    try {
      Object? strict;
      try {
        await RangeSupportProbe().probe(_spec(uri));
      } catch (e) {
        strict = e;
      }
      expect(strict, isA<TransportFailure>());
      final lax = await RangeSupportProbe(
        options: const TransportOptions(verifyTls: false),
      ).probe(_spec(uri));
      expect(lax.supported, isTrue);
      readbackRow(
        setting: 'streaming.tls (self-signed origin)',
        value: "Verify / Don't verify",
        sent: 'HttpClient.badCertificateCallback',
        readBack: 'Verify -> failure, Don\'t verify -> probe ok',
        pass: true,
      );
    } finally {
      await secure.close(force: true);
    }
  });
}
