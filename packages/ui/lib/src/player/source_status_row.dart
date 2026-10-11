import '../l10n_gen/app_strings.dart';
import '../l10n_gen/app_strings_en.dart';
import '../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../accessibility/ui_accessibility.dart';

import '../states/state_views.dart';

import '../theme/rivulet_tokens.dart';
import 'panel_row.dart';

String transportFailureMessage(
  TransportFailure failure, {
  AppStrings? strings,
}) => switch (failure.code) {
  'transport.http.no_range_support' =>
    (strings ?? AppStringsEn()).player_transportHttpNoRangeSupport,
  'transport.http.validator_changed' =>
    (strings ?? AppStringsEn()).player_transportHttpValidatorChanged,
  'transport.http.unreachable' =>
    (strings ?? AppStringsEn()).player_transportHttpUnreachable,
  'transport.range.unsatisfiable' =>
    (strings ?? AppStringsEn()).player_transportRangeUnsatisfiable,
  'transport.torrent.no_metadata' =>
    (strings ?? AppStringsEn()).player_transportTorrentNoMetadata,
  'transport.torrent.no_peers' =>
    (strings ?? AppStringsEn()).player_transportTorrentNoPeers,
  'transport.torrent.stalled' =>
    (strings ?? AppStringsEn()).player_transportTorrentStalled,
  'transport.torrent.file_error' =>
    (strings ?? AppStringsEn()).player_transportTorrentFileError,
  'transport.torrent.file_not_found' =>
    (strings ?? AppStringsEn()).player_transportTorrentFileNotFound,
  'transport.engine.unavailable' =>
    (strings ?? AppStringsEn()).player_transportEngineUnavailable,
  _ => (strings ?? AppStringsEn()).player_transportUnknownTransport,
};

/// One source row in [SourcePickerPanel]: token-styled (no stock
/// `ListTile`/Material look, per the phase brief), showing the source's
/// loading/ready/stalled/failed state and, on failure, a retry action.
class SourceStatusRow extends StatelessWidget {
  const SourceStatusRow({
    required this.source,
    required this.active,
    this.status,
    this.onTap,
    this.onRetry,
    this.onBuild,
    this.autofocus = false,
    super.key,
  });

  final SourceSpec source;
  final bool active;
  final SourceStatus? status;
  final VoidCallback? onTap;

  /// Shown as a distinct retry action when [status]'s state is
  /// [SourceState.failed] or [SourceState.stalled].
  final VoidCallback? onRetry;
  final VoidCallback? onBuild;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    onBuild?.call();
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final failure = status?.failure;
    final failed =
        status?.state == SourceState.failed ||
        status?.state == SourceState.stalled;
    final fg = PanelRow.foregroundColor(tokens, selected: active && !failed);
    return PanelRow(
      autofocus: autofocus,
      selected: active,
      failed: failed,
      onTap: onTap,
      tokens: tokens,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: active ? Icon(Icons.play_arrow, color: fg, size: 22) : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText(
                  _label(AppStrings.of(context), source),
                  style: tokens.typeStyles.panelRow.copyWith(color: fg),
                ),
                AppText(
                  failure == null
                      ? _statusLabel(AppStrings.of(context), status)
                      : transportFailureMessage(
                          failure,
                          strings: AppStrings.of(context),
                        ),
                  style: tokens.typeStyles.panelRowCaption.copyWith(
                    color: failed ? colors.danger : fg.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          if (status?.state == SourceState.buffering ||
              status?.state == SourceState.resolving ||
              status?.state == SourceState.metadata)
            SizedBox(
              key: const ValueKey<String>('source-loading'),
              width: 92,
              child: const StateSkeleton(layout: SkeletonLayout.player),
            ),
          if (failed && onRetry != null)
            TextButton(
              key: const ValueKey<String>('source-retry'),
              onPressed: onRetry,
              style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: fg),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AppText(
                  UiAccessibility.labelsOf(context).retry,
                  style: tokens.typeStyles.panelRowCaption.copyWith(color: fg),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(AppStrings strings, SourceSpec source) {
    final kind = switch (source.kind) {
      SourceKind.httpUrl => 'HTTP',
      SourceKind.torrentMagnet => strings.player_sourceTorrent_magnet,
      SourceKind.torrentFile => strings.player_sourceTorrent_file,
      SourceKind.localFile => strings.player_sourceLocal_file,
      SourceKind.hlsUrl => 'HLS',
    };
    final hint = source.uri.host.isNotEmpty
        ? source.uri.host
        : source.fileHint ?? source.uri.path;
    return '$kind · $hint';
  }

  String _statusLabel(AppStrings strings, SourceStatus? status) {
    final state = switch (status?.state) {
      null => strings.player_sourceWaiting_for_status,
      SourceState.resolving => strings.player_sourceResolving_source,
      SourceState.metadata => strings.player_sourceReading_metadata,
      SourceState.buffering => strings.player_sourceBuffering,
      SourceState.ready => strings.player_sourceReady,
      SourceState.stalled => strings.player_sourceStalled,
      SourceState.failed => strings.player_sourceFailed,
      SourceState.closed => strings.player_sourceClosed,
    };
    if (status == null) return state;
    return strings.player_sourceStatus(
      state,
      status.bytesPerSecond.toStringAsFixed(1),
      status.peersOrConnections,
      status.available.ranges.length,
    );
  }
}
