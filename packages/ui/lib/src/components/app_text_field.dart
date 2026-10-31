import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../focus/focusable_action.dart';
import '../focus/tv_text_entry.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
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
    this.busy = false,
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

  /// Shows a small spinner inside the field (a search is running).
  final bool busy;

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
    final ff = AdaptiveBehavior.formFactorOf(context);
    final glyph = RivuletControlSize.m.glyph(ff);
    final multiline = widget.maxLines != 1;
    final radius = multiline ? RivuletRadius.medium : RivuletRadius.full;
    final height = RivuletControlSize.m.height(ff);
    // Single line: the TextField itself spans the tier height (tap target).
    final body = tokens.typeStyles.body;
    final pad = ((height - body.fontSize! * (body.height ?? 1.2)) / 2).clamp(
      0.0,
      double.infinity,
    );
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
        textAlignVertical: TextAlignVertical.center,
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
          contentPadding: EdgeInsets.symmetric(
            vertical: multiline ? RivuletSpacing.s16 : pad,
          ),
        ),
      ),
    );
    final surface = TintedSurface(
      radius: radius,
      padding: const EdgeInsets.symmetric(horizontal: RivuletSpacing.s20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Row(
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(widget.icon, size: glyph, color: colors.textSecondary),
              const SizedBox(width: RivuletSpacing.s12),
            ],
            Expanded(
              child: multiline
                  ? field
                  : ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height),
                      child: field,
                    ),
            ),
            if (widget.busy)
              Padding(
                padding: const EdgeInsets.only(right: RivuletSpacing.s8),
                child: SizedBox.square(
                  key: const ValueKey('field-spinner'),
                  dimension: glyph - RivuletSpacing.s8,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.accent,
                  ),
                ),
              ),
            if (widget.controller.text.isNotEmpty && !multiline)
              FocusableAction(
                onActivate: _clear,
                semanticLabel: AppStrings.of(context).common_clear,
                centered: true,
                focusRadius: BorderRadius.circular(RivuletRadius.full),
                child: Icon(
                  PhosphorIconsRegular.x,
                  size: glyph,
                  color: colors.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
    final ring = CustomPaint(
      foregroundPainter: _node.hasFocus
          ? FocusRingPainter.of(
              context,
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
          padding: const EdgeInsets.only(
            top: RivuletSpacing.s4,
            left: RivuletSpacing.s20,
          ),
          child: AppText(
            widget.errorText!,
            style: tokens.typeStyles.caption.copyWith(color: colors.danger),
          ),
        ),
      ],
    );
  }
}
