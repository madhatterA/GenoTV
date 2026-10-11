import '../l10n_gen/app_strings.dart';

import 'package:flutter/material.dart';

import '../components/app_dialog.dart';
import '../components/app_text_button.dart';
import '../components/app_text_field.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Plays the pasted or chosen link; returns an error message for the viewer,
/// or null when playback was started.
import '../components/app_button.dart';
import '../l10n/app_text.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';

import '../platform/form_factor.dart';

typedef PlayLinkHandler = Future<String?> Function(String link);

/// The "Torrent / https link" input with its Play and Import .torrent buttons.
/// Shared by the Play link page and the "Insert link…" dialog.
class PlayLinkInput extends StatefulWidget {
  const PlayLinkInput({
    required this.onPlay,
    required this.pickTorrent,
    super.key,
  });

  final PlayLinkHandler onPlay;

  /// Opens the file picker; returns the chosen .torrent path, or null if the
  /// viewer cancelled.
  final Future<String?> Function() pickTorrent;

  @override
  State<PlayLinkInput> createState() => _PlayLinkInputState();
}

class _PlayLinkInputState extends State<PlayLinkInput> {
  final _input = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _play(String link) async {
    if (_busy) return;
    setState(() => _busy = true);
    String? error;
    try {
      error = await widget.onPlay(link.trim());
    } catch (failure) {
      error = failure.toString();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _input.clear();
    });
  }

  Future<void> _import() async {
    final path = await widget.pickTorrent();
    if (path != null && mounted) await _play(path);
  }

  @override
  Widget build(BuildContext context) {
    final phone = AdaptiveBehavior.of(context).formFactor == FormFactor.phone;
    final field = AppTextField(
      controller: _input,
      autofocus: true,
      icon: PhosphorIconsRegular.link,
      hint: AppStrings.of(context).playlink_hint,
      errorText: _error,
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: _play,
    );
    final play = AppButton.primary(
      icon: PhosphorIconsRegular.play,
      label: AppStrings.of(context).common_play,
      expand: phone,
      onActivate: _busy ? null : () => _play(_input.text),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (phone) ...[
          field,
          const SizedBox(height: RivuletSpacing.s16),
          play,
        ] else
          Row(
            children: [
              Expanded(child: field),
              const SizedBox(width: RivuletSpacing.s16),
              play,
            ],
          ),
        const SizedBox(height: RivuletSpacing.s16),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton.secondary(
            icon: PhosphorIconsRegular.folderOpen,
            label: AppStrings.of(context).playlink_import,
            onActivate: _busy ? null : _import,
          ),
        ),
      ],
    );
  }
}

/// The "Insert link…" dialog. Returns true when [onPlay] accepted a link (the
/// dialog has closed itself), false/null when dismissed.
Future<bool?> showPlayLinkDialog(
  BuildContext context, {
  required PlayLinkHandler onPlay,
  required Future<String?> Function() pickTorrent,
}) => showAppDialog<bool>(
  context: context,
  builder: (dialogContext) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Semantics(
        header: true,
        child: AppText(
          AppStrings.of(dialogContext).playlink_insert,
          style: RivuletTokens.of(dialogContext).typeStyles.title,
        ),
      ),
      const SizedBox(height: RivuletSpacing.s16),
      PlayLinkInput(
        pickTorrent: pickTorrent,
        onPlay: (link) async {
          final error = await onPlay(link);
          if (error == null && dialogContext.mounted) {
            Navigator.pop(dialogContext, true);
          }
          return error;
        },
      ),
      const SizedBox(height: RivuletSpacing.s16),
      Align(
        alignment: Alignment.centerRight,
        child: AppTextButton(
          label: AppStrings.of(dialogContext).common_cancel,
          onActivate: () => Navigator.pop(dialogContext, false),
        ),
      ),
    ],
  ),
);
