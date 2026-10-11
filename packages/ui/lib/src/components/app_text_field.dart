import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../focus/focusable_action.dart';
import '../focus/tv_text_entry.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'tinted_surface.dart';

/// The one text field (DESIGN_SPEC §9.14): a `TintedSurface` capsule, height 52
/// (TV 60), optional leading icon, a clear `x` while it holds text, and a 2 px
/// `accent` ring while focused in any input mode (typing needs to see it). On
/// TV it keeps `TvTextEntry`'s read-only-until-Select behaviour. A multi-line
/// field ([maxLines] other than 1) uses the `medium` radius and grows.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    this.focusNode,
    this.hint,
    this.icon,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.autofocus = false,
    this.fieldKey,
    this.minLines,
    this.maxLines = 1,
    this.errorText,
    this.obscureText = false,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hint;
  final IconData? icon;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TapRegionCallback? onTapOutside;
  final bool autofocus;

  /// Key of the inner `TextField`.
  final Key? fieldKey;
  final int? minLines;
  final int maxLines;
  final String? errorText;

  /// Hides the typed text (passwords).
  final bool obscureText;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final bool _ownsNode = widget.focusNode == null;
  late final FocusNode _node = widget.focusNode ?? FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _node.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _node.removeListener(_changed);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
    _node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final tv = AdaptiveBehavior.of(context).formFactor == FormFactor.tv;
    final multiline = widget.maxLines != 1;
    final radius = multiline ? RivuletRadius.medium : RivuletRadius.full;
    final height = tv ? 60.0 : 52.0;
    final field = TvTextEntry(
      builder: (_, tvReadOnly) => TextField(
        key: widget.fieldKey,
        readOnly: tvReadOnly,
        controller: widget.controller,
        focusNode: _node,
        autofocus: widget.autofocus,
        minLines: widget.minLines,
        maxLines: widget.maxLines,
        obscureText: widget.obscureText,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        onTapOutside: widget.onTapOutside,
        style: tokens.typeStyles.body,
        cursorColor: colors.textPrimary,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: tokens.typeStyles.body.copyWith(
            color: colors.textTertiary,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
    final surface = TintedSurface(
      radius: radius,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height - 2),
        child: Row(
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(widget.icon, size: 20, color: colors.textSecondary),
              const SizedBox(width: RivuletSpacing.s12),
            ],
            Expanded(child: field),
            if (widget.controller.text.isNotEmpty && !multiline)
              FocusableAction(
                onActivate: _clear,
                semanticLabel: AppStrings.of(context).common_clear,
                centered: true,
                focusRadius: BorderRadius.circular(RivuletRadius.full),
                child: Icon(
                  PhosphorIconsRegular.x,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
    final ring = CustomPaint(
      foregroundPainter: _node.hasFocus
          ? FocusRingPainter(
              radius: BorderRadius.circular(radius),
              color: colors.accent,
            )
          : null,
      child: surface,
    );
    if (widget.errorText == null) return ring;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ring,
        Padding(
          padding: const EdgeInsets.only(top: RivuletSpacing.s4, left: 20),
          child: AppText(
            widget.errorText!,
            style: tokens.typeStyles.caption.copyWith(color: colors.danger),
          ),
        ),
      ],
    );
  }
}
