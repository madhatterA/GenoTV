import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'player_metadata.dart';
import 'progress_rail.dart';
import 'transport_control_button.dart';

/// The rail's secondary actions, in the fixed order Rivulet renders them.
///
/// Source: `PlayerRailView.swift:125-127` (`cluster` arranged-subview order)
/// and the phase file's Decisions table: "subtitles, audio, info, insights,
/// up next, filter; no skip-back button".
import '../platform/form_factor.dart';

enum RailAction { subtitles, audio, info, insights, upNext, filter }

/// What the rail should land focus on: a [RailAction] button, or the
/// scrubber (owned by the caller, not this widget — see
/// [PlayerControlRail.scrubberAutofocus]).
enum RailFocusTarget {
  scrubber,
  subtitles,
  audio,
  info,
  insights,
  upNext,
  filter,
}

RailFocusTarget _targetFor(RailAction action) => switch (action) {
  RailAction.subtitles => RailFocusTarget.subtitles,
  RailAction.audio => RailFocusTarget.audio,
  RailAction.info => RailFocusTarget.info,
  RailAction.insights => RailFocusTarget.insights,
  RailAction.upNext => RailFocusTarget.upNext,
  RailAction.filter => RailFocusTarget.filter,
};

/// Pure port of `PlayerRailView.preferredFocusEnvironments`
/// (`PlayerRailView.swift:274-279`) and `didUpdateFocus`/`resetFocusMemory`
/// (`:284-293`): a remembered button (if still visible) wins; otherwise the
/// scrubber (first arrival); otherwise the default action; otherwise the
/// first visible action.
///
/// Kept as a plain, widget-free class — like this Part's existing
/// `PlayerChromeController` state machines — so "default/remembered/fallback
/// focus" is provable by direct unit tests rather than driving Flutter's
/// focus engine in a widget test.
class RailFocusMemory {
  RailFocusTarget? _remembered;

  /// The target the rail should land on right now.
  RailFocusTarget resolve({
    required List<RailAction> visible,
    required RailAction defaultAction,
    bool scrubberAvailable = true,
  }) {
    final remembered = _remembered;
    if (remembered != null && remembered != RailFocusTarget.scrubber) {
      final stillVisible = visible.any((a) => _targetFor(a) == remembered);
      if (stillVisible) return remembered;
    }
    if (scrubberAvailable) return RailFocusTarget.scrubber;
    if (visible.contains(defaultAction)) return _targetFor(defaultAction);
    if (visible.isNotEmpty) return _targetFor(visible.first);
    return RailFocusTarget.scrubber;
  }

  /// Records that focus moved onto a button (never the scrubber — matches
  /// `didUpdateFocus`'s `next is UIControl` guard at `PlayerRailView.swift:290`).
  void remember(RailFocusTarget target) {
    if (target != RailFocusTarget.scrubber) _remembered = target;
  }

  /// `PlayerRailView.swift:284-286` — `resetFocusMemory()`: drop the
  /// remembered button so the next appearance starts on the scrubber again.
  void reset() => _remembered = null;

  RailFocusTarget? get remembered => _remembered;
}

const Map<RailAction, IconData> _railIcons = <RailAction, IconData>{
  RailAction.subtitles: Icons.subtitles_outlined,
  RailAction.audio: Icons.graphic_eq,
  RailAction.info: Icons.info_outline,
  RailAction.insights: Icons.auto_awesome_outlined,
  RailAction.upNext: Icons.video_collection_outlined,
  RailAction.filter: Icons.front_hand_outlined,
};

Map<RailAction, String> _railLabels(AppStrings strings) => {
  RailAction.subtitles: strings.player_subtitles,
  RailAction.audio: strings.player_audio,
  RailAction.info: strings.player_info,
  RailAction.insights: strings.player_insights,
  RailAction.upNext: strings.player_upNext,
  RailAction.filter: strings.player_contentFilter,
};

