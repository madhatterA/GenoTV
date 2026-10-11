import 'dart:io';

import 'package:contracts/contracts.dart';

import 'http_options.dart';

class RangeProbeResult {
  const RangeProbeResult({
    required this.uri,
    required this.totalBytes,
    required this.validator,
    required this.supported,
  });
  final Uri uri;
  final int? totalBytes;
  final String? validator;
  final bool supported;
}

class RangeSupportProbe {
  RangeSupportProbe({
    HttpClient? client,
    this.options = const TransportOptions(),
  }) : _client = client ?? HttpClient();
  final HttpClient _client;
  final TransportOptions options;

  Future<RangeProbeResult> probe(SourceSpec spec) async {
    try {
      configureOriginClient(_client, options);
      return await _probe(spec);
    } finally {
      _client.close(force: true);
    }
  }

  Future<RangeProbeResult> _probe(SourceSpec spec) async {
    late HttpClientRequest head;
    try {
      head = await _client.headUrl(spec.uri);
    } catch (error, stack) {
      throw TransportFailure.httpUnreachable(cause: error, stack: stack);
    }
    originHeaders(spec, options).forEach(head.headers.add);
    late HttpClientResponse response;
    try {
      response = await head.close();
    } catch (error, stack) {
      throw TransportFailure.httpUnreachable(cause: error, stack: stack);
    }
    final total = int.tryParse(
      response.headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    final validator =
        response.headers.value('etag') ??
        response.headers.value('last-modified');
    final finalUri = response.redirects.fold<Uri>(
      spec.uri,
      (base, redirect) => base.resolveUri(redirect.location),
    );
    if (response.statusCode >= 200 &&
        response.statusCode < 400 &&
        response.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase() ==
            'bytes') {
      await response.drain<void>();
      return RangeProbeResult(
        uri: finalUri,
        totalBytes: total,
        validator: validator,
        supported: true,
      );
    }
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw TransportFailure.httpUnreachable(
        cause: 'origin HEAD returned ${response.statusCode}',
      );
    }
    await response.drain<void>();
    late HttpClientResponse ranged;
    try {
      final request = await _client.getUrl(finalUri);
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      originHeaders(spec, options).forEach(request.headers.add);
      ranged = await request.close();
    } catch (error, stack) {
      throw TransportFailure.httpUnreachable(cause: error, stack: stack);
    }
    if (ranged.statusCode >= 400) {
      await ranged.drain<void>();
      throw TransportFailure.httpUnreachable(
        cause: 'ranged probe returned ${ranged.statusCode}',
      );
    }
    final supported = ranged.statusCode == HttpStatus.partialContent;
    final rangedTotal = int.tryParse(
      (ranged.headers.value('content-range') ?? '').split('/').last,
    );
    final rangedValidator =
        ranged.headers.value('etag') ?? ranged.headers.value('last-modified');
    try {
      await ranged.drain<void>();
    } catch (error, stack) {
      // A server that closes a ranged response before Content-Length is
      // satisfied is an unreachable source, not an untyped probe exception.
      throw TransportFailure.httpUnreachable(cause: error, stack: stack);
    }
    if (!supported) {
      throw const TransportFailure.httpNoRangeSupport(
        cause: 'probe returned no 206',
      );
    }
    return RangeProbeResult(
      uri: finalUri,
      totalBytes: rangedTotal ?? total,
      validator: rangedValidator ?? validator,
      supported: true,
    );
  }
}
