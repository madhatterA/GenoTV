import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../l10n/app_text.dart';
import '../components/app_text_field.dart';
import '../l10n_gen/app_strings.dart';
import '../theme/rivulet_tokens.dart';

/// Saves a typed domain (null/empty = built-in). Returns an error message to
/// show, or null when saved.
typedef DomainSave = Future<String?> Function(String? raw);

/// Dialog showing [current] with a field for a new domain, Save, and Use
/// default (phase 14). Returns true when something was saved.
Future<bool?> showDomainDialog(
  BuildContext context, {
  required String title,
  required String current,
  required DomainSave save,
}) => showAppDialog<bool>(
  context: context,
  builder: (_) => _DomainDialog(title: title, current: current, save: save),
);

class _DomainDialog extends StatefulWidget {
  const _DomainDialog({
    required this.title,
    required this.current,
    required this.save,
    this.apiKey = false,
  });

  final bool apiKey;
  final String title;
  final String current;
  final DomainSave save;

  @override
  State<_DomainDialog> createState() => _DomainDialogState();
}

class _DomainDialogState extends State<_DomainDialog> {
  late final _controller = TextEditingController(text: widget.current);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply(String? raw) async {
    final error = await widget.save(raw);
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
    } else {
      setState(
        () => _error = error == 'domain.invalid'
            ? AppStrings.of(context).domain_invalid
            : error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final styles = RivuletTokens.of(context).typeStyles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(widget.title, style: styles.title),
        const SizedBox(height: RivuletSpacing.s16),
        AppText(
          widget.apiKey ? strings.providers_apiKey : strings.domain_label,
          style: styles.label,
        ),
        const SizedBox(height: RivuletSpacing.s8),
        AppTextField(
          fieldKey: ValueKey<String>(widget.apiKey ? 'api-key-field' : 'domain-field'),
          obscureText: widget.apiKey,
          controller: _controller,
          hint: widget.apiKey ? strings.providers_apiKey : strings.domain_hint,
          icon: widget.apiKey ? PhosphorIconsRegular.key : PhosphorIconsRegular.globe,
          autofocus: true,
          errorText: _error,
          onSubmitted: _apply,
        ),
        const SizedBox(height: RivuletSpacing.s24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            AppButton.secondary(
              key: const ValueKey<String>('domain-default'),
              label: strings.domain_useDefault,
              onActivate: () => _apply(null),
            ),
            const SizedBox(width: RivuletSpacing.s8),
            AppButton.primary(
              key: const ValueKey<String>('domain-save'),
              label: strings.domain_save,
              onActivate: () => _apply(_controller.text),
            ),
          ],
        ),
      ],
    );
  }
}

/// `••••abcd`: the key is never shown in full.
String maskedKey(String key) =>
    key.length <= 4 ? '••••' : '••••${key.substring(key.length - 4)}';

/// Like [showDomainDialog] for an API key: a masked field, Save, Use default
/// (clears the key). Returns true when something was saved.
Future<bool?> showApiKeyDialog(
  BuildContext context, {
  required String title,
  required String current,
  required DomainSave save,
}) => showAppDialog<bool>(
  context: context,
  builder: (_) => _DomainDialog(
    title: title,
    current: current,
    save: save,
    apiKey: true,
  ),
);
