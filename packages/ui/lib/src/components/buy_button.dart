import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../l10n_gen/app_strings.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import 'app_chip.dart';
import 'app_icon_button.dart';

/// The provider Buy button: a labelled chip, or on phones a cart icon button
/// (the label stays as tooltip and semantics label).
class BuyButton extends StatelessWidget {
  const BuyButton({required this.onActivate, this.signUp = false, super.key});

  /// Free-account services (subtitles): "Sign Up" with a user-plus icon.
  final bool signUp;

  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final label = signUp ? strings.providers_signUp : strings.providers_buy;
    final icon = signUp
        ? PhosphorIconsRegular.userPlus
        : PhosphorIconsRegular.shoppingCart;
    return AdaptiveBehavior.formFactorOf(context) == FormFactor.phone
        ? AppIconButton(
            icon: icon,
            semanticLabel: label,
            onActivate: onActivate,
          )
        : AppChip(icon: icon, label: label, onActivate: onActivate);
  }
}