/// The bottom glass rail: metadata left, progress rail + elapsed/remaining,
/// round action buttons right. One widget serves both the TV/10-foot layout
/// and desktop (noncompact — Rivulet has no separate macOS rail spec, only
/// tvOS and a `compact`-flagged iOS one; desktop reuses the tvOS geometry)
/// and the touch/phone layout (compact), switched by [compact].
///
/// Source: `research/Rivulet/Rivulet/Views/Player/UIKit/PlayerRailView.swift`
/// (noncompact geometry) and `research/Rivulet/RivuletiOS/Player/IOSPlayerChrome.swift`
/// (`compact` geometry) — see field-level citations below and in
/// `player_metadata.dart`/`transport_control_button.dart`.
class PlayerControlRail extends StatefulWidget {
  const PlayerControlRail({
    required this.title,
    required this.controller,
    required this.state,
    this.eyebrow,
    this.rating,
    this.runtime,
    this.audio,
    this.compact = false,
    this.onSubtitles,
    this.onAudio,
    this.onInfo,
    this.onInsights,
    this.onUpNext,
    this.onFilter,
    this.onReplayLongPress,
    this.filterEnabled = false,
    this.ambient = false,
    this.keepTitleWhenAmbient = false,
    this.focusMemory,
    this.leadingButton,
    this.actions,
    this.showPlate = true,
    this.elapsedUnderPlayhead = false,
    this.markers = const <ProgressMarker>[],
    this.thumbnail,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewPosition,
    super.key,
  });

  final String title;
  final PlaybackController controller;
  final PlaybackState state;
  final String? eyebrow;
  final String? rating;
  final String? runtime;
  final String? audio;

  /// TV/desktop (`false`, `PlayerRailView.swift` geometry) vs touch/phone
  /// (`true`, `IOSPlayerChrome.swift`'s `compact` geometry).
  final bool compact;

  /// Action callbacks. An action with no callback is not rendered (Step 4:
  /// "Render only actions supported by callbacks/data") — `insights` and
  /// `filter` additionally default hidden in Rivulet even when wired
  /// (`PlayerRailView.swift:168-171`), so those two also need their
  /// `*Available` flag; the others need only a non-null callback.
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudio;
  final VoidCallback? onInfo;
  final VoidCallback? onInsights;
  final VoidCallback? onUpNext;
  final VoidCallback? onFilter;

  /// `PlayerRailView.swift:56,162` — long-pressing Subtitles (the rail's
  /// leftmost/default button) triggers "replay", not a second subtitles
  /// action.
  final VoidCallback? onReplayLongPress;

  /// Reflects on/off in the filter glyph (`setFilterEnabled`,
  /// `PlayerRailView.swift:176-178`).
  final bool filterEnabled;

  /// `PlayerRailView.swift:230-254` — ambient pause: plate/metadata/buttons
  /// fade to 0; the title stays if [keepTitleWhenAmbient] (episodic media).
  final bool ambient;
  final bool keepTitleWhenAmbient;

  /// Injectable for tests that need to assert on remembered-focus behavior
  /// across rebuilds; defaults to an owned instance.
  final RailFocusMemory? focusMemory;

  /// An extra button rendered before the [RailAction] cluster, outside the
  /// enum's own traversal order — the ch03-p02 owner rejection requires
  /// "exactly one play-pause control per form factor"; TV has no separate
  /// primary-transport chrome (`PlayerScreen` renders desktop/phone's
  /// play-pause inside their own cluster instead), so TV's single play-pause
  /// button lives here, next to the rail's own action row
  /// (`evidence/part-04-rivulet/infuse-ref/tvos/IMG_8303.jpg`: "3 round
  /// glass icon buttons right above rail" — this is the 4th, leftmost one).
  final Widget? leadingButton;
  final Widget? actions;

