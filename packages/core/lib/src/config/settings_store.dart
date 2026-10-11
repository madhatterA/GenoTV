import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';

/// Tiny key-value storage interface behind [AppSettings]' typed accessors.
abstract interface class SettingsStore {
  /// Loads persisted values into memory. Call once before the first [read].
  Future<void> load();

  String? read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// In-memory [SettingsStore] for tests. Nothing persists across instances.
class MemorySettingsStore implements SettingsStore {
  final Map<String, String> _values = {};

  @override
  Future<void> load() async {}

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Persists settings as one JSON file under `AppPaths.support`. Writes are
/// debounced so rapid changes (e.g. a volume slider) don't thrash the disk;
/// call [dispose] to flush any pending write immediately.
class JsonSettingsStore implements SettingsStore {
  JsonSettingsStore({
    required this.file,
    required AppLogger logger,
    this.debounce = const Duration(milliseconds: 500),
  }) : _logger = logger.scoped('core.settings');

  final File file;
  final AppLogger _logger;
  final Duration debounce;
  final Map<String, String> _values = {};
  Timer? _flushTimer;
  bool _dirty = false;

  @override
  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _values
        ..clear()
        ..addAll(decoded.map((key, value) => MapEntry(key, value as String)));
    } catch (e, stack) {
      _logger.error('Failed to load settings from ${file.path}; starting empty',
          error: e, stack: stack);
    }
  }

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    _scheduleFlush();
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    _dirty = true;
    _flushTimer?.cancel();
    _flushTimer = Timer(debounce, _flush);
  }

  Future<void> _flush() async {
    if (!_dirty) return;
    _dirty = false;
    await file.writeAsString(jsonEncode(_values));
  }

  /// Flushes any pending debounced write. Safe to call twice.
  Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
  }
}
