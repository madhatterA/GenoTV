import 'package:contracts/contracts.dart';

import 'play_flow.dart';

/// Every provider's stream list for one movie, started when its detail page
/// opens so the play flow finds them ready (owner 2026-10-10). Movies only:
/// a show would cost one lookup per episode. [stop] runs when the page
/// closes so nothing keeps loading in the background.
class SourcePrefetch {
  SourcePrefetch(this.media, this._providers) {
    for (final entry in _providers) {
      final provider = entry.provider;
      if (provider == null) continue;
      final result = provider.resolve(media);
      // Failures are read by the play flow when it awaits the future; this
      // only keeps an unread failure from reaching the zone as unhandled.
      result.then<void>((_) {}, onError: (Object _) {});
      results[entry.id] = result;
    }
  }

  final MediaItem media;
  final List<PlayProviderEntry> _providers;
  final Map<String, Future<List<SourceSpec>>> results =
      <String, Future<List<SourceSpec>>>{};
  bool _stopped = false;

  void stop() {
    if (_stopped) return;
    _stopped = true;
    for (final entry in _providers) {
      entry.cancel?.call();
    }
  }
}
