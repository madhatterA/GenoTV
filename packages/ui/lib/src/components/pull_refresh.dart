import 'package:flutter/material.dart';

import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

/// Pull-to-refresh on phones only (DESIGN_SPEC §8.1); other form factors pass
/// the child through. [onRefresh] is the page's own reload.
class PullRefresh extends StatelessWidget {
  const PullRefresh({required this.onRefresh, required this.child, super.key});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      AdaptiveBehavior.formFactorOf(context) == FormFactor.phone
      ? RefreshIndicator(
          color: RivuletTokens.of(context).colors.accent,
          onRefresh: onRefresh,
          // A short page must still be pullable.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context)
                .copyWith(physics: const AlwaysScrollableScrollPhysics()),
            child: child,
          ),
        )
      : child;
}
