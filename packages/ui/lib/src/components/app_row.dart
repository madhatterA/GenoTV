import 'app_switch.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../focus/focusable_action.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'tinted_surface.dart';

/// One settings-style row (DESIGN_SPEC §9.6, §8.7): label and description on
/// the left; on the right a switch ([toggle]), a value with a caret ([value]),
/// or a caret alone ([caret]). Lives inside an [AppRowGroup].
class AppRow extends StatelessWidget {
  const AppRow({
    required this.label,
    this.description,
    this.descriptionWidget,
    this.icon,
    this.leading,
    this.trailing,
    this.toggle,
    this.value,
    this.caret = false,
    this.selected = false,
    this.onActivate,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final String? description;
  final Widget? descriptionWidget;
  final IconData? icon;

  /// A widget shown where [icon] goes (a source's quality badges).
  final Widget? leading;

  /// A widget shown right-aligned before the caret (a source's size and
  /// seeds, a provider's loader).
  final Widget? trailing;

  /// Non-null shows a switch in this state.
  final bool? toggle;

  /// Shown right-aligned in `textSecondary`; implies a caret.
  final String? value;
  final bool caret;

  /// Shows a trailing `check` in `accent`: the current choice of a choice
  /// dialog (DESIGN_SPEC §8.9).
  final bool selected;

  /// Null disables the row.
  final VoidCallback? onActivate;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final styles = tokens.typeStyles;
    final sizes = AdaptiveBehavior.sizesOf(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RivuletSpacing.s16,
        vertical: RivuletSpacing.s8,
      ),
      child: Row(
        children: <Widget>[
          // Leading + text share one Expanded so spare width never lands
          // after the trailing controls: they stay pinned to the right edge.
          Expanded(
            child: Row(
              children: <Widget>[
                if (leading != null) ...<Widget>[
                  leading!,
                  const SizedBox(width: RivuletSpacing.s12),
                ] else if (icon != null) ...<Widget>[
                  Icon(icon, size: sizes.iconGlyph, color: colors.textPrimary),
                  const SizedBox(width: RivuletSpacing.s12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      AppText(label, style: styles.label),
                      if (descriptionWidget != null)
                        descriptionWidget!
                      else if (description != null)
                        AppText(
                          description!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: styles.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null)
            Padding(
              padding: const EdgeInsets.only(left: RivuletSpacing.s12),
              child: trailing,
            ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(left: RivuletSpacing.s12),
              child: AppText(
                value!,
                style: styles.label.copyWith(color: colors.textSecondary),
              ),
            ),
          if (value != null || caret)
            Padding(
              padding: const EdgeInsets.only(left: RivuletSpacing.s8),
              child: Icon(
                PhosphorIconsRegular.caretRight,
                size: sizes.iconGlyph,
                color: colors.textTertiary,
              ),
            ),
          if (selected)
            Padding(
              padding: const EdgeInsets.only(left: RivuletSpacing.s8),
              child: Icon(
                PhosphorIconsRegular.check,
                size: sizes.iconGlyph,
                color: colors.accent,
              ),
            ),
          if (toggle != null) AppSwitch(value: toggle!),
        ],
      ),
    );
    if (onActivate == null) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: sizes.settingsRowMinHeight),
        child: content,
      );
    }
    return MergeSemantics(
      child: Semantics(
        selected: selected ? true : null,
        child: FocusableAction(
          onActivate: onActivate,
          focusNode: focusNode,
          autofocus: autofocus,
          semanticLabel: label,
          minSize: sizes.settingsRowMinHeight,
          focusRadius: BorderRadius.circular(RivuletRadius.medium),
          child: content,
        ),
      ),
    );
  }
}

/// Rows in one [TintedSurface] with `large` radius, separated by `hairline`
/// dividers inset 16 (DESIGN_SPEC §8.7, §9.6). [overMedia] is the darker fill
/// for a group placed over artwork (§3.2).
class AppRowGroup extends StatelessWidget {
  const AppRowGroup({
    required this.children,
    this.overMedia = false,
    super.key,
  });

  final List<Widget> children;
  final bool overMedia;

  @override
  Widget build(BuildContext context) {
    final hairline = RivuletTokens.of(context).colors.hairline;
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (var i = 0; i < children.length; i++) ...<Widget>[
          if (i > 0)
            Divider(
              height: 1,
              thickness: 1,
              indent: RivuletSpacing.s16,
              color: hairline,
            ),
          children[i],
        ],
      ],
    );
    return overMedia
        ? TintedSurface.overMedia(radius: RivuletRadius.large, child: column)
        : TintedSurface(radius: RivuletRadius.large, child: column);
  }
}
