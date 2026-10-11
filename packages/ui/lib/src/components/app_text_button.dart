import 'package:flutter/material.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';

/// Accent text without a background (DESIGN_SPEC §9.4), e.g. "See all".
/// Underlined while the pointer hovers it.
class AppTextButton extends StatefulWidget {
  const AppTextButton({
    required this.label,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<AppTextButton> createState() => _AppTextButtonState();
}

class _AppTextButtonState extends State<AppTextButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final underline =
        _hovered && AdaptiveBehavior.of(context).inputMode == InputMode.pointer;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableAction(
        onActivate: widget.onActivate,
        enabled: widget.onActivate != null,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        semanticLabel: widget.label,
        minSize: AdaptiveBehavior.hitTargetOf(context),
        centered: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RivuletSpacing.s8),
          child: AppText(
            widget.label,
            style: tokens.typeStyles.label.copyWith(
              color: tokens.colors.accent,
              decoration: underline
                  ? TextDecoration.underline
                  : TextDecoration.none,
              decorationColor: tokens.colors.accent,
            ),
          ),
        ),
      ),
    );
  }
}
