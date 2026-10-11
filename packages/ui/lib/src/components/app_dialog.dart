import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accessibility/ui_accessibility.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';
import 'app_row.dart';
import 'glass_surface.dart';

Future<T?> showAppChoiceDialog<T>({
  required BuildContext context,
  required String title,
  required Map<T, String> options,
  required T current,
}) => showAppDialog<T>(
  context: context,
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AppText(title, style: RivuletTokens.of(context).typeStyles.title),
      const SizedBox(height: RivuletSpacing.s24),
      for (final option in options.entries)
        AppRow(
          key: ValueKey<String>('choice-option-${option.key}'),
          label: option.value,
          selected: option.key == current,
          autofocus: option.key == current,
          onActivate: () => Navigator.of(context).pop(option.key),
        ),
    ],
  ),
);

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final profile = AdaptiveBehavior.of(context);
  final opaque = UiAccessibility.opaqueOf(context);
  final reduced = MediaQuery.disableAnimationsOf(context);
  final maxWidth = AdaptiveBehavior.sizesOf(context).dialogMaxWidth;
  final focus = FocusManager.instance.primaryFocus;
  final result = await showGeneralDialog<T>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: reduced ? RivuletMotion.press : RivuletMotion.base,
    pageBuilder: (routeContext, _, _) => AdaptiveBehavior(
      capabilities: profile.capabilities,
      child: UiAccessibility(
        reduceTransparency: opaque,
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            SingleActivator(LogicalKeyboardKey.goBack): DismissIntent(),
          },
          child: Actions(
            actions: {
              DismissIntent: CallbackAction<DismissIntent>(
                onInvoke: (_) => Navigator.of(routeContext).pop(),
              ),
            },
            child: _DialogFocusScope(
              child: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(RivuletSpacing.s16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Material(
                        type: MaterialType.transparency,
                        child: GlassSurface(
                          radius: RivuletRadius.large,
                          padding: const EdgeInsets.all(RivuletSpacing.s24),
                          child: FocusTraversalGroup(
                            child: SingleChildScrollView(
                              child: Builder(builder: builder),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (_, animation, _, child) {
      final curved = animation.drive(CurveTween(curve: RivuletMotion.easeOut));
      final faded = FadeTransition(opacity: curved, child: child);
      return profile.formFactor == FormFactor.tv || reduced
          ? faded
          : ScaleTransition(
              scale: curved.drive(Tween(begin: 0.96, end: 1.0)),
              child: faded,
            );
    },
  );
  if (focus?.context != null) focus!.requestFocus();
  return result;
}

class _DialogFocusScope extends StatefulWidget {
  const _DialogFocusScope({required this.child});
  final Widget child;

  @override
  State<_DialogFocusScope> createState() => _DialogFocusScopeState();
}

class _DialogFocusScopeState extends State<_DialogFocusScope> {
  final _node = FocusScopeNode(
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _node, child: widget.child);
}
