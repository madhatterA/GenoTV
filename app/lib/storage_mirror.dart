import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:persistence/persistence.dart';
import 'package:platform_services/platform_services.dart';

/// tvOS only. tvOS lets an app write just to Caches/tmp, which the OS may purge, and keeps 500 KB
/// of persistent storage in NSUserDefaults (Apple, App Programming Guide for tvOS). The settings,
/// provider sessions (every `*.json` in the support folder) and the small DB tables (progress,
/// favourites, next-up) are mirrored there, and put back when a purge removed them.
final class StorageMirror {
  StorageMirror({
    required this.channel,
    required this.logger,
    this.capBytes = defaultCapBytes,
  });

  /// 500 KB documented; the margin is for everything else the app keeps in NSUserDefaults.
  static const defaultCapBytes = 400 * 1000;

  final PlatformChannel channel;
  final AppLogger logger;
  final int capBytes;
  Timer? _timer;
  Map<String, String> _written = {};

  Future<Map<String, String>> _read() async {
    final raw = (await channel.invoke(PlatformMethods.storageMirrorRead)) as Map?;
    final entries = raw?['entries'] as Map? ?? const {};
    return {for (final e in entries.entries) '${e.key}': '${e.value}'};
  }

  /// Puts back every mirrored file that is missing from [support].
  Future<void> restoreFiles(Directory support) async {
    final entries = await _read();
    _written = entries;
    for (final e in entries.entries.where((e) => e.key.startsWith('file:'))) {
      final file = File('${support.path}${Platform.pathSeparator}${e.key.substring(5)}');
      if (!file.existsSync()) {
        await file.writeAsString(e.value, flush: true);
        logger.info('storage mirror: restored ${e.key}');
      }
    }
  }

  /// Fills a freshly created database from the mirror.
  Future<void> restoreDb(Object database) async {
    final json = _written['db'];
    if (json == null) return;
    await importMirror(database as dynamic, json);
    logger.info('storage mirror: restored database tables');
  }

  Future<void> snapshot(Directory support, Object database) async {
    final entries = <String, String>{};
    for (final f in support.listSync().whereType<File>().where((f) => f.path.endsWith('.json'))) {
      entries['file:${f.uri.pathSegments.last}'] = await f.readAsString();
    }
    entries['db'] = await exportMirror(database as dynamic);
    final bytes = entries.entries.fold<int>(0, (n, e) => n + utf8.encode(e.key).length + utf8.encode(e.value).length);
    if (bytes > capBytes) {
      final message = 'storage mirror: $bytes bytes exceeds the $capBytes cap; mirror not updated';
      logger.error(message, error: StateError(message));
      return;
    }
    if (mapEquals(entries, _written)) return;
    await channel.invoke(PlatformMethods.storageMirrorWrite, {'entries': entries});
    _written = entries;
  }

  void start(Directory support, Object database, {Duration every = const Duration(seconds: 20)}) {
    _timer = Timer.periodic(every, (_) async {
      try {
        await snapshot(support, database);
      } on Object catch (error, stack) {
        logger.error('storage mirror snapshot failed', error: error, stack: stack);
      }
    });
  }

  Future<void> stop(Directory support, Object database) async {
    _timer?.cancel();
    await snapshot(support, database);
  }
}

bool mapEquals(Map<String, String> a, Map<String, String> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