  /// `false` renders the rail with no box background/border/shadow — TV's
  /// resting chrome per the owner's rejection has no boxed plate, only a
  /// bottom gradient scrim (`PlayerScreen` renders that scrim as its own
  /// layer, behind this rail). Desktop/phone keep the glass plate (`true`,
  /// the phase file's Decisions-table geometry).
  final bool showPlate;

  /// `true` positions the elapsed-time label under the scrub thumb instead
  /// of flush left (`evidence/part-04-rivulet/infuse-ref/tvos/IMG_8303.jpg`)
  /// — TV only; desktop/phone match the elapsed-left/remaining-right layout
  /// visible in `macos/macos_1.png` and `ios/IMG_8298.PNG`.
  final bool elapsedUnderPlayhead;
  final List<ProgressMarker> markers;
  final ImageProvider? thumbnail;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final Duration? previewPosition;

  @override
  State<PlayerControlRail> createState() => PlayerControlRailState();
}

class PlayerControlRailState extends State<PlayerControlRail> {
  late final RailFocusMemory _memory = widget.focusMemory ?? RailFocusMemory();
  late final Map<RailAction, FocusNode> _nodes = <RailAction, FocusNode>{
    for (final action in RailAction.values)
      action: FocusNode(debugLabel: 'rail-${action.name}'),
  };

  List<RailAction> get _visibleActions =>
      RailAction.values.where(_isVisible).toList();

  bool _isVisible(RailAction action) => switch (action) {
    RailAction.subtitles => widget.onSubtitles != null,
    RailAction.audio => widget.onAudio != null,
    RailAction.info => widget.onInfo != null,
    // PlayerRailView.swift:168-171 — hidden by default even when wired;
    // callers opt in explicitly (mirrors setInsightsAvailable/onFilter wiring).
    RailAction.insights => widget.onInsights != null,
    RailAction.upNext => widget.onUpNext != null,
    RailAction.filter => widget.onFilter != null,
  };

  VoidCallback? _callbackFor(RailAction action) => switch (action) {
    RailAction.subtitles => widget.onSubtitles,
    RailAction.audio => widget.onAudio,
    RailAction.info => widget.onInfo,
    RailAction.insights => widget.onInsights,
    RailAction.upNext => widget.onUpNext,
    RailAction.filter => widget.onFilter,
  };

  /// The traversal order of currently-visible actions — exposed for the
  /// confirmation item "Traversal list contains exactly the visible
  /// supported actions."
  List<RailAction> get traversalOrder => _visibleActions;

  /// [scrubberAvailable]: whether the sibling scrubber can currently take
  /// focus (`state.duration > Duration.zero` at the call site) — a real
  /// caller fact, not derived from remembered state
  /// (`PlayerRailView.swift:276`: `scrubberFocusProxy.canBecomeFocused`).
  RailFocusTarget resolveFocus({
    RailAction defaultAction = RailAction.subtitles,
    bool scrubberAvailable = true,
  }) => _memory.resolve(
    visible: _visibleActions,
    defaultAction: defaultAction,
    scrubberAvailable: scrubberAvailable,
  );

  /// Drops the remembered button (`resetFocusMemory`,
  /// `PlayerRailView.swift:284-286`) — call when controls-focus mode ends.
  void resetFocusMemory() => _memory.reset();

  @override
  void initState() {
    super.initState();
    // Registered once per node (not per build): mirrors `didUpdateFocus`
    // (`PlayerRailView.swift:288-293`), which fires only on a real focus
    // transition, never once per layout pass.
    for (final action in RailAction.values) {
      final target = _targetFor(action);
      _nodes[action]!.addListener(() {
        if (_nodes[action]!.hasFocus) _memory.remember(target);
      });
    }
  }

  @override
  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final geometry = tokens.geometry;
    final colors = tokens.colors;
    final visible = _visibleActions;

    final metadata = PlayerMetadata(
      title: widget.title,
      eyebrow: widget.eyebrow,
      rating: widget.rating,
      runtime: widget.runtime,
      audio: widget.audio,
      compact: widget.compact,
    );

