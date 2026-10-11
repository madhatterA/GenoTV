import 'package:flutter/widgets.dart' show Locale;
import 'package:ui/ui.dart' show AppStrings, lookupAppStrings;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cast/dart_cast.dart' show decodeSubtitleBytes;
import 'package:file_selector/file_selector.dart';

/// Subtitle file extensions the player accepts, lower case, no dot.
const subtitleExtensions = <String>['srt', 'ass', 'ssa', 'vtt', 'sub'];

const _maxEntryBytes = 5 * 1024 * 1024;
const _maxTotalBytes = 20 * 1024 * 1024;
const _maxZipBytes = 20 * 1024 * 1024;

/// A user-facing import failure (bad zip, nothing usable inside, unreadable).
class SubtitleImportException implements Exception {
  const SubtitleImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One subtitle file found in a picked file or zip: its display name and bytes.
typedef SubtitleEntry = ({String name, Uint8List bytes});

bool _isSubtitleName(String name) {
  final dot = name.lastIndexOf('.');
  return dot >= 0 &&
      subtitleExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Every subtitle entry of the zip in [zip] (stored or deflate); other entries
/// are ignored. Absolute or `..` names, encrypted entries, oversized data and
/// archives without a subtitle throw [SubtitleImportException].
List<SubtitleEntry> readSubtitleZip(Uint8List zip, {AppStrings? strings}) {
  final s = strings ?? lookupAppStrings(const Locale('en'));
  final data = ByteData.sublistView(zip);
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 22 - 0xFFFF; i--) {
    if (data.getUint32(i, Endian.little) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw SubtitleImportException(s.subtitle_invalidZip);
  final count = data.getUint16(eocd + 10, Endian.little);
  var pos = data.getUint32(eocd + 16, Endian.little);
  final found = <SubtitleEntry>[];
  var total = 0;
  try {
    for (var n = 0; n < count; n++) {
      if (data.getUint32(pos, Endian.little) != 0x02014b50) {
        throw SubtitleImportException(s.subtitle_damagedDirectory);
      }
      final flags = data.getUint16(pos + 8, Endian.little);
      final method = data.getUint16(pos + 10, Endian.little);
      final compSize = data.getUint32(pos + 20, Endian.little);
      final size = data.getUint32(pos + 24, Endian.little);
      final nameLen = data.getUint16(pos + 28, Endian.little);
      final extraLen = data.getUint16(pos + 30, Endian.little);
      final commentLen = data.getUint16(pos + 32, Endian.little);
      final local = data.getUint32(pos + 42, Endian.little);
      final raw = Uint8List.sublistView(zip, pos + 46, pos + 46 + nameLen);
      final name = (flags & 0x800) != 0
          ? utf8.decode(raw, allowMalformed: true)
          : latin1.decode(raw);
      pos += 46 + nameLen + extraLen + commentLen;

      final path = name.replaceAll('\\', '/');
      if (path.startsWith('/') ||
          RegExp(r'^[A-Za-z]:').hasMatch(path) ||
          path.split('/').contains('..')) {
        throw SubtitleImportException(s.subtitle_unsafeName(name));
      }
      if (path.endsWith('/') || !_isSubtitleName(path)) continue;
      if ((flags & 1) != 0) {
        throw SubtitleImportException(s.subtitle_encrypted(name));
      }
      if (size > _maxEntryBytes || total + size > _maxTotalBytes) {
        throw SubtitleImportException(s.subtitle_entryTooLarge(name));
      }
      final start =
          local +
          30 +
          data.getUint16(local + 26, Endian.little) +
          data.getUint16(local + 28, Endian.little);
      final packed = Uint8List.sublistView(zip, start, start + compSize);
      final bytes = switch (method) {
        0 => packed,
        8 => _inflate(packed, name, s),
        _ => throw SubtitleImportException(
          s.subtitle_unsupportedCompression(name),
        ),
      };
      if (bytes.length != size) {
        throw SubtitleImportException(s.subtitle_damagedEntry(name));
      }
      total += size;
      found.add((name: path.split('/').last, bytes: bytes));
    }
  } on RangeError {
    throw SubtitleImportException(s.subtitle_damagedZip);
  }
  if (found.isEmpty) {
    throw SubtitleImportException(s.subtitle_emptyZip);
  }
  return found;
}

Uint8List _inflate(Uint8List packed, String name, AppStrings s) {
  final out = BytesBuilder(copy: false);
  final input = ZLibDecoder(raw: true)
      .startChunkedConversion(_CappedSink(out, name, s));
  try {
    input.add(packed);
    input.close();
  } on FormatException {
    throw SubtitleImportException(s.subtitle_damagedEntry(name));
  } on FileSystemException {
    throw SubtitleImportException(s.subtitle_damagedEntry(name));
  }
  return out.takeBytes();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._out, this._name, this._strings);
  final BytesBuilder _out;
  final String _name;
  final AppStrings _strings;
  @override
  void add(List<int> chunk) {
    _out.add(chunk);
    if (_out.length > _maxEntryBytes) {
      throw SubtitleImportException(_strings.subtitle_entryTooLarge(_name));
    }
  }

  @override
  void close() {}
}

/// Reads [path] as a subtitle file or a zip of subtitles.
Future<List<SubtitleEntry>> readSubtitleSource(
  String path, {
  AppStrings? strings,
}) async {
  final s = strings ?? lookupAppStrings(const Locale('en'));
  final name = path.split(RegExp(r'[\\/]')).last;
  final lower = name.toLowerCase();
  final isZip = lower.endsWith('.zip');
  if (!isZip && !_isSubtitleName(lower)) {
    throw SubtitleImportException(s.subtitle_unsupportedType(name));
  }
  final Uint8List bytes;
  try {
    final file = File(path);
    if (await file.length() > _maxZipBytes) {
      throw SubtitleImportException(s.subtitle_fileTooLarge(name));
    }
    bytes = await file.readAsBytes();
  } on FileSystemException catch (error) {
    throw SubtitleImportException(s.subtitle_readFailed(name, error.message));
  }
  return isZip
      ? readSubtitleZip(bytes, strings: s)
      : [(name: name, bytes: bytes)];
}

/// Writes each entry, decoded to UTF-8 text, into a fresh temp directory and
/// returns a file URI per entry for the player's external-subtitle path.
Future<List<({String name, Uri uri})>> stageSubtitles(
  List<SubtitleEntry> entries,
) async {
  final dir = await Directory.systemTemp.createTemp('subtitles_');
  final staged = <({String name, Uri uri})>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final file = File('${dir.path}${Platform.pathSeparator}$i-${entry.name}');
    await file.writeAsString(decodeSubtitleBytes(entry.bytes));
    staged.add((name: entry.name, uri: file.uri));
  }
  return staged;
}

/// The "Add subtitle file…" picker: subtitle or zip chosen by the viewer,
/// staged for the player; empty when cancelled.
Future<List<({String name, Uri uri})>> pickSubtitleFiles({
  AppStrings? strings,
}) async {
  final s = strings ?? lookupAppStrings(const Locale('en'));
  final group = XTypeGroup(
    label: s.subtitle_picker,
    extensions: <String>[...subtitleExtensions, 'zip'],
    // iOS rejects groups without a UTI; the extension is re-checked on read.
    uniformTypeIdentifiers: <String>['public.data'],
  );
  final file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
  if (file == null) return const [];
  return stageSubtitles(await readSubtitleSource(file.path, strings: s));
}
