import 'dart:async';

import '../logging/app_logger.dart';
import '../logging/console_logger.dart';
import 'settings_schema.dart';
import 'settings_store.dart';

/// Typed read/write of [SettingDef] values over a [SettingsStore], keyed by
/// [SettingDef.id]. Values are stored as strings: `true`/`false`, a number,
/// a choice, comma-joined list elements, or free text.
class SettingsValues {
  SettingsValues(this._store, {AppLogger? logger})
    : _logger = (logger ?? ConsoleLogger()).scoped('core.settings');

  final SettingsStore _store;
  final AppLogger _logger;
  final StreamController<SettingDef> _changes = StreamController.broadcast();

  /// Emits the definition after every [write] or [reset].
  Stream<SettingDef> get changes => _changes.stream;

  /// The current value as `bool` (toggle), `double` (number),
  /// `List<String>` (list) or `String` (choice, text, path). An unset or
  /// unparsable stored value yields the default; unparsable is logged.
  T read<T>(SettingDef def) {
    _requireValue(def);
    final stored = _store.read(def.id);
    Object? value;
    if (stored != null) {
      value = _parse(def, stored);
      if (value == null) {
        _logger.warn(
          'Ignoring invalid stored value "$stored" for ${def.id}; using default',
        );
      }
    }
    value ??= _parse(def, def.defaultValue);
    if (value is! T) {
      throw ArgumentError('${def.id} is a ${def.kind.name}, not $T');
    }
    return value;
  }

  /// Stores [value] (`bool`, `num`, `List<String>` or `String` matching the
  /// kind); throws [ArgumentError] when it is not valid for [def].
  ///
  /// Validation throws synchronously, before anything is stored.
  /// Validate the priority field before saving; invalid edits leave existing rules intact.
  String? validatePriority(String value) {
    final error = trackPriorityError(value);
    if (error != null) _logger.warn(error);
    return error;
  }

  Future<void> write(SettingDef def, Object value) {
    _requireValue(def);
    if (def.id == 'languages.trackPriority' && value is String) {
      final error = validatePriority(value);
      if (error != null) {
        throw ArgumentError(error);
      }
    }
    final encoded = _encode(def, value);
    return _store.write(def.id, encoded).then((_) => _changes.add(def));
  }

  /// Removes the stored value so [read] returns the default again.
  Future<void> reset(SettingDef def) async {
    _requireValue(def);
    await _store.delete(def.id);
    _changes.add(def);
  }

  void dispose() => _changes.close();

  static void _requireValue(SettingDef def) {
    if (def.kind == SettingKind.page) {
      throw ArgumentError.value(def.id, 'def', 'is a page and holds no value');
    }
  }

  static Object? _parse(SettingDef def, String s) => switch (def.kind) {
    SettingKind.toggle => s == 'true' ? true : (s == 'false' ? false : null),
    SettingKind.number => _inRange(def, double.tryParse(s)),
    SettingKind.choice => _validChoice(def, s) ? s : null,
    SettingKind.list => _parseList(def, s),
    SettingKind.text || SettingKind.path => s,
    SettingKind.page => null,
  };

  static double? _inRange(SettingDef def, double? v) =>
      v == null ||
          (def.min != null && v < def.min!) ||
          (def.max != null && v > def.max!)
      ? null
      : v;

  /// A choice with no fixed [SettingDef.choices] (the hardware decoder
  /// device) takes its options from the platform, so any string is valid.
  static bool _validChoice(SettingDef def, String s) {
    if (def.id == 'display.refreshRate') {
      final rate = double.tryParse(s);
      return s == 'auto' || rate != null && rate.isFinite && rate > 0;
    }
    return def.choices.isEmpty ||
        s == def.defaultValue ||
        def.choices.contains(s);
  }

  static List<String>? _parseList(SettingDef def, String s) {
    final items = s.isEmpty ? <String>[] : s.split(',');
    return items.every(def.choices.contains) ? items : null;
  }

  static String _encode(SettingDef def, Object value) {
    final encoded = switch ((def.kind, value)) {
      (SettingKind.toggle, final bool v) => v.toString(),
      (SettingKind.number, final num v) when v.isFinite => v.toString(),
      (SettingKind.list, final List<String> v) => v.join(','),
      (
        SettingKind.choice || SettingKind.text || SettingKind.path,
        final String v,
      ) =>
        v,
      _ => throw ArgumentError.value(
        value,
        'value',
        'wrong type for ${def.id} (${def.kind.name})',
      ),
    };
    if (_parse(def, encoded) == null) {
      throw ArgumentError.value(value, 'value', 'not valid for ${def.id}');
    }
    return encoded;
  }
}