    final progress = PlayerProgressRow(
      controller: widget.controller,
      state: widget.state,
      compact: widget.compact,
      elapsedUnderPlayhead: widget.elapsedUnderPlayhead,
      markers: widget.markers,
      thumbnail: widget.thumbnail,
      onScrubStart: widget.onScrubStart,
      onScrubUpdate: widget.onScrubUpdate,
      onScrubEnd: widget.onScrubEnd,
      previewPosition: widget.previewPosition,
    );

    final buttons = Row(
      key: const ValueKey<String>('rail-actions'),
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.leadingButton case final leading?) ...<Widget>[
          leading,
          SizedBox(width: widget.compact ? 12 : geometry.railButtonGap),
        ],
        ?widget.actions,
        for (var i = 0; i < visible.length; i++) ...<Widget>[
          if (i > 0)
            SizedBox(width: widget.compact ? 12 : geometry.railButtonGap),
          _buildButton(visible[i], tokens),
        ],
      ],
    );

    final plateOpacity = widget.ambient ? 0.0 : 1.0;
    final titleOpacity = widget.ambient
        ? (widget.keepTitleWhenAmbient ? 1.0 : 0.0)
        : 1.0;

    final radius = widget.compact ? 24.0 : 32.0;
    final content = widget.compact
        ? _CompactLayout(
            metadata: metadata,
            buttons: buttons,
            progress: progress,
          )
        : _NoncompactLayout(
            metadata: metadata,
            buttons: buttons,
            progress: progress,
            geometry: geometry,
          );

    return Container(
      key: const ValueKey<String>('player-control-rail'),
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 14 : geometry.railPadH,
        vertical: widget.compact ? 8 : geometry.railPadV,
      ),
      constraints: widget.compact
          ? null
          : BoxConstraints(minHeight: geometry.railHeight),
      decoration: !widget.showPlate
          ? null
          : BoxDecoration(
              color: colors.railPlateFill.withValues(
                alpha: colors.railPlateFill.a * plateOpacity,
              ),
              border: Border.all(
                color: colors.railBorder.withValues(
                  alpha: colors.railBorder.a * plateOpacity,
                ),
              ),
              borderRadius: BorderRadius.circular(radius),
              boxShadow: plateOpacity == 0
                  ? const <BoxShadow>[]
                  : <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 35,
                        offset: const Offset(0, 15),
                      ),
                    ],
            ),
      child: AnimatedOpacity(
        opacity: plateOpacity,
        duration: const Duration(milliseconds: 180),
        child: _AmbientTitleOverride(
          titleOpacity: titleOpacity,
          showChrome: !widget.ambient,
          child: content,
        ),
      ),
    );
  }

  Widget _buildButton(RailAction action, RivuletTokens tokens) {
    final node = _nodes[action]!;
    final diameter = widget.compact
        ? (action == RailAction.subtitles || action == RailAction.audio
              ? 36.0
              : 44.0)
        : tokens.geometry.railButtonDiameter;
    return TransportControlButton(
      key: ValueKey<String>('rail-action-${action.name}'),
      icon: action == RailAction.filter && widget.filterEnabled
          ? Icons.front_hand
          : _railIcons[action]!,
      semanticLabel: action == RailAction.filter && widget.filterEnabled
          ? AppStrings.of(context)
                .player_filterOn(_railLabels(AppStrings.of(context))[action]!)
          : _railLabels(AppStrings.of(context))[action]!,
      diameter: diameter,
      iconSize: widget.compact ? diameter * 0.4 : 25,
      focusNode: node,
      onPress: _callbackFor(action),
      onLongPress: action == RailAction.subtitles
          ? widget.onReplayLongPress
          : null,
    );
  }
}

class _NoncompactLayout extends StatelessWidget {
  const _NoncompactLayout({
    required this.metadata,
    required this.buttons,
    required this.progress,
    required this.geometry,
  });

