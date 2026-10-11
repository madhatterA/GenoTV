import 'player_state_views.dart';
import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';
import 'panel_row.dart';

/// Normalizes a language tag for comparison: `en`/`eng`/`ENG` all compare
/// equal. Only the common ISO 639-1/639-2 pairing the phase names is
/// handled explicitly; anything else is lower-cased verbatim.
///
/// `Track.language`/`Track.codec` (`packages/contracts/lib/src/playback/track.dart`)
/// are free-form engine strings with no normalization contract of their own
/// — this table is Part 04's own comparison rule, not a contracts-owned
/// mapping.
String? normalizeTrackLanguage(String? language) {
  if (language == null) return null;
  final lower = language.toLowerCase();
  const eng = <String>{'en', 'eng'};
  if (eng.contains(lower)) return 'en';
  return lower;
}

/// Normalizes a subtitle/audio codec name: `subrip`/`srt` compare equal.
String? normalizeTrackCodec(String? codec) {
  if (codec == null) return null;
  final lower = codec.toLowerCase();
  const srt = <String>{'subrip', 'srt'};
  if (srt.contains(lower)) return 'srt';
  return lower;
}

/// True when a track's title marks it as commentary or an audio-description
/// track. `Track` (contracts) carries no dedicated flag for either — this is
/// a title-text heuristic, the only signal Part 04's contract exposes; see
/// the phase report's "what still differs" section.
bool isCommentaryOrDescriptiveTrack(Track track) {
  final title = track.title?.toLowerCase() ?? '';
  return title.contains('commentary') ||
      title.contains('audio description') ||
      title.contains('described');
}

/// What the caller would like selected, in preference order (step 4):
/// exact requested track id; then same-language (quality/channels/codec are
/// not in the `Track` contract, so that tier degrades to a language+codec
/// match — see the phase report); then English; then the file's own
/// default; then the first valid, non-commentary/description track.
class TrackPreference {
  const TrackPreference({this.trackId, this.language, this.codec});

  final String? trackId;
  final String? language;
  final String? codec;
}

/// Ranks [candidates] per [TrackPreference.resolve]'s tiers. Pure and
/// synchronous so the ranking table can be tested without pumping a widget.
Track? resolveTrackPreference(
  List<Track> candidates,
  TrackPreference preference,
) {
  final eligible = candidates
      .where((track) => !isCommentaryOrDescriptiveTrack(track))
      .toList();
  if (eligible.isEmpty) return null;

  if (preference.trackId case final id?) {
    for (final track in eligible) {
      if (track.id == id) return track;
    }
  }

  final wantLanguage = normalizeTrackLanguage(preference.language);
  final wantCodec = normalizeTrackCodec(preference.codec);
  if (wantLanguage != null) {
    for (final track in eligible) {
      if (normalizeTrackLanguage(track.language) == wantLanguage &&
          (wantCodec == null ||
              normalizeTrackCodec(track.codec) == wantCodec)) {
        return track;
      }
    }
    for (final track in eligible) {
      if (normalizeTrackLanguage(track.language) == wantLanguage) return track;
    }
  }

  for (final track in eligible) {
    if (normalizeTrackLanguage(track.language) == 'en') return track;
  }

  for (final track in eligible) {
    if (track.isDefault) return track;
  }

  return eligible.first;
}

/// Audio/subtitle track panel. Optimistic selection: the UI updates
/// immediately and calls [controller]; on a `playback.track.selection_failed`
/// event the previous selection is restored, the panel stays open, the
/// failed row keeps focus, and the error is exposed to accessibility
/// (`Semantics.liveRegion`).
///
/// Source: player track panel row layout/selection-state look —
/// `evidence/part-04-rivulet/infuse-ref/tvos/IMG_8304.jpg` (subtitle popover,
/// checkmark on selected) and `IMG_8305-8306.jpg` (audio popover, single
/// pill) — see `evidence/part-04-rivulet/ch03-p05/` compares.
class TrackPanel extends StatefulWidget {
  const TrackPanel({
    required this.controller,
    required this.state,
    required this.dismiss,
    this.type,
    this.compact = false,
    this.showHeadings = true,
    this.closeOnSelection = false,
    this.embedded = false,
    this.onAddSubtitleFiles,
    super.key,
  });

  /// Lets the viewer pick their own subtitle file or zip: returns the staged
  /// files (empty when cancelled) or throws a user-facing error. Null hides
  /// the "Add subtitle file…" row.
  final Future<List<({String name, Uri uri})>> Function()? onAddSubtitleFiles;

