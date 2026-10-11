import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:ui/ui.dart';

/// What the user pasted, decided by the app so the user never chooses.
enum LinkKind { magnet, torrentFile, torrentUrl, hls, directFile }

/// Input that is not a playable link, or a link that could not be fetched.
/// The message is written for the viewer.
final class PlayLinkFailure extends AppFailure {
  const PlayLinkFailure(String message, {super.cause, super.stack})
    : super(code: 'app.play_link.invalid', message: message);
}

/// Largest .torrent file downloaded from a URL.
const int maxTorrentBytes = 10 * 1024 * 1024;

const Duration _headTimeout = Duration(seconds: 10);
const Duration _fetchTimeout = Duration(seconds: 20);

final RegExp _btih = RegExp(
  r'^urn:btih:([0-9a-f]{40}|[a-z2-7]{32})$',
  caseSensitive: false,
);

/// Classifies [input] (see `planning/part-04-play-link/phase-01` decisions).
/// Only an http(s) link without a telling extension costs one HEAD request.
Future<LinkKind> classifyLink(
  String input, {
  HttpClient Function() clientFactory = HttpClient.new,
  AppStrings? strings,
}) async {
  final s = strings ?? lookupAppStrings(const Locale('en'));
  final text = input.trim();
  final lower = text.toLowerCase();
  if (lower.startsWith('magnet:')) {
    final uri = Uri.tryParse(text);
    final ok =
        uri != null &&
        (uri.queryParametersAll['xt'] ?? const <String>[]).any(_btih.hasMatch);
    if (!ok) {
      throw PlayLinkFailure(s.playlink_badMagnet);
    }
    return LinkKind.magnet;
  }
  final uri = Uri.tryParse(text);
  if (uri != null && (uri.isScheme('http') || uri.isScheme('https'))) {
    if (uri.host.isEmpty) {
      throw PlayLinkFailure(s.playlink_invalid);
    }
    final path = uri.path.toLowerCase();
    if (path.endsWith('.torrent')) return LinkKind.torrentUrl;
    if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return LinkKind.hls;
    return _headKind(uri, clientFactory, s);
  }
  if (lower.endsWith('.torrent') && text.isNotEmpty) {
    if (!File(_filePath(text)).existsSync()) {
      throw PlayLinkFailure(s.playlink_fileMissing(text));
    }
    return LinkKind.torrentFile;
  }
  throw PlayLinkFailure(s.playlink_invalid);
}

String _filePath(String text) {
  final uri = Uri.tryParse(text);
  return uri != null && uri.isScheme('file') ? uri.toFilePath() : text;
}

Future<LinkKind> _headKind(
  Uri uri,
  HttpClient Function() factory,
  AppStrings s,
) async {
  final client = factory();
  try {
    final request = await client.openUrl('HEAD', uri).timeout(_headTimeout);
    final response = await request.close().timeout(_headTimeout);
    await response.drain<void>();
    final type = response.headers.contentType?.mimeType.toLowerCase();
    if (type == 'application/x-bittorrent') return LinkKind.torrentUrl;
    if (type == 'application/vnd.apple.mpegurl' ||
        type == 'application/x-mpegurl') {
      return LinkKind.hls;
    }
    return LinkKind.directFile;
  } on Object catch (error, stack) {
    throw PlayLinkFailure(
      s.playlink_unreachable(uri.host),
      cause: error,
      stack: stack,
    );
  } finally {
    client.close(force: true);
  }
}

/// Turns pasted text into the [SourceSpec] the existing play flow opens.
final class LinkResolver {
  LinkResolver({required this.torrentDir, this.clientFactory = HttpClient.new});

  /// Where .torrent files downloaded from a URL are kept.
  final Directory torrentDir;
  final HttpClient Function() clientFactory;

  Future<SourceSpec> resolve(String input, {AppStrings? strings}) async {
    final text = input.trim();
    final kind = await classifyLink(
      text,
      clientFactory: clientFactory,
      strings: strings,
    );
    switch (kind) {
      case LinkKind.magnet:
        return SourceSpec(kind: SourceKind.torrentMagnet, uri: Uri.parse(text));
      case LinkKind.torrentFile:
        return SourceSpec(
          kind: SourceKind.torrentFile,
          uri: Uri.file(File(_filePath(text)).absolute.path),
        );
      case LinkKind.torrentUrl:
        return SourceSpec(
          kind: SourceKind.torrentFile,
          uri: (await _download(
            Uri.parse(text),
            strings ?? lookupAppStrings(const Locale('en')),
          )).uri,
        );
      case LinkKind.hls:
        return SourceSpec(kind: SourceKind.hlsUrl, uri: Uri.parse(text));
      case LinkKind.directFile:
        return SourceSpec(kind: SourceKind.httpUrl, uri: Uri.parse(text));
    }
  }

