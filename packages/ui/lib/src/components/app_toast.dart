import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'glass_surface.dart';

/// The toast pill (DESIGN_SPEC §9.11): `GlassSurface`, `full` radius, an icon
/// and one `label` line. Shown with [showAppToast].
class AppToast extends StatelessWidget {
  const AppToast({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String text;

  /// Optional action (Undo): a tap target on touch/pointer, never focusable.
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final sizes = AdaptiveBehavior.sizesOf(context);
    return Semantics(
      liveRegion: true,
      label: text,
      child: ExcludeSemantics(
        child: GlassSurface(
          radius: RivuletRadius.full,
          padding: const EdgeInsets.symmetric(
            horizontal: RivuletSpacing.s16,
            vertical: RivuletSpacing.s12,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: sizes.iconGlyph, color: tokens.colors.accent),
              const SizedBox(width: RivuletSpacing.s8),
              Flexible(
                child: AppText(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.typeStyles.label,
                ),
              ),
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(width: RivuletSpacing.s16),
                GestureDetector(
                  key: const ValueKey<String>('toast-action'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onAction,
                  child: AppText(
                    actionLabel!,
                    maxLines: 1,
                    style: tokens.typeStyles.label.copyWith(
                      color: tokens.colors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

VoidCallback? _replace;

/// Whether a toast is on screen right now.
bool get appToastActive => _replace != null;

/// Shows an [AppToast] bottom-centre on the nearest overlay, replacing any toast
/// already showing: slide up 16 px and fade in, fade out (TV: fade only),
/// `base`, `easeOut` (§5.2). Stays 3 s (TV and toasts with an action: 5 s).
/// The toast is announced to screen readers and never takes focus.
void showAppToast(
  BuildContext context,
  IconData icon,
  String text, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final tv = AdaptiveBehavior.formFactorOf(context) == FormFactor.tv;
  final visible =
      duration ??
      (tv || onAction != null ? RivuletMotion.toastLong : RivuletMotion.toast);
  _replace?.call();
  late final OverlayEntry entry;
  var removed = false;
  void done() {
    if (removed) return;
    removed = true;
    if (_replace == done) _replace = null;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _ToastHost(
      icon: icon,
      text: text,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              done();
              onAction();
            },
      visible: visible,
      onDone: done,
      onGone: () {
        if (_replace == done) _replace = null;
      },
    ),
  );
  _replace = done;
  overlay.insert(entry);
  if (tv) {
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        Directionality.of(context),
      ),
    );
  }
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.icon,
    required this.text,
    required this.visible,
    required this.onDone,
    required this.onGone,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration visible;
  final VoidCallback onDone;

  /// The host left the tree (removed, or its overlay was torn down).
  final VoidCallback onGone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  static const double _rise = 16;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: RivuletMotion.base,
  );
  late final CurvedAnimation _curved = CurvedAnimation(
    parent: _controller,
    curve: RivuletMotion.easeOut,
  );
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_timer != null) return;
    _controller.duration = effectiveDuration(context, RivuletMotion.base);
    _controller.forward();
    _timer = Timer(widget.visible, () async {
      await _controller.reverse();
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    widget.onGone();
    _timer?.cancel();
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = AdaptiveBehavior.formFactorOf(context) != FormFactor.tv;
    Widget toast = FadeTransition(
      opacity: _curved,
      child: AppToast(
        icon: widget.icon,
        text: widget.text,
        actionLabel: widget.actionLabel,
        onAction: widget.onAction,
      ),
    );
    if (slide) {
      toast = AnimatedBuilder(
        animation: _curved,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, _rise * (1 - _curved.value)),
          child: child,
        ),
        child: toast,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(RivuletSpacing.s24),
            child: IgnorePointer(
              ignoring: widget.onAction == null,
              child: toast,
            ),
          ),
        ),
      ),
    );
  }
}
