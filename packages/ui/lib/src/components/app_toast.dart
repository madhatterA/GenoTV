import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'glass_surface.dart';

/// The toast pill (DESIGN_SPEC §9.11): `GlassSurface`, `full` radius, an icon
/// and one `label` line. Shown with [showAppToast].
class AppToast extends StatelessWidget {
  const AppToast({required this.icon, required this.text, super.key});

  final IconData icon;
  final String text;

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
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows an [AppToast] bottom-centre on the nearest overlay for 3 s: slide up
/// 16 px and fade in, fade out (TV: fade only), `base`, `easeOut` (§5.2).
void showAppToast(BuildContext context, IconData icon, String text) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) =>
        _ToastHost(icon: icon, text: text, onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({
    required this.icon,
    required this.text,
    required this.onDone,
  });

  final IconData icon;
  final String text;
  final VoidCallback onDone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost>
    with SingleTickerProviderStateMixin {
  static const Duration _visible = Duration(seconds: 3);
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
    _timer = Timer(_visible, () async {
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slide = AdaptiveBehavior.of(context).formFactor != FormFactor.tv;
    Widget toast = FadeTransition(
      opacity: _curved,
      child: AppToast(icon: widget.icon, text: widget.text),
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
            child: IgnorePointer(child: toast),
          ),
        ),
      ),
    );
  }
}
