import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// [NetworkImage] with the backup-proxy routing (direct first, the proxy
/// after 3 s without headers; BACKUP_PROXY.md). Artwork is JSON/image
/// traffic the proxy forwards; it is never media.
@immutable
class RoutedNetworkImage extends ImageProvider<RoutedNetworkImage> {
  const RoutedNetworkImage(this.url, {this.scale = 1});

  final String url;
  final double scale;

  static HttpClient _newClient() =>
      HttpClient()..connectionTimeout = const Duration(seconds: 30);
  static HttpClient _client = _newClient();
  static final BackupRouter _router = BackupRouter();

  @override
  Future<RoutedNetworkImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<RoutedNetworkImage>(this);

  @override
  ImageStreamCompleter loadImage(
    RoutedNetworkImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: scale,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final HttpClientResponse response;
    try {
      response = await _router.send(_client, 'GET', Uri.parse(url), const {});
    } on Object {
      // After a network drop the pooled keep-alive sockets are dead and every
      // later image fails on them; start the next request from a fresh pool
      // (same recovery as ProviderHttp).
      _client.close();
      _client = _newClient();
      rethrow;
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: Uri.parse(url),
      );
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    if (bytes.isEmpty) {
      throw StateError('Empty artwork response: $url');
    }
    return decode(
      await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes)),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RoutedNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'RoutedNetworkImage("$url", scale: $scale)';
}
