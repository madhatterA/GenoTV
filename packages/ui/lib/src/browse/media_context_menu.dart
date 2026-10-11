import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/glass_surface.dart';
import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

/// One context menu action.
class MediaContextAction {
  const MediaContextAction({
    required this.label,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
}

/// Focus-trapped media context menu (DESIGN_SPEC §6.3, §8.9): a glass popover
/// at [anchor] on desktop and phone, a centred dialog on TV or without an
/// anchor. A [FocusScope] traps directional/Tab focus inside while it is open;
/// Escape/Back or picking an action closes it and returns focus to
/// [returnFocusTo].
Future<void> showMediaContextMenu({
  required BuildContext context,
  required List<MediaContextAction> actions,
  FocusNode? returnFocusTo,
  Offset? anchor,
}) {
  final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
  final safePadding = MediaQuery.paddingOf(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    // DESIGN_SPEC §5.2 dialog/popover/context menu: scale 0.96 -> 1 + fade,
    // `base`, easeOut; TV and reduced motion fade only.
    transitionDuration: reduced ? RivuletMotion.press : RivuletMotion.base,
    transitionBuilder: (_, animation, _, child) {
      final curved = animation.drive(CurveTween(curve: RivuletMotion.easeOut));
      final faded = FadeTransition(opacity: curved, child: child);
      return tv || reduced
          ? faded
          : ScaleTransition(
              scale: curved.drive(Tween(begin: 0.96, end: 1.0)),
              child: faded,
            );
    },
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: anchor == null || tv
        ? RivuletTokens.of(context).colors.scrim
        : Colors.transparent,
    pageBuilder: (dialogContext, _, _) {
      final menu = Material(
        type: MaterialType.transparency,
        child: FocusScope(
          autofocus: true,
          child: Semantics(
            container: true,
            label: AppStrings.of(context).menu_mediaOptions,
            child: GlassSurface(
              radius: RivuletRadius.large,
              padding: const EdgeInsets.all(RivuletSpacing.s8),
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final action in actions)
                      _MenuRow(
                        action: action,
                        autofocus: action == actions.first,
                        onDone: () => Navigator.of(dialogContext).pop(),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return SafeArea(
        child: anchor == null || tv
            ? Center(child: menu)
            : CustomSingleChildLayout(
                delegate: _AnchoredMenuLayout(
                  anchor - Offset(safePadding.left, safePadding.top),
                ),
                child: menu,
              ),
      );
    },
  ).then((_) => returnFocusTo?.requestFocus());
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.action,
    required this.autofocus,
    required this.onDone,
  });

  final MediaContextAction action;
  final bool autofocus;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    return FocusableAction(
      autofocus: autofocus,
      semanticLabel: action.label,
      minSize: AdaptiveBehavior.hitTargetOf(context),
      focusRadius: BorderRadius.circular(RivuletRadius.medium),
      onActivate: () {
        onDone();
        action.onSelected();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: RivuletSpacing.s12),
        child: Row(
          children: <Widget>[
            if (action.icon != null) ...<Widget>[
              Icon(
                action.icon,
                size: AdaptiveBehavior.sizesOf(context).iconGlyph,
                color: tokens.colors.textPrimary,
              ),
              const SizedBox(width: RivuletSpacing.s12),
            ],
            Expanded(
              child: AppText(action.label, style: tokens.typeStyles.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// Puts the menu's top-left corner at the pointer, shifted back inside the
/// screen when it would overflow.
class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  const _AnchoredMenuLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.dx.clamp(0, size.width - childSize.width),
    anchor.dy.clamp(0, size.height - childSize.height),
  );

  @override
  bool shouldRelayout(_AnchoredMenuLayout old) => old.anchor != anchor;
}

/// The menu every poster offers on right-click or the context-menu key: one
/// "Details" action that opens the title.
Future<void> showMediaDetailsMenu({
  required BuildContext context,
  required Offset anchor,
  required VoidCallback onDetails,
}) => showMediaContextMenu(
  context: context,
  anchor: anchor,
  returnFocusTo: FocusManager.instance.primaryFocus,
  actions: <MediaContextAction>[
    MediaContextAction(
      label: AppStrings.of(context).common_details,
      icon: PhosphorIconsRegular.info,
      onSelected: onDetails,
    ),
  ],
);