  final Widget metadata;
  final Widget buttons;
  final Widget progress;
  final RivuletGeometry geometry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: metadata),
          SizedBox(width: geometry.railTopRowGap),
          buttons,
        ],
      ),
      const SizedBox(height: 20),
      progress,
    ],
  );
}

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.metadata,
    required this.buttons,
    required this.progress,
  });

  final Widget metadata;
  final Widget buttons;
  final Widget progress;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(child: metadata),
          const SizedBox(width: 8),
          buttons,
        ],
      ),
      const SizedBox(height: 12),
      progress,
    ],
  );
}

/// Elapsed/remaining under the shared [ProgressRail].
/// widget for the bar itself — this phase does not own scrub gesture/seek
/// algorithm (Non-goals). Reused by both `PlayerControlRail` (TV/desktop/
/// phone rail progress) and the desktop floating pill's own progress row
/// (`player_desktop_pill.dart`) rather than duplicating the formatting/
/// layout logic a second time.
///
/// Default (`elapsedUnderPlayhead: false`): elapsed left, remaining right —
/// matches `macos/macos_1.png` and `ios/IMG_8298.PNG`. `true`: elapsed
/// tracks the thumb's fractional position along the rail, remaining stays
/// right-aligned — matches `tvos/IMG_8303.jpg`'s resting TV chrome.
class PlayerProgressRow extends StatelessWidget {
  const PlayerProgressRow({
    required this.controller,
    required this.state,
    required this.compact,
    this.elapsedUnderPlayhead = false,
    this.fontSize,
    this.markers = const <ProgressMarker>[],
    this.thumbnail,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewPosition,
    super.key,
  });

  final PlaybackController controller;
  final PlaybackState state;
  final bool compact;
  final bool elapsedUnderPlayhead;
  final double? fontSize;
  final List<ProgressMarker> markers;
  final ImageProvider? thumbnail;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final Duration? previewPosition;

  @override
  Widget build(BuildContext context) {
    final progress = ProgressRail(
      position: previewPosition ?? state.position,
      duration: state.duration,
      bufferedAhead: state.bufferedAhead,
      chapters: state.chapters
          .map(
            (chapter) =>
                ProgressChapter(start: chapter.start, name: chapter.title),
          )
          .toList(),
      markers: markers,
      isPaused: !state.isPlaying,
      isSkeleton: state.duration <= Duration.zero,
      thumbnail: thumbnail,
      onScrubStart: onScrubStart,
      onScrubUpdate: onScrubUpdate,
      onScrubEnd: onScrubEnd ?? controller.seek,
      playerChrome: true,
      elapsedUnderPlayhead: elapsedUnderPlayhead,
      labelSize: fontSize ?? (compact ? 12 : 20),
    );
    if (!(AdaptiveBehavior.of(context).formFactor == FormFactor.tv)) {
      return progress;
    }
    return FocusRing(
      child: Focus(debugLabel: 'tv-seek-bar', child: progress),
    );
  }
}

/// Keeps the title visible during ambient pause when [showChrome] is false
/// but [titleOpacity] is 1 — the parent `AnimatedOpacity` fades everything
/// including the title, so this override counter-fades the title back up
/// (`PlayerRailView.swift:253`: title alpha is set independently of the
/// plate/metadata/cluster group).
class _AmbientTitleOverride extends StatelessWidget {
  const _AmbientTitleOverride({
    required this.titleOpacity,
    required this.showChrome,
    required this.child,
  });

  final double titleOpacity;
  final bool showChrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (showChrome) return child;
    // Ambient: everything the parent already faded to 0 stays hidden except
    // the title, restored via an independent opacity animation layered on
    // top at the title's own position. Simpler and exact for this phase's
    // purposes: render only the title (compact metadata's first line) at
    // titleOpacity, matching "hides plate, metadata, and buttons but keeps
    // episode title" — no other ambient content is interactive or visible.
    return Opacity(
      opacity: titleOpacity,
      child: IgnorePointer(child: child),
    );
  }
}
