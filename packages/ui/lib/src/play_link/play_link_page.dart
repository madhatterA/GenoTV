import '../l10n_gen/app_strings.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../components/ambient_background.dart';
import '../components/app_text_button.dart';

import '../l10n/app_text.dart';
import '../navigation/page_back_button.dart';

import 'play_link_input.dart';

import 'package:phosphor_flutter/phosphor_flutter.dart';

/// The Play link sidebar page: one input, Play, Import .torrent, and the
/// Recent list. The app supplies playback and the file picker.
import '../components/app_button.dart';
import '../components/app_dialog.dart';
import '../components/app_icon_button.dart';
import '../components/app_row.dart';
import '../theme/rivulet_tokens.dart';
import '../navigation/page_top_inset.dart';

class PlayLinkPage extends StatefulWidget {
  const PlayLinkPage({
    required this.recents,
    required this.onPlay,
    required this.pickTorrent,
    super.key,
  });

  final RecentLinks recents;
  final PlayLinkHandler onPlay;

  /// Opens the file picker; returns the chosen .torrent path, or null if the
  /// viewer cancelled.
  final Future<String?> Function() pickTorrent;

  @override
  State<PlayLinkPage> createState() => _PlayLinkPageState();
}

class _PlayLinkPageState extends State<PlayLinkPage> {
  bool _busy = false;

  Future<String?> _play(String link) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      return await widget.onPlay(link);
    } finally {
      // Also shows the link just played in Recent.
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppText(
            AppStrings.of(context).playlink_clearConfirm,
            style: RivuletTokens.of(context).typeStyles.title,
          ),
          const SizedBox(height: RivuletSpacing.s24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton.secondary(
                label: AppStrings.of(context).common_cancel,
                onActivate: () => Navigator.pop(dialogContext, false),
              ),
              const SizedBox(width: RivuletSpacing.s12),
              AppButton.primary(
                label: AppStrings.of(context).common_clearAll,
                onActivate: () => Navigator.pop(dialogContext, true),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.recents.clear();
    if (mounted) setState(() {});
  }

  Future<void> _remove(String link) async {
    await widget.recents.remove(link);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final entries = widget.recents.entries;
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(pageTopInsetOf(context)),
          child: PageHeader(
            title: AppStrings.of(context).common_playLink,
            showBackButton: ModalRoute.of(context)?.canPop ?? false,
          ),
        ),
        body: FocusTraversalGroup(
          policy: ReadingOrderTraversalPolicy(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            children: [
              PlayLinkInput(onPlay: _play, pickTorrent: widget.pickTorrent),
              const SizedBox(height: RivuletSpacing.s32),
              AppText(
                AppStrings.of(context).playlink_recent,
                style: tokens.typeStyles.title,
              ),
              const SizedBox(height: RivuletSpacing.s8),
              if (entries.isEmpty)
                AppText(AppStrings.of(context).playlink_recentEmpty),
              if (entries.isNotEmpty)
                AppRowGroup(
                  children: [
                    for (final entry in entries)
                      Row(
                        key: ValueKey('recent-${entry.link}'),
                        children: [
                          Expanded(
                            child: AppRow(
                              icon: PhosphorIconsRegular.link,
                              label: entry.label,
                              descriptionWidget: _LinkCaption(link: entry.link),
                              onActivate: _busy
                                  ? null
                                  : () => _play(entry.link),
                            ),
                          ),
                          AppIconButton(
                            icon: PhosphorIconsRegular.x,
                            semanticLabel: AppStrings.of(context)
                                .playlink_remove(entry.label),
                            onActivate: () => _remove(entry.link),
                          ),
                          const SizedBox(width: RivuletSpacing.s16),
                        ],
                      ),
                  ],
                ),
              if (entries.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppTextButton(
                    label: AppStrings.of(context).common_clearAll,
                    onActivate: _clearAll,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkCaption extends StatelessWidget {
  const _LinkCaption({required this.link});
  final String link;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final style = tokens.typeStyles.caption.copyWith(
      color: tokens.colors.textTertiary,
    );
    return Semantics(
      label: link,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            );
            bool fits(String value) {
              painter.text = TextSpan(text: value, style: style);
              painter.layout();
              return painter.width <= constraints.maxWidth;
            }

            var display = link;
            if (!fits(link)) {
              final characters = link.characters.toList();
              var low = 0;
              var high = characters.length;
              while (low < high) {
                final count = (low + high + 1) ~/ 2;
                final candidate =
                    '${characters.take((count + 1) ~/ 2).join()}…${characters.skip(characters.length - count ~/ 2).join()}';
                if (fits(candidate)) {
                  low = count;
                  display = candidate;
                } else {
                  high = count - 1;
                }
              }
              if (low == 0) display = '…';
            }
            painter.dispose();
            return AppText.content(
              display,
              textDirection: TextDirection.ltr,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.clip,
            );
          },
        ),
      ),
    );
  }
}
