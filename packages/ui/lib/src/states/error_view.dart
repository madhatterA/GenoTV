import '../l10n_gen/app_strings.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../accessibility/ui_accessibility.dart';
import '../components/app_button.dart';
import '../components/app_text_button.dart';
import '../l10n/app_text.dart';
import '../theme/rivulet_tokens.dart';

import 'failure_messages.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

class ErrorView extends StatefulWidget {
  const ErrorView({
    required this.failure,
    this.onRetry,
    this.onBack,
    this.message,
    this.hasUsableContent = false,
    this.logger,
    this.fullScreen = false,
    super.key,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;
  final String? message;
  final bool hasUsableContent;
  final AppLogger? logger;
  final bool fullScreen;

  @override
  State<ErrorView> createState() => _ErrorViewState();
}

class _ErrorViewState extends State<ErrorView> {
  bool _showCode = false;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final labels = context
        .dependOnInheritedWidgetOfExactType<UiAccessibility>()
        ?.labels;
    final message =
        widget.message ??
        messageForFailure(
          widget.failure,
          strings: AppStrings.of(context),
          onUnknown: (code, failure) => widget.logger?.warn(
            'Unmapped UI failure code: $code',
            error: failure,
            stack: failure.stack,
          ),
        );
    final tokens = RivuletTokens.of(context);
    final colors = tokens.colors;
    final opaque = UiAccessibility.opaqueOf(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          PhosphorIconsRegular.cloudSlash,
          size: 40,
          color: opaque ? colors.textPrimary : colors.textTertiary,
        ),
        const SizedBox(height: RivuletSpacing.s16),
        AppText(
          (labels?.errorTitle ?? strings.state_errorTitle),
          style: tokens.typeStyles.headline,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RivuletSpacing.s8),
        AppText(
          message,
          paragraph: true,
          textAlign: isFarsi(context) ? TextAlign.right : TextAlign.center,
          style: tokens.typeStyles.body.copyWith(
            color: opaque ? colors.textPrimary : colors.textSecondary,
          ),
        ),
        AppTextButton(
          label: _showCode
              ? (labels?.hideCode ?? strings.state_hideCode)
              : (labels?.showCode ?? strings.state_showCode),
          onActivate: () => setState(() => _showCode = !_showCode),
        ),
        if (_showCode)
          AppText(
            widget.failure.code,
            key: const ValueKey<String>('error-code-detail'),
            style: tokens.typeStyles.caption,
          ),
        const SizedBox(height: RivuletSpacing.s16),
        if (widget.onRetry != null)
          AppButton.primary(
            autofocus: !widget.hasUsableContent,
            onActivate: widget.onRetry,
            icon: PhosphorIconsRegular.arrowsClockwise,
            label: (labels?.retry ?? strings.common_retry),
          ),
        if (widget.onRetry == null)
          AppButton.secondary(
            autofocus: !widget.hasUsableContent,
            onActivate: widget.onBack ?? () => Navigator.of(context).maybePop(),
            label: (labels?.back ?? strings.common_back),
          ),
      ],
    );
    // Material supplies the DefaultTextStyle/ink ancestors a route pushed
    // without a Scaffold (e.g. the player route) would otherwise lack.
    final child = Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RivuletSpacing.s24,
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
    return widget.fullScreen
        ? SizedBox.expand(child: Center(child: child))
        : child;
  }
}
