import 'dart:convert';

import '../config/settings_store.dart';

/// Parses what a user typed as a service domain: `host`, `host:port`,
/// `http(s)://host[:port][/path]`. No scheme means https. Null when it is not
/// an http(s) URL with a host.
Uri? parseDomainInput(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      !RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$')
          .hasMatch(uri.host) ||
      text.contains(' ') ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri.replace(
    path: uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path,
  );
}

/// [url] with its [builtIn] base (scheme://host[:port][/path]) replaced by
/// [override]; every path after the base, and the query, stay. Without an
/// override [url] is returned unchanged.
Uri rebase(Uri url, Uri builtIn, Uri? override) {
  if (override == null) return url;
  final rest = url.path.startsWith(builtIn.path)
      ? url.path.substring(builtIn.path.length)
      : url.path;
  return url.replace(
    scheme: override.scheme,
    host: override.host,
    port: override.hasPort ? override.port : null,
    path: '${override.path}$rest',
  );
}

/// One entry of Settings > Title API.
class TitleApiEntry {
  const TitleApiEntry(this.id, this.builtIn, this.override);
  final String id;
  final Uri builtIn;
  final Uri? override;
  Uri get current => override ?? builtIn;
}

/// User-editable domains (phase 14): the Title API list (order + domains) and
/// each provider's own domain. Two separate stores of values: a service that
/// appears in both never shares one. Persisted in the settings store as
/// `titleApi.entries` and `providers.<id>.baseUrl`; empty means built-in.
class DomainSettings {
  DomainSettings(this._store, {required Map<String, Uri> titleDefaults})
    : _titleDefaults = titleDefaults;

  final SettingsStore _store;
  final Map<String, Uri> _titleDefaults;
  final _listeners = <void Function()>[];

  void addListener(void Function() listener) => _listeners.add(listener);
  void _notify() {
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  Uri? provider(String id) {
    final raw = _store.read('providers.$id.baseUrl');
    return raw == null || raw.isEmpty ? null : Uri.tryParse(raw);
  }

  /// Saves [raw] (null or empty = back to built-in). Throws [FormatException]
  /// for invalid input and keeps the old value.
  Future<void> setProvider(String id, String? raw) async {
    final key = 'providers.$id.baseUrl';
    if (raw == null || raw.trim().isEmpty) {
      await _store.delete(key);
    } else {
      final uri = parseDomainInput(raw);
      if (uri == null) throw FormatException('invalid domain', raw);
      await _store.write(key, uri.toString());
    }
    _notify();
  }

  /// Entries in the user's order (new built-in ids are appended).
  List<TitleApiEntry> titleApi() {
    Map<String, dynamic> saved = {};
    List<String> order = [];
    final raw = _store.read('titleApi.entries');
    if (raw != null && raw.isNotEmpty) {
      try {
        for (final e in jsonDecode(raw) as List<dynamic>) {
          final m = e as Map<String, dynamic>;
          final id = m['id'] as String;
          if (_titleDefaults.containsKey(id) && !order.contains(id)) {
            order.add(id);
            saved[id] = m['baseUrl'];
          }
        }
      } on Object {
        order = [];
        saved = {};
      }
    }
    order.addAll(_titleDefaults.keys.where((id) => !order.contains(id)));
    return [
      for (final id in order)
        TitleApiEntry(
          id,
          _titleDefaults[id]!,
          (saved[id] as String?)?.isNotEmpty == true
              ? Uri.tryParse(saved[id] as String)
              : null,
        ),
    ];
  }

  Uri? titleOverride(String id) =>
      titleApi().firstWhere((e) => e.id == id).override;

  List<String> get titleOrder => [for (final e in titleApi()) e.id];

  Future<void> _saveTitle(List<TitleApiEntry> entries) async {
    await _store.write(
      'titleApi.entries',
      jsonEncode([
        for (final e in entries)
          {'id': e.id, 'baseUrl': e.override?.toString() ?? ''},
      ]),
    );
    _notify();
  }

  Future<void> reorderTitle(int from, int to) async {
    final entries = titleApi();
    entries.insert(to, entries.removeAt(from));
    await _saveTitle(entries);
  }

  /// [raw] null or empty restores the entry's built-in domain.
  Future<void> setTitleDomain(String id, String? raw) async {
    Uri? uri;
    if (raw != null && raw.trim().isNotEmpty) {
      uri = parseDomainInput(raw);
      if (uri == null) throw FormatException('invalid domain', raw);
    }
    await _saveTitle([
      for (final e in titleApi())
        e.id == id ? TitleApiEntry(e.id, e.builtIn, uri) : e,
    ]);
  }

  /// Built-in order and domains.
  Future<void> resetTitle() async {
    await _store.delete('titleApi.entries');
    _notify();
  }
}