  Future<File> _download(Uri url, AppStrings s) async {
    final client = clientFactory();
    try {
      final request = await client.getUrl(url).timeout(_fetchTimeout);
      final response = await request.close().timeout(_fetchTimeout);
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw PlayLinkFailure(
          s.playlink_httpStatus(response.statusCode.toString()),
        );
      }
      if (response.contentLength > maxTorrentBytes) {
        await response.drain<void>();
        throw PlayLinkFailure(s.playlink_tooLarge);
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(_fetchTimeout)) {
        bytes.add(chunk);
        if (bytes.length > maxTorrentBytes) {
          throw PlayLinkFailure(s.playlink_tooLarge);
        }
      }
      final data = bytes.takeBytes();
      // A bencoded torrent is a dictionary: it starts with `d`.
      if (data.isEmpty || data.first != 0x64) {
        throw PlayLinkFailure(s.playlink_notTorrent);
      }
      await torrentDir.create(recursive: true);
      // Stable per URL so a replay finds its resume data.
      final file = File('${torrentDir.path}/${_fnv1a(url.toString())}.torrent');
      return await file.writeAsBytes(data, flush: true);
    } on PlayLinkFailure {
      rethrow;
    } on Object catch (error, stack) {
      throw PlayLinkFailure(
        s.playlink_downloadFailed(url.host),
        cause: error,
        stack: stack,
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// A readable name for the Recent list: a magnet's `dn`, else the file name
/// in the URL path or local path; null when there is none.
String? linkTitle(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text);
  if (text.toLowerCase().startsWith('magnet:')) {
    final name = uri?.queryParameters['dn'];
    return name == null || name.isEmpty ? null : name;
  }
  final segments =
      uri != null && (uri.isScheme('http') || uri.isScheme('https'))
      ? uri.pathSegments
      : text.split(RegExp(r'[/\\]'));
  return segments.where((s) => s.isNotEmpty).lastOrNull;
}

/// `info.name` of a .torrent file's bytes; null when they are not a
/// well-formed torrent or carry no name.
String? torrentName(Uint8List bytes) {
  var pos = 0;
  Object parse() {
    if (pos >= bytes.length) throw const FormatException('truncated');
    final c = bytes[pos];
    if (c == 0x69) {
      // i<digits>e
      final end = bytes.indexOf(0x65, pos);
      if (end < 0) throw const FormatException('bad int');
      final n = int.parse(String.fromCharCodes(bytes, pos + 1, end));
      pos = end + 1;
      return n;
    }
    if (c == 0x6c || c == 0x64) {
      pos++;
      final items = <Object>[];
      while (pos < bytes.length && bytes[pos] != 0x65) {
        items.add(parse());
      }
      if (pos >= bytes.length) throw const FormatException('truncated');
      pos++;
      if (c == 0x6c) return items;
      return {
        for (var i = 0; i + 1 < items.length; i += 2)
          if (items[i] is Uint8List)
            utf8.decode(items[i] as Uint8List, allowMalformed: true):
                items[i + 1],
      };
    }
    final colon = bytes.indexOf(0x3a, pos);
    if (colon < 0) throw const FormatException('bad string');
    final length = int.parse(String.fromCharCodes(bytes, pos, colon));
    final end = colon + 1 + length;
    if (length < 0 || end > bytes.length) {
      throw const FormatException('truncated');
    }
    pos = end;
    return Uint8List.sublistView(bytes, colon + 1, end);
  }

  try {
    final root = parse();
    final info = root is Map ? root['info'] : null;
    final name = info is Map ? info['name'] : null;
    if (name is! Uint8List) return null;
    final text = utf8.decode(name, allowMalformed: true).trim();
    return text.isEmpty ? null : text;
  } on FormatException {
    return null;
  }
}

/// Resolves [link] and records it in [recents]. [title] is the name to show
/// (a title's own name when the link plays as that title); without it the
/// torrent's or link's name is used. Throws [PlayLinkFailure] for bad input.
Future<({SourceSpec spec, String? title})> prepareLink(
  String link, {
  required LinkResolver resolver,
  required RecentLinks recents,
  required AppLogger logger,
  String? title,
  AppStrings? strings,
}) async {
  final spec = await resolver.resolve(link, strings: strings);
  var name = title ?? linkTitle(link);
  if (title == null && spec.kind == SourceKind.torrentFile) {
    try {
      name = torrentName(await File.fromUri(spec.uri).readAsBytes()) ?? name;
    } on FileSystemException catch (error, stack) {
      logger.warn(
        'play-link: could not read torrent for its name',
        error: error,
        stack: stack,
      );
    }
  }
  await recents.add(link, kind: spec.kind.name, title: name);
  return (spec: spec, title: name);
}

/// The "Import .torrent" picker: the chosen file's path, null if cancelled.
Future<String?> pickTorrentFile({String? label}) async {
  final torrents = XTypeGroup(
    label: label ?? lookupAppStrings(const Locale('en')).play_torrent,
    extensions: <String>['torrent'],
  );
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[torrents]);
  return file?.path;
}

String _fnv1a(String text) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(text)) {
    hash = (hash ^ byte) * 0x100000001b3;
  }
  return hash.toUnsigned(64).toRadixString(16);
}
