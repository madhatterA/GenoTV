import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'bif_thumbnail_index.dart';

/// Fetches a media part's raw BIF file bytes. Returns `null` when the part
/// has no BIF (the equivalent of Plex's 404, or any other resolvable
/// failure) — this is a normal, cacheable outcome, not a thrown error.
typedef BifBytesFetcher = Future<Uint8List?> Function(String partId);

/// Turns one BIF frame's raw JPEG bytes into a paintable [ImageProvider].
/// Injected so this package never opens an image codec itself (Non-goals:
/// "No HTTP/file access and no custom image codec dependency").
typedef FrameImageDecoder = Future<ImageProvider?> Function(
  Uint8List frameBytes,
);

/// Drives the scrub-thumbnail preview: preloads and indexes a media part's
/// BIF once, resolves a frame for a scrub time, and decodes it to an
/// [ImageProvider] — guarding every async step by a session token so a
/// slow load/decode from a part the caller has since abandoned can never
/// land on the current item.
///
/// Port of the caching/guarding shape of `PlexThumbnailService`
/// (`research/Rivulet/Rivulet/Services/Plex/PlexThumbnailService.swift:14-236`),
/// adapted from its actor-isolated singleton to a plain injectable
/// controller per the phase's Part-boundary decision (byte fetch and frame
/// decode are both injected callbacks, never owned here).
class ThumbnailPreviewController extends ChangeNotifier {
  ThumbnailPreviewController({
    required this.fetchBifBytes,
    required this.decodeFrame,
  });

  final BifBytesFetcher fetchBifBytes;
  final FrameImageDecoder decodeFrame;

  final Map<String, BifThumbnailIndex?> _indexCache =
      <String, BifThumbnailIndex?>{};
  final Map<String, Future<BifThumbnailIndex?>> _loading =
      <String, Future<BifThumbnailIndex?>>{};

  /// Bumped on every [onItemChanged] call. Captured by every in-flight
  /// preload/decode before its first `await`; a stale session's result is
  /// discarded rather than applied. Mirrors `PlexThumbnailService`'s
  /// `loadingTasks[partId] == task` re-check after each `await`
  /// (`PlexThumbnailService.swift:56,136`), generalized to a monotonic
  /// counter so one bump invalidates every part's in-flight work at once.
  int _session = 0;

  /// Bumped on every [requestThumbnail] call, so an out-of-order decode
  /// (a fast scrub tick's frame landing after a slower earlier tick's) is
  /// dropped rather than overwriting a newer frame with a stale one.
  int _requestToken = 0;

  ImageProvider? _currentThumbnail;

  /// The most recently decoded frame. Retained across a new
  /// [requestThumbnail] call while its decode is in flight — the caller
  /// should keep painting this until a new value arrives or [onItemChanged]
  /// clears it (`PlayerProgressBarView.swift:446-455`: "the last frame
  /// stays visible while the next scrub tick's fetch is still in flight").
  ImageProvider? get currentThumbnail => _currentThumbnail;

  /// Loads and indexes the part's BIF once — a second call for the same
  /// part while a load is in flight awaits the same future; a part already
  /// indexed (including a cached "no BIF" `null`) resolves immediately.
  /// Source: `PlexThumbnailService.swift:119-144` (`preloadBIF`).
  Future<BifThumbnailIndex?> preload(String partId) => _ensureIndex(partId);

  Future<BifThumbnailIndex?> _ensureIndex(String partId) {
    if (_indexCache.containsKey(partId)) {
      return SynchronousFuture<BifThumbnailIndex?>(_indexCache[partId]);
    }
    final inFlight = _loading[partId];
    if (inFlight != null) return inFlight;

    final session = _session;
    late final Future<BifThumbnailIndex?> future;
    future = fetchBifBytes(partId).then((bytes) {
      final index = bytes == null ? null : BifThumbnailIndex.parse(bytes);
      // A part release (`clearPart`/`clearAll`) or a whole-controller
      // session bump while this fetch was in flight drops (or replaces)
      // the loading entry to say "nobody is left holding this" — don't
      // re-populate the cache in that case (mirrors the guard at
      // `PlexThumbnailService.swift:56,136`).
      if (session == _session && identical(_loading[partId], future)) {
        _indexCache[partId] = index;
        _loading.remove(partId);
      }
      return index;
    });
    _loading[partId] = future;
    return future;
  }

  /// Resolves the frame nearest [time] in [partId]'s BIF and decodes it,
  /// publishing the result on [currentThumbnail] and notifying listeners.
  /// Guarded by both the session token (item changed) and a request token
  /// (a newer request for the same item superseded this one) — either
  /// makes this call a no-op past that point, per-frame, never throwing.
  Future<void> requestThumbnail({
    required String partId,
    required Duration time,
  }) async {
    final session = _session;
    final myRequest = ++_requestToken;

    final index = await _ensureIndex(partId);
    if (session != _session || myRequest != _requestToken) return;
    if (index == null) return;

    final frameIdx = index.frameIndexAt(time);
    if (frameIdx == null) return;

    final image = await decodeFrame(index.frames[frameIdx].imageData);
    if (session != _session || myRequest != _requestToken) return;
    if (image == null) return;

    _currentThumbnail = image;
    notifyListeners();
  }

  /// Cancels every pending preload/decode (they will observe the bumped
  /// session and drop their result) and clears the currently displayed
  /// thumbnail. Call whenever the player swaps to a different playable
  /// item (`PlayerProgressBarView.swift:660-676`, `resetFilmstrip`).
  void onItemChanged() {
    _session++;
    _requestToken++;
    _currentThumbnail = null;
  }

  /// Releases a single part's cached index and in-flight load, so a load
  /// that finishes after this call doesn't re-fill the cache.
  /// Source: `PlexThumbnailService.swift:219-229` (`clearCache`).
  void clearPart(String partId) {
    _loading.remove(partId);
    _indexCache.remove(partId);
  }

  /// Clears every cached index and in-flight load.
  /// Source: `PlexThumbnailService.swift:231-235` (`clearAllCache`).
  void clearAll() {
    _session++;
    _loading.clear();
    _indexCache.clear();
  }
}
