import 'package:flutter/material.dart';

import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'glass_surface.dart';

/// Phone picker route (DESIGN_SPEC §5.2 and §8.6).
Future<T?> showAppSheet<T>(BuildContext context, WidgetBuilder builder) {
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return Navigator.of(context, rootNavigator: true).push<T>(
    _AppSheetRoute<T>(
      builder: builder,
      themes: InheritedTheme.capture(
        from: context,
        to: Navigator.of(context, rootNavigator: true).context,
      ),
      capabilities: AdaptiveBehavior.capabilitiesOf(context),
      reduceMotion: reduceMotion,
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      scrim: RivuletTokens.of(context).colors.scrimMenu,
    ),
  );
}

class _AppSheetRoute<T> extends PopupRoute<T> {
  _AppSheetRoute({
    required this.builder,
    required this.themes,
    required this.capabilities,
    required this.reduceMotion,
    required this.label,
    required this.scrim,
  });

  final WidgetBuilder builder;
  final CapturedThemes themes;
  final PlatformCapabilities capabilities;
  final bool reduceMotion;
  final String label;
  final Color scrim;

  @override
  Duration get transitionDuration =>
      reduceMotion ? RivuletMotion.press : RivuletMotion.panel;
  @override
  bool get barrierDismissible => true;
  @override
  Color get barrierColor => scrim;
  @override
  String get barrierLabel => label;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => themes.wrap(
    AdaptiveBehavior(
      capabilities: capabilities,
      child: Builder(builder: (context) => AppSheet(child: builder(context))),
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = animation.drive(CurveTween(curve: RivuletMotion.drawer));
    final faded = FadeTransition(opacity: curved, child: child);
    if (reduceMotion) return faded;
    return SlideTransition(
      position: curved.drive(
        Tween(begin: const Offset(0, 1), end: Offset.zero),
      ),
      child: faded,
    );
  }
}

class AppSheet extends StatefulWidget {
  const AppSheet({required this.child, super.key});

  final Widget child;

  static bool contains(BuildContext context) =>
      context.findAncestorWidgetOfExactType<AppSheet>() != null;

  @override
  State<AppSheet> createState() => _AppSheetState();
}

class _AppSheetState extends State<AppSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _settle() {
    _drag.animateTo(
      0,
      duration: effectiveDuration(context, RivuletMotion.panel),
      curve: RivuletMotion.drawer,
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.85;
    final colors = RivuletTokens.of(context).colors;
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: _drag,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, _drag.value), child: child),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => _drag.stop(),
          onVerticalDragUpdate: (details) =>
              _drag.value = (_drag.value + details.delta.dy).clamp(0, height),
          onVerticalDragCancel: _settle,
          onVerticalDragEnd: (details) {
            if (_drag.value > height * 0.3 ||
                details.velocity.pixelsPerSecond.dy > 700) {
              Navigator.of(context).pop();
            } else {
              _settle();
            }
          },
          child: RepaintBoundary(
            child: SizedBox(
              key: const ValueKey('app-sheet'),
              width: double.infinity,
              height: height,
              child: GlassSurface(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(RivuletRadius.large),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      children: [
                        SizedBox(
                          key: const ValueKey('app-sheet-handle'),
                          height: RivuletSizes.touchHitTarget,
                          child: Center(
                            child: Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colors.hairline.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(
                                  RivuletRadius.full,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(child: widget.child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
