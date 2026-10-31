import 'dart:async';

import 'package:contracts/contracts.dart';

import 'content_source_failure.dart';

/// Title source with fallback (Part 06): [sources] in priority order (TMDB,
/// MovieJavan, CCloud). A call goes to the active source; a timeout or network
/// failure moves on to the next one. While degraded, the first source is probed
/// in the background every [recheck] and becomes active again as soon as it
/// answers, so screens never wait on it. A "not found" is an answer, not a
/// cutoff, and is passed on unchanged. TMDB direct vs. proxy is already tried
/// inside the HTTP layer, so one TMDB failure here means both paths failed.
class FallbackCatalogue implements SourceProvider {
  FallbackCatalogue({
    required this.sources,
    this.timeout = const Duration(seconds: 5),
    this.recheck = const Duration(seconds: 60),
  }) : assert(sources.isNotEmpty);

  List<SourceProvider> sources;
  final Duration timeout;
  final Duration recheck;

  int _active = 0;
  Timer? _probe;
  final _changes = StreamController<String>.broadcast();

  @override
  String get id => 'catalogue';
  @override
  String get displayName => 'Catalogue';

  /// Applies the user's Title API order (ids not listed keep their place at
  /// the end); the first source becomes active again (phase 14).
  void reorder(List<String> ids) {
    final rank = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    sources = [...sources]
      ..sort((a, b) => (rank[a.id] ?? 99).compareTo(rank[b.id] ?? 99));
    _active = 0;
    _probe?.cancel();
    _probe = null;
    _changes.add(activeId);
  }

  /// Id of the source titles currently come from.
  String get activeId => sources[_active].id;

  /// True when titles come from a fallback (shows the "Limited mode" notice).
  bool get limited => _active != 0;

  /// Emits the new [activeId] whenever the source changes.
  Stream<String> get changes => _changes.stream;

  @override
  Future<MediaPage> browse(BrowseQuery query) => _run((s) => s.browse(query));

  @override
  Future<MediaPage> search(String query, {int limit = 50}) =>
      _run((s) => s.search(query, limit: limit));

  @override
  Future<List<SourceSpec>> resolve(MediaItem item) async => const [];

  Future<T> _run<T>(Future<T> Function(SourceProvider) call) async {
    // From the active source down, then the ones above it.
    final order = [
      for (var i = 0; i < sources.length; i++) (_active + i) % sources.length,
    ];
    Object? last;
    for (final i in order) {
      try {
        final result = await call(sources[i]).timeout(
          timeout,
          onTimeout: () => throw ContentSourceFailure.network('timeout'),
        );
        _use(i);
        return result;
      } on ContentSourceFailure catch (error) {
        if (error.code == 'provider.not_found') rethrow;
        last = error;
      } on Object catch (error) {
        last = error;
      }
    }
    throw last!;
  }

  void _use(int index) {
    if (index == _active) return;
    _active = index;
    _changes.add(activeId);
    if (index == 0) {
      _probe?.cancel();
      _probe = null;
    } else {
      _probe ??= Timer.periodic(recheck, (_) => _probeFirst());
    }
  }

  bool _probing = false;

  Future<void> _probeFirst() async {
    if (_probing || _active == 0) return;
    _probing = true;
    try {
      await sources.first.browse(const BrowseQuery(limit: 1)).timeout(timeout);
      _use(0);
    } on Object {
      // Still cut off: stay on the fallback; the next tick tries again.
    } finally {
      _probing = false;
    }
  }

  @override
  Future<void> dispose() async {
    _probe?.cancel();
    await _changes.close();
  }
}
