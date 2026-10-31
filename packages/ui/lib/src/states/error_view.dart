import '../l10n_gen/app_strings.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../accessibility/ui_accessibility.dart';
import '../components/app_button.dart';
import '../components/app_text_button.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../platform/form_factor.dart';
import '../theme/rivulet_tokens.dart';

import 'failure_messages.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Icon by failure type: network, playback/decoder, anything else.
IconData errorIconFor(String code) {
  if (code.startsWith('transport.http.') ||
      code == 'playback.source.unreachable') {
    return PhosphorIconsRegular.cloudSlash;
  }
  if (code.startsWith('playback.') || code.startsWith('transport.')) {
    return PhosphorIconsRegular.filmSlate;
  }
  return PhosphorIconsRegular.warningCircle;
}

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
  final FocusNode _action = FocusNode(debugLabel: 'error-action');

  @override
  void initState() {
    super.initState();
    // autofocus is ignored when something else in the route already holds
    // focus (a back button, the loading view's node): take it explicitly so
    // the remote always lands on Retry/Back.
    if (!widget.hasUsableContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _action.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _action.dispose();
    super.dispose();
  }

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
    final tv = AdaptiveBehavior.formFactorOf(context) == FormFactor.tv;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(
          errorIconFor(widget.failure.code),
          key: const ValueKey<String>('error-icon'),
          size: 40,
          color: opaque ? colors.textPrimary : colors.decorative,
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
        // TV has no disclosure or clipboard: the code is a second line.
        if (tv)
          AppText(
            widget.failure.code,
            key: const ValueKey<String>('error-code-detail'),
            style: tokens.typeStyles.caption,
          )
        else ...<Widget>[
          AppTextButton(
            label: _showCode
                ? (labels?.hideCode ?? strings.state_hideCode)
                : (labels?.showCode ?? strings.state_showCode),
            onActivate: () => setState(() => _showCode = !_showCode),
          ),
          if (_showCode) ...<Widget>[
            AppText(
              widget.failure.code,
              key: const ValueKey<String>('error-code-detail'),
              style: tokens.typeStyles.caption,
            ),
            // Code and message only: never the URL or a token.
            AppTextButton(
              key: const ValueKey<String>('error-copy'),
              label: strings.state_copyDetails,
              onActivate: () => Clipboard.setData(
                ClipboardData(text: '${widget.failure.code}\n$message'),
              ),
            ),
          ],
        ],
        const SizedBox(height: RivuletSpacing.s16),
        if (widget.onRetry != null)
          AppButton.primary(
            focusNode: _action,
            autofocus: !widget.hasUsableContent,
            onActivate: widget.onRetry,
            icon: PhosphorIconsRegular.arrowsClockwise,
            label: (labels?.retry ?? strings.common_retry),
          ),
        if (widget.onRetry == null)
          AppButton.secondary(
            focusNode: _action,
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
