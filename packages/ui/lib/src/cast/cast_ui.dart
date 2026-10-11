import '../l10n_gen/app_strings.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

import '../player/transport_control_button.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// One TV in the picker. [playable] is the result for the file being played.
import '../components/app_button.dart';
import '../components/app_row.dart';
import '../components/tinted_surface.dart';
import '../focus/focusable_action.dart';

class CastTarget {
  const CastTarget({
    required this.id,
    required this.name,
    required this.playable,
    this.checking = false,
  });

  final String id;
  final String name;
  final bool playable;

  /// The file's facts or this TV's capability are not known yet; shown as
  /// "Checking…", not as incompatible.
  final bool checking;
}

class CastUiState {
  const CastUiState({
    this.targets = const <CastTarget>[],
    this.castingTo,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
    this.airPlayAvailable = false,
    this.airPlayPlayable = true,
  });

  final List<CastTarget> targets;

  /// The picker shows the system AirPlay route button (Apple platforms).
  final bool airPlayAvailable;

  /// False when AirPlay cannot play the current file; the row says so.
  final bool airPlayPlayable;

  /// Name of the TV being cast to, or null when not casting.
  final String? castingTo;
  final bool isPlaying;
  final Duration position;
  final Duration duration;

  /// Plain-language failure of the last cast attempt, if any.
  final String? error;
}

/// What the player needs from casting. The app implements it over the cast
/// package; `ui` never depends on that package.
abstract interface class CastUiController {
  ValueListenable<CastUiState> get state;
  Future<void> startDiscovery();
  Future<void> stopDiscovery();
  Future<void> cast(String targetId);
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> stop();
}

/// Platform view type the cast package's native plugin registers for the
/// system AirPlay route picker (`AirPlaySession.routePickerViewType`).
const String airPlayRoutePickerViewType = 'cast/airplay-route-picker';

/// The single cast button in the player's action row. The player opens
/// [CastPicker] from [onPress] in its anchored panel, like Subtitles/Audio.
class CastButton extends StatelessWidget {
  const CastButton({
    required this.onPress,
    this.focusNode,
    this.anchorLink,
    this.diameter = 44,
    this.iconSize = 20,
    this.touchTargetEnabled = true,
    super.key,
  });

  final VoidCallback onPress;
  final FocusNode? focusNode;
  final double diameter;
  final double iconSize;
  final bool touchTargetEnabled;

  final LayerLink? anchorLink;

  @override
  Widget build(BuildContext context) {
    final button = TransportControlButton(
      key: const ValueKey<String>('cast-button'),
      icon: PhosphorIconsRegular.screencast,
      semanticLabel: AppStrings.of(context).cast_title,
      diameter: diameter,
      iconSize: iconSize,
      focusNode: focusNode,
      touchTargetEnabled: touchTargetEnabled,
      onPress: onPress,
    );
    return anchorLink == null
        ? button
        : CompositedTransformTarget(link: anchorLink!, child: button);
  }
}

/// Device list shown in the player's anchored panel (which owns the frame,
/// Back/Escape and focus return). Discovery runs while it is open. A TV that
/// cannot play the file is shown disabled with the not-compatible text;
/// it is never castable. Rows are focusable in order; Enter selects.
class CastPicker extends StatefulWidget {
  const CastPicker({
    required this.controller,
    required this.dismiss,
    super.key,
  });

  final CastUiController controller;
  final VoidCallback dismiss;

  @override
  State<CastPicker> createState() => _CastPickerState();
}

