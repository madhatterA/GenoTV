import '../l10n_gen/app_strings.dart';

import 'package:flutter/widgets.dart';

/// Caller-owned copy; a localization lookup may supply this at the route root.
@immutable
class UiStateLabels {
  const UiStateLabels({
    this.loading = 'Loading',
    this.emptyTitle = 'Nothing here yet',
    this.emptyBody = 'No media is available.',
    this.errorTitle = 'Unable to continue',
    this.retry = 'Retry',
    this.back = 'Back',
    this.showCode = 'Show error code',
    this.hideCode = 'Hide error code',
    this.offline = "You're offline.",
    this.reconnecting = 'Reconnecting…',
    this.retryFailed = 'Still offline. Try again.',
    this.dismiss = 'Dismiss',
  });

  final String loading;
  final String emptyTitle;
  final String emptyBody;
  final String errorTitle;
  final String retry;
  final String back;
  final String showCode;
  final String hideCode;
  final String offline;
  final String reconnecting;
  final String retryFailed;
  final String dismiss;
}

/// Flutter exposes high contrast; the caller supplies reduced transparency.
class UiAccessibility extends InheritedWidget {
  const UiAccessibility({
    this.labels = const UiStateLabels(),
    this.reduceTransparency = false,
    required super.child,
    super.key,
  });

  final UiStateLabels labels;
  final bool reduceTransparency;

  static UiStateLabels labelsOf(BuildContext context) {
    final override = context
        .dependOnInheritedWidgetOfExactType<UiAccessibility>()
        ?.labels;
    if (override != null && !identical(override, const UiStateLabels())) {
      return override;
    }
    final strings = AppStrings.of(context);
    return UiStateLabels(
      loading: strings.state_loading,
      emptyTitle: strings.state_emptyTitle,
      emptyBody: strings.state_noMedia,
      errorTitle: strings.state_errorTitle,
      retry: strings.common_retry,
      back: strings.common_back,
      showCode: strings.state_showCode,
      hideCode: strings.state_hideCode,
      offline: strings.state_offlineWithPeriod,
      reconnecting: strings.state_reconnecting,
      retryFailed: strings.state_retryFailed,
      dismiss: strings.common_dismiss,
    );
  }

  static bool opaqueOf(BuildContext context) =>
      (MediaQuery.maybeOf(context)?.highContrast ?? false) ||
      (context
              .dependOnInheritedWidgetOfExactType<UiAccessibility>()
              ?.reduceTransparency ??
          false);

  @override
  bool updateShouldNotify(UiAccessibility oldWidget) =>
      labels != oldWidget.labels ||
      reduceTransparency != oldWidget.reduceTransparency;
}
