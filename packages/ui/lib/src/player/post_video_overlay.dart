import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';

import 'dart:async';
import 'dart:math' as math;

import '../platform/adaptive_behavior.dart';

import 'package:flutter/material.dart';

import '../theme/rivulet_tokens.dart';

import 'package:flutter/services.dart';

/// Controls shown after playback completes while the existing video surface
/// stays mounted in a smaller window behind this overlay.
import '../components/tinted_surface.dart';
import '../components/orb_loader.dart';

class PostVideoOverlay extends StatefulWidget {
  const PostVideoOverlay({
    required this.nextTitle,
    required this.onPlayNext,
    required this.onDismiss,
    this.nextArtwork,
    this.nextDescription,
    this.onOpenShow,
    this.onOpenSeason,
    this.countdown = const Duration(seconds: 10),
    this.countdownPaused = false,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    super.key,
  });

  final String nextTitle;
  final ImageProvider? nextArtwork;
  final String? nextDescription;
  final VoidCallback onPlayNext;
  final VoidCallback onDismiss;
  final VoidCallback? onOpenShow;
  final VoidCallback? onOpenSeason;
  final Duration countdown;
  final bool countdownPaused;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  @override
  State<PostVideoOverlay> createState() => PostVideoOverlayState();
}

class PostVideoOverlayState extends State<PostVideoOverlay>
    with WidgetsBindingObserver {
  Timer? _timer;
  late int _remaining = widget.countdown.inSeconds;
  bool _paused = false;
  bool _cancelled = false;
  bool _played = false;
  bool _appPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(seconds: 1), _tick);
  }

  @override
  void didUpdateWidget(covariant PostVideoOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nextTitle != widget.nextTitle) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), _tick);
      _remaining = widget.countdown.inSeconds;
      _paused = false;
      _cancelled = false;
      _played = false;
    }
  }

  void _tick(Timer timer) {
    if (_paused ||
        _appPaused ||
        widget.countdownPaused ||
        widget.isLoading ||
        widget.errorMessage != null ||
        _played) {
      return;
    }
    if (_remaining <= 1) {
      setState(() => _remaining = 0);
      _playNext();
    } else {
      setState(() => _remaining--);
    }
  }

  void _playNext() {
    if (_played) return;
    _played = true;
    _timer?.cancel();
    widget.onPlayNext();
  }

  void _cancelCountdown() {
    _timer?.cancel();
    setState(() => _cancelled = true);
  }

  void handleBack() {
    if (!_cancelled && !_played && _remaining > 0) {
      _cancelCountdown();
      return;
    }
    widget.onDismiss();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appPaused = state != AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = AdaptiveBehavior.isShortHeight(context);
    final colors = RivuletTokens.of(context).colors;
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 350 : 540),
      child: TintedSurface.overMedia(
        radius: RivuletRadius.large,
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppText(
              AppStrings.of(context).player_upNextUpper,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.textSecondary, letterSpacing: 2),
            ),
            SizedBox(height: compact ? 8 : 16),
            if (widget.nextArtwork != null && !compact)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: widget.nextArtwork!,
                  height: compact ? 110 : 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            SizedBox(height: compact ? 8 : 16),
            AppText.content(
              widget.nextTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: compact ? 24 : 32,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.isLoading) ...<Widget>[
              const SizedBox(height: 12),
              const OrbLoader.medium(),
            ],
            if (widget.errorMessage case final message?) ...<Widget>[
              const SizedBox(height: 12),
              AppText(message, style: TextStyle(color: colors.textSecondary)),
              if (widget.onRetry != null)
                TextButton(
                  onPressed: widget.onRetry,
                  child: AppText(AppStrings.of(context).common_retry),
                ),
            ],
            if (widget.nextDescription case final description?) ...<Widget>[
              const SizedBox(height: 8),
              AppText.content(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.textSecondary, fontSize: 16),
              ),
            ],
            SizedBox(height: compact ? 12 : 24),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                ElevatedButton.icon(
                  autofocus: true,
                  key: const ValueKey<String>('post-video-play-next'),
                  onPressed: widget.isLoading || widget.errorMessage != null
                      ? null
                      : _playNext,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: AppText(AppStrings.of(context).player_playNext),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      CustomPaint(
                        size: const Size.square(48),
                        painter: _CountdownArc(
                          fraction: widget.countdown.inSeconds > 0
                              ? _remaining / widget.countdown.inSeconds
                              : 0,
                          color: RivuletTokens.of(context).colors.accent,
                          track: RivuletTokens.of(context).colors.hairline,
                        ),
                      ),
                      AppText(
                        '$_remaining',
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey<String>('countdown-toggle'),
                  tooltip: _cancelled
                      ? AppStrings.of(context).player_countdownCanceled
                      : _paused
                      ? AppStrings.of(context).player_resumeCountdown
                      : AppStrings.of(context).player_pauseCountdown,
                  onPressed: _cancelled
                      ? null
                      : () => setState(() => _paused = !_paused),
                  icon: Icon(_paused ? Icons.play_arrow : Icons.pause),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton(
                  onPressed: _cancelled ? null : _cancelCountdown,
                  child: AppText(AppStrings.of(context).player_cancelCountdown),
                ),
                TextButton(
                  onPressed: widget.onDismiss,
                  child: AppText(AppStrings.of(context).common_dismiss),
                ),
                if (widget.onOpenSeason != null)
                  TextButton(
                    onPressed: () {
                      _timer?.cancel();
                      widget.onOpenSeason!();
                    },
                    child: AppText(AppStrings.of(context).player_season),
                  ),
                if (widget.onOpenShow != null)
                  TextButton(
                    onPressed: () {
                      _timer?.cancel();
                      widget.onOpenShow!();
                    },
                    child: AppText(AppStrings.of(context).player_show),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    return FocusScope(
      autofocus: true,
      child: Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
                  event.logicalKey == LogicalKeyboardKey.goBack)) {
            handleBack();
            return KeyEventResult.handled;
          }
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space &&
              !_cancelled) {
            setState(() => _paused = !_paused);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: ColoredBox(
          color: colors.scrim,
          child: SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.all(compact ? 12 : 64),
                child: SingleChildScrollView(child: card),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Determinate countdown ring: a [track] circle and an arc of [fraction] of
/// a turn in [color], starting at the top.
class _CountdownArc extends CustomPainter {
  const _CountdownArc({
    required this.fraction,
    required this.color,
    required this.track,
  });

  static const double _stroke = 4;

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = track);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      paint..color = color,
    );
  }

  @override
  bool shouldRepaint(_CountdownArc old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
