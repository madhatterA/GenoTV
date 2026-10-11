import 'package:flutter/material.dart';

import '../components/app_dialog.dart';
import '../components/app_row.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

/// One row of a [showChoiceDialog].
typedef Choice<T> = ({T value, String label});

/// The choice dialog (DESIGN_SPEC §8.9): a `GlassSurface` with the title and
/// one [AppRow] per option; the current one shows a `check` in `accent` and
/// takes the first focus. Picking a row closes the dialog with its value.
Future<T?> showChoiceDialog<T>(
  BuildContext context, {
  required String title,
  required List<Choice<T>> options,
  required T? current,
}) => showAppDialog<T>(
  context: context,
  builder: (dialogContext) => ChoiceDialogShell(
    title: title,
    child: FocusTraversalGroup(
      child: AppRowGroup(
        children: <Widget>[
          for (var i = 0; i < options.length; i++)
            AppRow(
              key: ValueKey<String>('choice-option-$i'),
              label: options[i].label,
              selected: options[i].value == current,
              autofocus: options[i].value == current,
              onActivate: () =>
                  Navigator.of(dialogContext).pop(options[i].value),
            ),
        ],
      ),
    ),
  ),
);

/// The heading + body shared by every browse dialog; the surface, width and
/// padding come from [showAppDialog].
class ChoiceDialogShell extends StatelessWidget {
  const ChoiceDialogShell({
    required this.title,
    required this.child,
    super.key,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final styles = RivuletTokens.of(context).typeStyles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Semantics(header: true, child: AppText(title, style: styles.title)),
        const SizedBox(height: RivuletSpacing.s16),
        child,
      ],
    );
  }
}
