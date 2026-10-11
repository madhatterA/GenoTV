import '../l10n_gen/app_strings.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_icon_button.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import 'page_top_inset.dart';

/// Owner fix (round-a item 6): every pushed page (detail, series,
/// play-source — the player already has its own back button) needs a
/// visible top-left back control. Same look/placement as the player's own
/// back button (`player_screen.dart`: `IconButton(icon: arrow_back_rounded)`
/// over a `SafeArea`, top-left), generalized here so other pages don't each
/// reinvent it.
class PageBackButton extends StatelessWidget {
  const PageBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    // The shell floats its menu pill over the top-left of every page and
    // steps it right on pushed pages; the button sits in the slot it leaves,
    // vertically centred on the pill's real rect (DESIGN_SPEC §7.2).
    final pill = menuSlotOf(context);
    final button = AppIconButton(
      key: const ValueKey<String>('top-back'),
      glass: true,
      icon: PhosphorIconsRegular.arrowLeft,
      semanticLabel: AppStrings.of(context).common_back,
      onActivate: onPressed ?? () => Navigator.of(context).maybePop(),
    );
    final iconButton = AdaptiveBehavior.sizesOf(context).iconButton;
    return Padding(
      padding: EdgeInsets.only(
        left: (pill.left - menuBackSlotOf(context)).clamp(0, double.infinity),
        top: pill.top + (pill.height - iconButton) / 2,
      ),
      child: button,
    );
  }
}

/// Top row of a pushed page that has a title: the back button, then the
/// title placed to the right of the Home pill (never underneath it), centred
/// on the pill. Without a pill (compact layout) the title simply follows the
/// back button.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.showBackButton = true,
    this.actions = const [],
    super.key,
  });

  final String title;
  final bool showBackButton;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final pill = menuSlotOf(context);
    final content = Row(
      children: [
        Expanded(
          child: AppText(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        ...actions,
      ],
    );
    return SizedBox(
      height: pageTopInsetOf(context),
      child: Stack(
        children: [
          if (showBackButton) const PageBackButton(),
          Positioned(
            left: pill.right + 16,
            right: 16,
            top: pill.top,
            height: pill.height
                .clamp(AdaptiveBehavior.hitTargetOf(context), double.infinity)
                .toDouble(),
            child: content,
          ),
        ],
      ),
    );
  }
}

/// One header layout and background for catalogue and settings routes.
/// Shared across the root navigator and all nested tab navigators.
class NavigatorBackShortcuts extends StatelessWidget {
  const NavigatorBackShortcuts({required this.child, this.onPop, super.key});
  final Widget child;
  final VoidCallback? onPop;

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    includeSemantics: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      // Android remote Back also sends a pop route; only that path handles it.
      if (event.logicalKey != LogicalKeyboardKey.escape &&
          event.logicalKey != LogicalKeyboardKey.backspace) {
        return KeyEventResult.ignored;
      }
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null ||
          focused.findAncestorStateOfType<EditableTextState>() != null) {
        return KeyEventResult.ignored;
      }
      if (onPop != null) {
        onPop!();
        return KeyEventResult.handled;
      }
      final local = Navigator.maybeOf(focused);
      final root = Navigator.maybeOf(focused, rootNavigator: true);
      final navigator = local?.canPop() == true ? local : root;
      if (navigator?.canPop() != true) return KeyEventResult.ignored;
      navigator!.maybePop();
      return KeyEventResult.handled;
    },
    child: child,
  );
}

/// Escape, Backspace, and a mouse's dedicated back button all pop the
/// current route. Android's hardware Back uses the system pop route only.
/// Wrap a page's content in this once; it
/// never requests focus itself, so it doesn't disturb the page's own focus
/// traversal (`Focus.onKeyEvent` is consulted for any key event bubbling up
/// from a focused descendant regardless of who currently holds focus).
///
/// The mouse back button is not a [LogicalKeyboardKey] at all — Flutter
/// surfaces it as a pointer button ([kBackMouseButton]) on
/// [PointerDownEvent.buttons], so it needs its own [Listener] rather than
/// the keyboard `Focus.onKeyEvent` path.
class PopOnEscape extends StatelessWidget {
  const PopOnEscape({super.key, required this.child, this.onPop});
  final Widget child;
  final VoidCallback? onPop;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons & kBackMouseButton != 0) {
        if (onPop != null) {
          onPop!();
        } else {
          Navigator.of(context).maybePop();
        }
      }
    },
    child: NavigatorBackShortcuts(onPop: onPop, child: child),
  );
}
