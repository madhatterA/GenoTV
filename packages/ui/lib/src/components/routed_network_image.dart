import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:crypto/crypto.dart';
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

  /// Largest size the on-disk copy of the pictures may reach.
  static const int diskCacheMaxBytes = 200 * 1024 * 1024;

  static Directory? _disk;
  static AppLogger? _log;

  /// Keeps every downloaded picture as a file in [directory] (the app's
  /// cache directory) so scrolling back, or the next launch, never fetches it
  /// again. The oldest files (by modified time) go first once the folder
  /// passes [diskCacheMaxBytes]. Null turns the disk copy off.
  static Future<void> useDiskCache(Directory? directory, {AppLogger? logger}) {
    _disk = directory;
    _log = logger;
    return directory == null ? Future<void>.value() : _prune(directory);
  }

  static File? _fileFor(String url) => _disk == null
      ? null
      : File('${_disk!.path}/${sha1.convert(url.codeUnits)}');

  static Future<void> _prune(Directory dir) async {
    try {
      final files = <(File, FileStat)>[];
      var total = 0;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final stat = await e.stat();
        files.add((e, stat));
        total += stat.size;
      }
      files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
      for (final (file, stat) in files) {
        if (total <= diskCacheMaxBytes) break;
        await file.delete();
        total -= stat.size;
      }
    } on Object catch (error, stack) {
      _log?.warn('Artwork disk cache prune failed', error: error, stack: stack);
    }
  }

  static Future<Uint8List?> _readDisk(String url) async {
    final file = _fileFor(url);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.setLastModified(DateTime.now());
      return bytes.isEmpty ? null : bytes;
    } on Object catch (error, stack) {
      _log?.warn('Artwork disk read failed: $url', error: error, stack: stack);
      return null;
    }
  }

  static Future<void> _writeDisk(String url, Uint8List bytes) async {
    final file = _fileFor(url);
    if (file == null) return;
    try {
      final temp = File('${file.path}.tmp');
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
    } on Object catch (error, stack) {
      _log?.warn('Artwork disk write failed: $url', error: error, stack: stack);
    }
  }

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

  /// Longest one try (headers and body) may take, and how many tries a picture gets.
  @visibleForTesting
  static Duration fetchTimeout = const Duration(seconds: 20);
  static const int fetchAttempts = 3;

  Future<List<int>> _fetch(HttpClient client) async {
    final response = await _router.send(
      client,
      'GET',
      Uri.parse(url),
      const {},
    );
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw NetworkImageLoadException(
        statusCode: response.statusCode,
        uri: Uri.parse(url),
      );
    }
    return consolidateHttpClientResponseBytes(response);
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final cached = await _readDisk(url);
    if (cached != null) {
      return decode(await ui.ImmutableBuffer.fromUint8List(cached));
    }
    // A socket that dies mid-response (tvOS drops idle pooled sockets) never
    // completes the body future, which left the picture loading forever: bound
    // each try, retry on a fresh pool, then fail so the error widget shows.
    List<int>? bytes;
    for (var attempt = 1; bytes == null; attempt++) {
      final used = _client;
      try {
        bytes = await _fetch(used).timeout(fetchTimeout);
      } on NetworkImageLoadException {
        rethrow;
      } on Object {
        // Also the recovery after a network drop: dead keep-alive sockets
        // would fail every later image (same as ProviderHttp). Only the pool
        // this try used is replaced: a load that failed because another one
        // already closed it must not close the fresh pool again (that made
        // every concurrent picture fail in turn: "Client is closed").
        if (identical(_client, used)) {
          used.close(force: true);
          _client = _newClient();
        }
        if (attempt >= fetchAttempts) rethrow;
      }
    }
    if (bytes.isEmpty) {
      throw StateError('Empty artwork response: $url');
    }
    final data = Uint8List.fromList(bytes);
    unawaited(_writeDisk(url, data));
    return decode(await ui.ImmutableBuffer.fromUint8List(data));
  }

  @override
  bool operator ==(Object other) =>
      other is RoutedNetworkImage && other.url == url && other.scale == scale;

  @override
  int get hashCode => Object.hash(url, scale);

  @override
  String toString() => 'RoutedNetworkImage("$url", scale: $scale)';
}