class _CastPickerState extends State<CastPicker> {
  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.dismiss();
  }

  // The system AirPlay button starts casting without going through a row.
  void _closeWhenCasting() {
    if (widget.controller.state.value.castingTo != null) _close();
  }

  @override
  void initState() {
    super.initState();
    widget.controller.state.addListener(_closeWhenCasting);
    widget.controller.startDiscovery();
  }

  @override
  void dispose() {
    widget.controller.state.removeListener(_closeWhenCasting);
    widget.controller.stopDiscovery();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ValueListenableBuilder<CastUiState>(
      valueListenable: widget.controller.state,
      builder: (context, s, _) => ListView(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        children: [
          if (s.targets.isEmpty)
            AppText(
              AppStrings.of(context).cast_looking,
              style: tokens.typeStyles.body,
            ),
          AppRowGroup(
            children: [
              for (final (i, t) in s.targets.indexed)
                AppRow(
                  key: ValueKey<String>('cast-target-${t.id}'),
                  icon: PhosphorIconsRegular.television,
                  label: t.name,
                  descriptionWidget: t.checking || !t.playable
                      ? AppText(
                          t.checking
                              ? AppStrings.of(context).cast_checking
                              : AppStrings.of(context).cast_notCompatible,
                          style: tokens.typeStyles.caption.copyWith(
                            color: tokens.colors.textTertiary,
                          ),
                        )
                      : null,
                  autofocus: i == 0,
                  onActivate: () {
                    if (!t.playable) return;
                    widget.controller.cast(t.id);
                    _close();
                  },
                ),
              if (s.airPlayAvailable)
                AppRow(
                  key: const ValueKey<String>('cast-airplay-row'),
                  icon: PhosphorIconsRegular.airplay,
                  label: AppStrings.of(context).cast_airPlay,
                  descriptionWidget: s.airPlayPlayable
                      ? null
                      : AppText(
                          AppStrings.of(context).cast_notCompatible,
                          style: tokens.typeStyles.caption.copyWith(
                            color: tokens.colors.textTertiary,
                          ),
                        ),
                  trailing: s.airPlayPlayable
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: AppKitView(
                            viewType: airPlayRoutePickerViewType,
                          ),
                        )
                      : null,
                ),
            ],
          ),
          if (s.error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: RivuletSpacing.s8),
              child: AppText(
                error,
                style: tokens.typeStyles.caption.copyWith(
                  color: tokens.colors.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown in place of the player controls while casting: where it plays,
/// play/pause, seek, stop.
class CastingChrome extends StatelessWidget {
  const CastingChrome({required this.controller, super.key});

  final CastUiController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return ValueListenableBuilder<CastUiState>(
      valueListenable: controller.state,
      builder: (context, s, _) {
        final max = s.duration.inMilliseconds.toDouble();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TintedSurface.overMedia(
              key: const ValueKey<String>('casting-chrome'),
              radius: RivuletRadius.large,
              padding: const EdgeInsets.all(RivuletSpacing.s24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppText(
                    AppStrings.of(context).cast_castingTo(s.castingTo!),
                    style: tokens.typeStyles.title,
                    textAlign: TextAlign.center,
                  ),
                  FocusRing(
                    child: Slider(
                      value: s.position.inMilliseconds.toDouble().clamp(
                        0,
                        max > 0 ? max : 1,
                      ),
                      max: max > 0 ? max : 1,
                      onChanged: max > 0
                          ? (v) => controller.seek(
                              Duration(milliseconds: v.round()),
                            )
                          : null,
                    ),
                  ),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: RivuletSpacing.s16,
                    runSpacing: RivuletSpacing.s16,
                    children: [
                      AppButton.primary(
                        key: const ValueKey<String>('cast-play-pause'),
                        icon: s.isPlaying
                            ? PhosphorIconsRegular.pause
                            : PhosphorIconsRegular.play,
                        label: s.isPlaying
                            ? AppStrings.of(context).common_pause
                            : AppStrings.of(context).common_play,
                        onActivate: s.isPlaying
                            ? controller.pause
                            : controller.play,
                      ),
                      AppButton.secondary(
                        key: const ValueKey<String>('cast-stop'),
                        icon: PhosphorIconsRegular.stop,
                        label: AppStrings.of(context).cast_stop,
                        onActivate: controller.stop,
                      ),
                    ],
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
