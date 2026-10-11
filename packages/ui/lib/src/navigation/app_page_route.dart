import 'package:flutter/widgets.dart';

import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'page_entry_focus.dart';

/// The one page route of the app (DESIGN_SPEC §5.2 "Page push / pop"): fade +
/// 24 px slide from the right on phone and desktop, fade only on TV. Reduced
/// motion drops the slide and caps the fade at [RivuletMotion.press] (§5.3).
class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({super.settings, required this.builder, super.fullscreenDialog});

  final WidgetBuilder builder;

  /// The page's primary focus node, registered through [PageEntryFocus].
  final PageEntry entry = PageEntry();

  static const double _slideDistance = 24;

  bool get _tv {
    final context = navigator?.context;
    return context != null &&
        AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
  }

  bool get _reduced {
    final context = navigator?.context;
    return context != null && MediaQuery.disableAnimationsOf(context);
  }

  Duration _duration(Duration normal) {
    if (_tv) return Duration.zero;
    return _reduced ? RivuletMotion.press : normal;
  }

  @override
  Duration get transitionDuration => _duration(RivuletMotion.page);

  @override
  Duration get reverseTransitionDuration => _duration(RivuletMotion.base);

  @override
  bool get opaque => true;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PageEntryFocus(entry: entry, child: builder(context));

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (_tv) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: RivuletMotion.easeOut,
      reverseCurve: RivuletMotion.easeOut,
    );
    final fade = FadeTransition(opacity: curved, child: child);
    if (MediaQuery.disableAnimationsOf(context)) return fade;
    final width = MediaQuery.sizeOf(context).width;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset(_slideDistance / width, 0),
        end: Offset.zero,
      ).animate(curved),
      child: fade,
    );
  }
}

/// Pushes [route] and, once it is popped, puts focus back on the element that
/// opened it (DESIGN_SPEC §6.4 rule 9). A pushing widget whose node is gone
/// leaves focus to the shell.
Future<T?> pushAndRestoreFocus<T extends Object?>(
  NavigatorState navigator,
  Route<T> route,
) async {
  final opener = FocusManager.instance.primaryFocus;
  final result = await navigator.push<T>(route);
  if (opener != null && opener.context != null && opener.canRequestFocus) {
    opener.requestFocus();
  }
  return result;
}
