import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';

import 'source_prefetch.dart';

/// One row of the play-flow provider list: a stable id/display name plus
/// either a real resolver or a permanent failure message. A null [provider]
/// renders as a `failed` row that never becomes selectable-and-loading —
/// e.g. MovieJavan while ch02-p04 stays blocked (ESCALATIONS.md): the row
/// still appears, first, with "MovieJavan login is not set up yet.".
class PlayProviderEntry {
  const PlayProviderEntry({
    required this.id,
    required this.name,
    this.provider,
    this.unavailableMessage,
    this.progress,
    this.cancel,
  }) : assert(
         provider != null || unavailableMessage != null,
         'a provider-less entry needs a message to show',
       );

  final String id;
  final String name;
  final SourceProvider? provider;
  final String? unavailableMessage;

  /// 0..1 while this provider resolves (Playtorrio Direct's sites answered).
  final ValueListenable<double>? progress;

  /// Stops this provider's running resolve (leaving a movie page).
  final VoidCallback? cancel;
}

/// App-owned play-flow screen: provider list -> stream list -> a chosen
/// [SourceSpec]. Resolves on every provider tap (links expire) and never
/// caches a stream list across taps.
class PlayFlowRoute extends StatefulWidget {
  const PlayFlowRoute({
    required this.media,
    required this.providers,
    required this.onStreamSelected,
    required this.onBack,
    required this.onPlayLink,
    required this.onLinkAccepted,
    required this.pickTorrent,
    this.logger,
    this.prefetch,
    this.forgetSaved,
    super.key,
  });

  final MediaItem media;
  final List<PlayProviderEntry> providers;

  /// Called with the chosen stream and the provider row it came from.
  final void Function(SourceSpec spec, PlayProviderEntry entry)
  onStreamSelected;
  final VoidCallback onBack;

  /// "Insert link…": checks the link; returns an error message, or null when
  /// it is playable.
  final PlayLinkHandler onPlayLink;

  /// Called after the Insert-link dialog closed on a playable link.
  final VoidCallback onLinkAccepted;
  final Future<String?> Function() pickTorrent;
  final AppLogger? logger;

  /// Stream lists already loading for [media] (opened from its movie page).
  final SourcePrefetch? prefetch;

  /// Drops a provider's saved stream list for a title (Refresh / Retry).
  final Future<void> Function(String providerId, MediaItem item)? forgetSaved;

  @override
  State<PlayFlowRoute> createState() => _PlayFlowRouteState();
}

class _PlayFlowRouteState extends State<PlayFlowRoute> {
  String? _selectedId;
  UiStreamList _streams = const UiStreamListNone();
  final Map<String, UiProviderState> _states = <String, UiProviderState>{};
  final Map<String, String?> _messages = <String, String?>{};
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    for (final entry in widget.providers) {
      if (entry.provider == null) {
        _states[entry.id] = UiProviderState.failed;
        _messages[entry.id] = entry.unavailableMessage;
      } else {
        _states[entry.id] = UiProviderState.idle;
      }
    }
    final prefetched = widget.prefetch?.media.id == widget.media.id
        ? widget.prefetch!.results
        : const <String, Future<List<SourceSpec>>>{};
    _prefetched.addAll(prefetched);
    for (final MapEntry(key: id, value: result) in prefetched.entries) {
      _states[id] = UiProviderState.loading;
      result.then<void>(
        (_) {
          if (mounted && _selectedId != id) {
            setState(() => _states[id] = UiProviderState.ready);
          }
        },
        onError: (Object error) {
          if (mounted && _selectedId != id) {
            setState(() {
              _states[id] = UiProviderState.failed;
              _messages[id] = error is ProviderFailure
                  ? error.message
                  : AppStrings.of(context).play_providerUnavailable;
            });
          }
        },
      );
    }
  }

  /// Prefetched results, used once each: a Retry resolves afresh.
  final Map<String, Future<List<SourceSpec>>> _prefetched =
      <String, Future<List<SourceSpec>>>{};

  Future<void> _select(String id, {bool fresh = false}) async {
    final entry = widget.providers.firstWhere((e) => e.id == id);
    if (entry.provider == null) {
      setState(() {
        _selectedId = id;
        _streams = UiStreamListFailed(entry.unavailableMessage!);
      });
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _selectedId = id;
      _states[id] = UiProviderState.loading;
      _streams = const UiStreamListLoading();
    });
    try {
      final prefetched = _prefetched.remove(id);
      if (fresh) {
        await widget.forgetSaved?.call(entry.provider!.id, widget.media);
      }
      final streams = await (fresh || prefetched == null
          ? entry.provider!.resolve(widget.media)
          : prefetched);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _states[id] = UiProviderState.ready;
        _messages[id] = null;
        _streams = UiStreamListReady(streams);
      });
    } on ProviderFailure catch (error) {
      widget.logger?.warn(
        'play-flow resolve ${entry.id} ${widget.media.id}: ${error.code}',
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _states[id] = UiProviderState.failed;
        _messages[id] = error.message;
        _streams = UiStreamListFailed(error.message);
      });
    } catch (error, stack) {
      widget.logger?.warn(
        'play-flow resolve ${entry.id} ${widget.media.id} failed',
        error: error,
        stack: stack,
      );
      if (!mounted || requestId != _requestId) return;
      final message = AppStrings.of(context).play_providerUnavailable;
      setState(() {
        _states[id] = UiProviderState.failed;
        _messages[id] = message;
        _streams = UiStreamListFailed(message);
      });
    }
  }

  Future<void> _insertLink() async {
    final accepted = await showPlayLinkDialog(
      context,
      onPlay: widget.onPlayLink,
      pickTorrent: widget.pickTorrent,
    );
    if (accepted == true) widget.onLinkAccepted();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(<Listenable?>[
      for (final entry in widget.providers) entry.progress,
    ]),
    builder: (context, _) => _screen(),
  );

  double? _progressOf(PlayProviderEntry entry) =>
      _states[entry.id] == UiProviderState.loading
      ? entry.progress?.value
      : null;

  Widget _screen() => PlaySourceScreen(
    title: widget.media.title,
    subtitle: widget.media.subtitle,
    providers: <UiProviderOption>[
      for (final entry in widget.providers)
        UiProviderOption(
          id: entry.id,
          name: entry.name,
          state: _states[entry.id] ?? UiProviderState.idle,
          message: _messages[entry.id],
          progress: _progressOf(entry),
        ),
    ],
    selectedProviderId: _selectedId,
    streams: switch (_streams) {
      UiStreamListLoading() when _selectedId != null => UiStreamListLoading(
        progress: _progressOf(
          widget.providers.firstWhere((e) => e.id == _selectedId),
        ),
      ),
      final streams => streams,
    },
    onProviderSelected: _select,
    onStreamSelected: (spec) => widget.onStreamSelected(
      spec,
      widget.providers.firstWhere((e) => e.id == _selectedId),
    ),
    onBack: widget.onBack,
    onInsertLink: _insertLink,
    onRetry: _selectedId == null
        ? null
        : () => _select(_selectedId!, fresh: true),
    onRefresh: _selectedId == null
        ? null
        : () => _select(_selectedId!, fresh: true),
    backdropArtwork: widget.media.artwork?.toString(),
  );
}