  final PlaybackController controller;
  final PlaybackState state;
  final VoidCallback dismiss;
  final TrackType? type;
  final bool compact;
  final bool showHeadings;
  final bool closeOnSelection;
  final bool embedded;

  @override
  State<TrackPanel> createState() => _TrackPanelState();
}

class _TrackPanelState extends State<TrackPanel> {
  late TrackSelection _selection = widget.state.selected;
  TrackSelection? _pendingRevert;
  String? _failure;
  String? _failedRowKey;
  StreamSubscription<PlaybackEvent>? _events;

  @override
  void initState() {
    super.initState();
    _events = widget.controller.events.listen(_onEvent);
  }

  @override
  void dispose() {
    _events?.cancel();
    super.dispose();
  }

  void _onEvent(PlaybackEvent event) {
    if (event case PlaybackFailed(:final failure)
        when failure.code == 'playback.track.selection_failed') {
      setState(() {
        if (_pendingRevert case final revert?) _selection = revert;
        _pendingRevert = null;
        _failure = playerFailureMessage(failure, AppStrings.of(context));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final tracks = widget.state.tracks;
    return ListView(
      key: const ValueKey<String>('track-panel-list'),
      shrinkWrap: widget.closeOnSelection || widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: widget.closeOnSelection ? EdgeInsets.zero : null,
      children: <Widget>[
        if (widget.type != TrackType.subtitle && widget.showHeadings)
          _SectionHeader(
            label: AppStrings.of(context).player_audio,
            tokens: tokens,
          ),
        if (widget.type != TrackType.subtitle)
          for (final track in tracks.audio)
            _TrackRow(
              key: ValueKey<String>('track-${track.id}'),
              track: track,
              compact: widget.compact,
              selected: _selection.audio == TrackChoice.specific(track.id),
              failed: _failedRowKey == track.id,
              autofocus: _selection.audio == TrackChoice.specific(track.id),
              onTap: () => _select(track.id, isAudio: true),
            ),
        if (widget.type == null) const SizedBox(height: 12),
        if (widget.type != TrackType.audio && widget.showHeadings)
          _SectionHeader(
            label: AppStrings.of(context).player_subtitles,
            tokens: tokens,
          ),
        if (widget.type != TrackType.audio && widget.onAddSubtitleFiles != null)
          PanelRow(
            key: const ValueKey<String>('subtitle-add-file'),
            compact: widget.compact,
            selected: false,
            onTap: _adding ? null : _addFiles,
            tokens: tokens,
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 28,
                  child: Icon(
                    Icons.add,
                    size: 22,
                    color: PanelRow.foregroundColor(tokens, selected: false),
                  ),
                ),
                Expanded(
                  child: AppText(
                    AppStrings.of(context).player_addSubtitleFile,
                    style: tokens.typeStyles.panelRow.copyWith(
                      color: PanelRow.foregroundColor(tokens, selected: false),
                      fontSize: widget.compact ? 16 : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_failure case final message?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: AppText(
                key: const ValueKey<String>('track-selection-failure'),
                message,
                style: TextStyle(color: tokens.colors.danger),
              ),
            ),
          ),
        if (widget.type != TrackType.audio)
          _SubtitleOffRow(
            compact: widget.compact,
            selected: _selection.subtitle.mode == TrackSelectionMode.off,
            autofocus: _selection.subtitle.mode == TrackSelectionMode.off,
            onTap: () => _selectSubtitleOff(),
            tokens: tokens,
          ),
        if (widget.type != TrackType.audio)
          for (final track in tracks.subtitle)
            _TrackRow(
              key: ValueKey<String>('track-${track.id}'),
              track: track,
              compact: widget.compact,
              selected: _selection.subtitle == TrackChoice.specific(track.id),
              failed: _failedRowKey == track.id,
              autofocus: _selection.subtitle == TrackChoice.specific(track.id),
              onTap: () => _select(track.id, isAudio: false),
            ),
      ],
    );
  }

  bool _adding = false;

  /// Adds every picked subtitle to the playback; the first one added becomes
  /// the active subtitle (later ones are only listed).
  Future<void> _addFiles() async {
    final strings = AppStrings.of(context);
    setState(() {
      _adding = true;
      _failure = null;
    });
    try {
      final files = await widget.onAddSubtitleFiles!();
      final known = {
        for (final t in widget.controller.currentState.tracks.subtitle) t.id,
      };
      for (final file in files) {
        await widget.controller.addExternalSubtitle(file.uri, title: file.name);
      }
      if (files.isEmpty || !mounted) return;
      final added = widget.controller.currentState.tracks.subtitle
          .where((t) => !known.contains(t.id))
          .firstOrNull;
      if (added == null) throw StateError(strings.player_subtitleNotAdded);
      final current = widget.controller.currentState.selected;
      final selection = TrackSelection(
        video: current.video,
        audio: current.audio,
        subtitle: TrackChoice.specific(added.id),
      );
      await widget.controller.selectTrack(selection);
      if (mounted) setState(() => _selection = selection);
    } catch (error) {
      if (mounted) {
        setState(
          () => _failure = error is PlaybackFailure
              ? playerFailureMessage(error, AppStrings.of(context))
              : error.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _applySelection(TrackSelection selection) async {
    try {
      await widget.controller.selectTrack(selection);
      if (!mounted || _failure != null) return;
      _pendingRevert = null;
      if (widget.closeOnSelection) widget.dismiss();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        if (_pendingRevert case final revert?) _selection = revert;
        _pendingRevert = null;
        _failure = error is PlaybackFailure
            ? playerFailureMessage(error, AppStrings.of(context))
            : AppStrings.of(context)
                  .player_unableToSelectTrack(error.toString());
      });
    }
  }

  void _selectSubtitleOff() {
    _pendingRevert = _selection;
    setState(() {
      _selection = TrackSelection(
        video: _selection.video,
        audio: _selection.audio,
        subtitle: const TrackChoice.off(),
      );
      _failure = null;
      _failedRowKey = null;
    });
    unawaited(_applySelection(_selection));
  }

  void _select(String trackId, {required bool isAudio}) {
    _pendingRevert = _selection;
    final choice = TrackChoice.specific(trackId);
    setState(() {
      _selection = isAudio
          ? TrackSelection(
              video: _selection.video,
              audio: choice,
              subtitle: _selection.subtitle,
            )
          : TrackSelection(
              video: _selection.video,
              audio: _selection.audio,
              subtitle: choice,
            );
      _failure = null;
      _failedRowKey = trackId;
    });
    unawaited(_applySelection(_selection));
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.tokens});

  final String label;
  final RivuletTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: AppText(label, style: tokens.typeStyles.label),
  );
}

class _SubtitleOffRow extends StatelessWidget {
  const _SubtitleOffRow({
    required this.selected,
    this.compact = false,
    required this.autofocus,
    required this.onTap,
    required this.tokens,
  });

  final bool selected;
  final bool compact;
  final bool autofocus;
  final VoidCallback onTap;
  final RivuletTokens tokens;

  @override
  Widget build(BuildContext context) {
    final fg = PanelRow.foregroundColor(tokens, selected: selected);
    return PanelRow(
      compact: compact,
      key: const ValueKey<String>('subtitle-off'),
      autofocus: autofocus,
      selected: selected,
      onTap: onTap,
      tokens: tokens,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: selected ? Icon(Icons.check, color: fg, size: 22) : null,
          ),
          Expanded(
            child: AppText(
              AppStrings.of(context).common_off,
              style: tokens.typeStyles.panelRow.copyWith(
                color: fg,
                fontSize: compact ? 16 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.selected,
    this.compact = false,
    required this.failed,
    required this.autofocus,
    required this.onTap,
    super.key,
  });

  final Track track;
  final bool selected;
  final bool compact;
  final bool failed;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final fg = PanelRow.foregroundColor(tokens, selected: selected && !failed);
    final details = <String>[
      if (track.language != null) track.language!.toUpperCase(),
      if (track.codec != null) track.codec!,
    ].join(' · ');
    return PanelRow(
      compact: compact,
      autofocus: autofocus,
      selected: selected,
      failed: failed,
      onTap: onTap,
      tokens: tokens,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 28,
            child: selected ? Icon(Icons.check, color: fg, size: 22) : null,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                AppText.content(
                  track.title ?? details,
                  style: tokens.typeStyles.panelRow.copyWith(
                    color: fg,
                    fontSize: compact ? 16 : null,
                  ),
                ),
                if (track.title != null && details.isNotEmpty)
                  AppText.content(
                    details,
                    style: tokens.typeStyles.panelRowCaption.copyWith(
                      color: fg.withValues(alpha: 0.7),
                      fontSize: compact ? 13 : null,
                    ),
                  ),
              ],
            ),
          ),
          if (track.isDefault)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _Badge(
                label: AppStrings.of(context).player_defaultBadge,
                tokens: tokens,
                foreground: fg,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.tokens,
    required this.foreground,
  });

  final String label;
  final RivuletTokens tokens;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: foreground.withValues(alpha: 0.5)),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: AppText(
        label,
        style: tokens.typeStyles.caption.copyWith(
          color: foreground.withValues(alpha: 0.8),
        ),
      ),
    ),
  );
}
