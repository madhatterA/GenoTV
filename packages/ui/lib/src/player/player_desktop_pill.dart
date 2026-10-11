import '../l10n_gen/app_strings.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import '../components/tinted_surface.dart';
import '../theme/rivulet_tokens.dart';
import 'player_control_rail.dart';
import 'player_primary_transport.dart';
import 'progress_rail.dart';
import 'transport_control_button.dart';

/// Desktop's floating, centered glass control pill — the only widget in this
/// phase with no Rivulet source (Rivulet has no macOS app; see
/// `player_control_rail.dart`'s own doc comment for the same gap). Every
/// geometry value here is "measured from infuse-ref/macos/macos_1.png", not
/// a Rivulet citation.
///
/// Row 1: volume (left) — prev/next omitted, no playlist-navigation method
/// exists on `PlaybackController`; -10/play/+10 (center, `PlaybackController.
/// seek`/`play`/`pause`); subtitles/audio/info/up-next (right, the same
/// contract-backed actions the rail exposes elsewhere — settings/pip/
/// airplay/fullscreen from the reference are omitted, no matching
/// `PlaybackController` method exists for any of them).
/// Row 2: elapsed / scrub rail / remaining, reusing [PlayerProgressRow].
class PlayerDesktopPill extends StatefulWidget {
  const PlayerDesktopPill({
    required this.controller,
    required this.state,
    this.actions,
    this.onSubtitles,
    this.onAudio,
    this.onInfo,
    this.onUpNext,
    this.extraActions = 0,
    this.markers = const <ProgressMarker>[],
    this.thumbnail,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.previewPosition,
    super.key,
  });

  final Widget? actions;
  final PlaybackController controller;
  final PlaybackState state;
  final VoidCallback? onSubtitles;
  final VoidCallback? onAudio;
  final VoidCallback? onInfo;
  final VoidCallback? onUpNext;

  /// Buttons in [actions] the callbacks above do not name (each 52px wide).
  final int extraActions;
  final List<ProgressMarker> markers;
  final ImageProvider? thumbnail;
  final VoidCallback? onScrubStart;
  final ValueChanged<Duration>? onScrubUpdate;
  final ValueChanged<Duration>? onScrubEnd;
  final Duration? previewPosition;

  @override
  State<PlayerDesktopPill> createState() => _PlayerDesktopPillState();
}

