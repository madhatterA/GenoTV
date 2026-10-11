import 'package:core/core.dart';

import '../media/media_item.dart';
import '../media/source_spec.dart';

class BrowseQuery {
  const BrowseQuery({this.kind, this.offset = 0, this.limit = 50, this.sort});

  final MediaKind? kind;
  final int offset;
  final int limit;
  final String? sort;
}

class MediaPage {
  MediaPage({required List<MediaItem> items, this.total, required this.hasMore})
      : items = List<MediaItem>.unmodifiable(items);

  final List<MediaItem> items;
  final int? total;
  final bool hasMore;
}

/// `provider.*` prefix, owned by Part 06 — this base only, no leaves.
/// Declaring a leaf here would pre-empt a Part this repo deliberately
/// leaves empty (decision D6). `base`, not `final`: Part 06 must be able
/// to extend this with its own leaves later, the same way PlaybackFailure/
/// TransportFailure/PlatformFailure do for their own Parts — nothing stops
/// a caller from using this directly with its own `code` in the meantime.
base class ProviderFailure extends AppFailure {
  const ProviderFailure({required super.code, required super.message, super.cause, super.stack});
}

/// Declared here (interface only) so Parts 04 and 07 have something to
/// hold; Part 06 is empty by owner instruction (decision D6). No Part may
/// invent a provider, scraper, catalogue or search implementation behind
/// this until the owner specifies Part 06.
abstract interface class SourceProvider {
  /// Stable, e.g. `'fixture'`.
  String get id;
  String get displayName;

  /// Items to browse. Paged; a provider with no catalogue returns an
  /// empty page.
  Future<MediaPage> browse(BrowseQuery query);

  /// Free-text search. A provider that cannot search returns an empty
  /// page.
  Future<MediaPage> search(String query, {int limit = 50});

  /// Playable sources for one item. This is the call that matters; browse
  /// and search may both be empty for a provider that only resolves
  /// links.
  Future<List<SourceSpec>> resolve(MediaItem item);

  Future<void> dispose();
}
