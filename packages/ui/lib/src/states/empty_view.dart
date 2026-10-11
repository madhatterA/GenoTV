import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../accessibility/ui_accessibility.dart';
import '../components/app_button.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

/// Centred empty-state layout (DESIGN_SPEC §9.8): a 40 px icon, `headline`
/// title, `body` text and at most one primary action; [onSecondary] adds a
/// secondary button beside it.
class EmptyView extends StatelessWidget {
  const EmptyView({
    required this.headline,
    this.body,
    this.icon,
    this.action,
    this.onPrimary,
    this.primaryLabel,
    this.onSecondary,
    this.secondaryLabel,
    this.fullScreen = false,
    super.key,
  }) : assert(onPrimary == null || primaryLabel != null),
       assert(onSecondary == null || secondaryLabel != null);

  final String headline;
  final String? body;
  final IconData? icon;
  final Widget? action;
  final VoidCallback? onPrimary;
  final String? primaryLabel;
  final VoidCallback? onSecondary;
  final String? secondaryLabel;
  final bool fullScreen;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final opaque = UiAccessibility.opaqueOf(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ExcludeSemantics(
            child: Icon(
              icon ?? PhosphorIconsRegular.filmSlate,
              size: 40,
              color: opaque ? colors.textPrimary : colors.textTertiary,
            ),
          ),
          const SizedBox(height: RivuletSpacing.s16),
          Semantics(
            header: true,
            child: AppText(
              headline,
              style: tokens.typeStyles.headline,
              textAlign: TextAlign.center,
            ),
          ),
          if (body case final value?) ...<Widget>[
            const SizedBox(height: RivuletSpacing.s8),
            AppText(
              value,
              paragraph: true,
              textAlign: isFarsi(context) ? TextAlign.right : TextAlign.center,
              style: tokens.typeStyles.body.copyWith(
                color: opaque ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ],
          if (action case final Widget value?) ...<Widget>[
            const SizedBox(height: RivuletSpacing.s24),
            value,
          ],
          if (onPrimary != null || onSecondary != null) ...<Widget>[
            const SizedBox(height: RivuletSpacing.s24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: RivuletSpacing.s12,
              runSpacing: RivuletSpacing.s12,
              children: [
                if (onPrimary != null)
                  AppButton.primary(
                    label: primaryLabel!,
                    onActivate: onPrimary,
                  ),
                if (onSecondary != null)
                  AppButton.secondary(
                    label: secondaryLabel!,
                    onActivate: onSecondary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
    final child = Center(
      child: SingleChildScrollView(child: Center(child: content)),
    );
    return fullScreen ? SizedBox.expand(child: child) : child;
  }
}
