import 'package:flutter/material.dart';

import 'state_views.dart';

/// The loading placeholder: a [StateSkeleton] of the given [layout].
class LoadingView extends StatelessWidget {
  const LoadingView({
    this.fullScreen = false,
    this.label,
    this.layout = SkeletonLayout.posters,
    super.key,
  });
  final bool fullScreen;
  final String? label;
  final SkeletonLayout layout;
  @override
  Widget build(BuildContext context) {
    final child = StateSkeleton(label: label, layout: layout);
    return fullScreen ? SizedBox.expand(child: child) : child;
  }
}