class _PlayerDesktopPillState extends State<PlayerDesktopPill> {
  @override
  Widget build(BuildContext context) {
    final secondary = <MapEntry<String, IconData>>[
      if (widget.onSubtitles != null)
        const MapEntry<String, IconData>('subtitles', Icons.subtitles_outlined),
      if (widget.onAudio != null)
        const MapEntry<String, IconData>('audio', Icons.graphic_eq),
      if (widget.onInfo != null)
        const MapEntry<String, IconData>('info', Icons.info_outline),
      if (widget.onUpNext != null)
        const MapEntry<String, IconData>(
          'upNext',
          Icons.video_collection_outlined,
        ),
    ];
    final callbackFor = <String, VoidCallback?>{
      'subtitles': widget.onSubtitles,
      'audio': widget.onAudio,
      'info': widget.onInfo,
      'upNext': widget.onUpNext,
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        // measured from infuse-ref/macos/macos_1.png: the pill reads as
        // ~45% of a 1920-wide window (~870px), clamped for narrower windows.
        final width = (constraints.maxWidth * 0.453)
            .clamp(
              widget.actions == null
                  ? 360.0
                  : 534.0 +
                        52 *
                            ((widget.onUpNext == null ? 0 : 1) +
                                widget.extraActions),
              900.0,
            )
            .clamp(0.0, constraints.maxWidth);
        return Center(
          child: SizedBox(
            width: width,
            child: TintedSurface.overMedia(
              key: const ValueKey<String>('player-desktop-pill'),
              radius: RivuletRadius.large,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: <Widget>[
                      // Keep volume at its natural size; narrow pills wrap
                      // the transport/actions instead of shrinking it.
                      PlayerVolumeControl(controller: widget.controller),
                      PlayerPrimaryTransport(
                        controller: widget.controller,
                        state: widget.state,
                        // measured from infuse-ref/macos/macos_1.png: the
                        // play glyph bbox is ~33x39px at the reference's
                        // 2776px width (i.e. ~23x27 at 1920) — 56 diameter
                        // with the ratios below reproduces that (skip 28,
                        // play 32) instead of the previous 40/16/20 set,
                        // which read as tiny icons against the reference.
                        diameter: 56,
                        gap: 14,
                      ),
                      if (widget.actions case final actions?)
                        actions
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (
                              var i = 0;
                              i < secondary.length;
                              i++
                            ) ...<Widget>[
                              if (i > 0) const SizedBox(width: 10),
                              TransportControlButton(
                                key: ValueKey<String>(
                                  'desktop-action-${secondary[i].key}',
                                ),
                                icon: secondary[i].value,
                                semanticLabel: switch (secondary[i].key) {
                                  'subtitles' => AppStrings.of(
                                    context,
                                  ).player_action_subtitles,
                                  'audio' => AppStrings.of(
                                    context,
                                  ).player_action_audio,
                                  'info' => AppStrings.of(
                                    context,
                                  ).player_action_info,
                                  _ => AppStrings.of(
                                    context,
                                  ).player_action_upNext,
                                },
                                // measured from infuse-ref/macos/macos_1.png:
                                // was 32/16, unreadably small next to the
                                // reference's icons; scaled up in the same
                                // proportion as the primary cluster above.
                                diameter: 40,
                                iconSize: 20,
                                onPress: callbackFor[secondary[i].key],
                              ),
                            ],
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  PlayerProgressRow(
                    controller: widget.controller,
                    state: widget.state,
                    compact: true,
                    // Desktop's time labels measure about 15px in
                    // infuse-ref/macos/macos_1.png.
                    fontSize: 15,
                    markers: widget.markers,
                    thumbnail: widget.thumbnail,
                    onScrubStart: widget.onScrubStart,
                    onScrubUpdate: widget.onScrubUpdate,
                    onScrubEnd: widget.onScrubEnd,
                    previewPosition: widget.previewPosition,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `PlaybackController.setVolume` has no matching readable field on
/// `PlaybackState` (Rivulet doesn't surface current volume either), so this
/// keeps its own local 0.0-1.0 value, starting at full volume, and only
/// pushes changes outward — the same "local UI state, contract action" shape
/// `player_chrome_controller.dart`'s ambient/scrub gestures already use.
class PlayerVolumeControl extends StatefulWidget {
  const PlayerVolumeControl({
    required this.controller,
    this.sliderWidth = 90,
    super.key,
  });

  final PlaybackController controller;
  final double sliderWidth;

  @override
  State<PlayerVolumeControl> createState() => _PlayerVolumeControlState();
}

class _PlayerVolumeControlState extends State<PlayerVolumeControl> {
  double _volume = 1;

  @override
  // Fixed-size on purpose (`mainAxisSize: min`, no internal `Expanded`):
  // callers give this a bounded box and are responsible for making that box
  // fit their own layout (`PlayerDesktopPill` wraps its control groups;
  // `the former phone volume bar` uses a fixed-width `SizedBox`) —
  // see both call sites' own comments for why. Putting `Expanded` *inside*
  // this widget instead broke the phone top bar, whose `Align(topRight)`
  // ancestor hands it unbounded width: `Row(mainAxisSize: max)` (the
  // implicit default whenever an `Expanded` child is present) then filled
  // the entire screen width with the slider track — caught by reading
  // `player_rail_compact_844.png` directly, per the brief.
  Widget build(BuildContext context) => Row(
    key: const ValueKey<String>('player-volume'),
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Icon(
        _volume == 0 ? Icons.volume_off : Icons.volume_up,
        color: Colors.white,
        size: 18,
      ),
      const SizedBox(width: 4),
      SizedBox(
        width: widget.sliderWidth,
        // Explicit height, not just width: `Slider` sizes itself to
        // whatever max height its loose incoming constraints allow, and
        // both call sites (`PlayerDesktopPill`'s `Wrap` and
        // `the former phone volume bar`'s bare `Align(topRight)`) hand it unbounded
        // height — with no cap here the slider stretched to the full
        // screen height and its thumb painted vertically centered on
        // screen, which is what read as "volume slider misplaced" (it
        // wasn't horizontally misplaced, `Align(topRight)` already worked;
        // the control's own render box was just 386px tall on a 390px-tall
        // phone screen). 24 matches the row's other controls (18px icon).
        height: 24,
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: SliderComponentShape.noOverlay,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.28),
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: _volume,
            onChanged: (value) {
              setState(() => _volume = value);
              widget.controller.setVolume(value);
            },
          ),
        ),
      ),
    ],
  );
}
