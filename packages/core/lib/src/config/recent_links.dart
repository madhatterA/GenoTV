import 'dart:convert';

import 'settings_store.dart';

/// One replayable link on the Play link page.
class RecentLink {
  const RecentLink({
    required this.link,
    required this.kind,
    required this.addedAt,
    this.title,
  });

  factory RecentLink.fromJson(Map<String, dynamic> json) => RecentLink(
    link: json['link'] as String,
    kind: json['kind'] as String,
    addedAt: DateTime.fromMillisecondsSinceEpoch(json['addedAt'] as int),
    title: json['title'] as String?,
  );

  /// What the user pasted, or the local .torrent path.
  final String link;

  /// The detected link kind's name (app-owned enum, kept as text here).
  final String kind;
  final DateTime addedAt;
  final String? title;

  /// Title if known, else the link itself.
  String get label => title ?? link;

  Map<String, Object?> toJson() => {
    'link': link,
    'kind': kind,
    'addedAt': addedAt.millisecondsSinceEpoch,
    'title': ?title,
  };
}

/// The last [maxEntries] links played, newest first, kept in the settings
/// store so they survive restarts.
class RecentLinks {
  RecentLinks(this._store, {this._clock = DateTime.now});

  static const int maxEntries = 10;
  static const String _key = 'playLink.recent';

  final SettingsStore _store;
  final DateTime Function() _clock;

  /// Newest first. Unreadable stored data is treated as empty.
  List<RecentLink> get entries {
    final raw = _store.read(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final e in jsonDecode(raw) as List<dynamic>)
          RecentLink.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      // A corrupt list must not block the page; the next write replaces it.
      return const [];
    }
  }

  /// Puts [link] first. A repeat of the same link moves to the top and keeps
  /// its known title unless a new [title] is given.
  Future<void> add(String link, {required String kind, String? title}) {
    final current = entries;
    final previous = current.where((e) => e.link == link).firstOrNull;
    return _save(
      [
        RecentLink(
          link: link,
          kind: kind,
          addedAt: _clock(),
          title: title ?? previous?.title,
        ),
        ...current.where((e) => e.link != link),
      ].take(maxEntries).toList(),
    );
  }

  Future<void> remove(String link) =>
      _save(entries.where((e) => e.link != link).toList());

  Future<void> clear() => _store.delete(_key);

  Future<void> _save(List<RecentLink> list) =>
      _store.write(_key, jsonEncode([for (final e in list) e.toJson()]));
}
