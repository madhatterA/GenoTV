import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../l10n_gen/app_strings.dart';
import '../platform/adaptive_behavior.dart';
import '../theme/rivulet_tokens.dart';
import 'app_dialog.dart';

/// The "?" sheet: every app and player shortcut, with the OS's own modifier.
Future<void> showShortcutSheet(BuildContext context) {
  final s = AppStrings.of(context);
  final mod = AdaptiveBehavior.usesCommandKey ? '⌘' : 'Ctrl';
  final app = <(String, String)>[
    ('$mod F  /  /', s.common_search),
    ('$mod ,', s.common_settings),
    ('$mod R', s.shortcuts_refresh),
    ('Esc  /  Backspace', s.shortcuts_back),
    ('M', s.shortcuts_menu),
    ('?', s.shortcuts_help),
  ];
  final player = <(String, String)>[
    ('Space', s.shortcuts_playPause),
    ('←  →', s.shortcuts_seek),
    ('↑  ↓', s.shortcuts_volume),
    ('M', s.shortcuts_mute),
    ('F', s.shortcuts_fullscreen),
    ('C', s.shortcuts_subtitles),
    ('J  L', s.shortcuts_jump),
    ('I', s.shortcuts_stats),
  ];
  return showAppDialog<void>(
    context: context,
    builder: (context) {
      final type = RivuletTokens.of(context).typeStyles;
      Widget group(String title, List<(String, String)> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText(title, style: type.title),
          const SizedBox(height: RivuletSpacing.s8),
          for (final (keys, label) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: RivuletSpacing.s4),
              child: Row(
                children: [
                  SizedBox(
                    width: RivuletSpacing.shortcutKeyColumn,
                    child: AppText(keys, style: type.label),
                  ),
                  Expanded(child: AppText(label, style: type.body)),
                ],
              ),
            ),
        ],
      );
      return Column(
        key: const ValueKey<String>('shortcut-sheet'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppText(s.shortcuts_title, style: type.title),
          const SizedBox(height: RivuletSpacing.s16),
          group(s.shortcuts_app, app),
          const SizedBox(height: RivuletSpacing.s16),
          group(s.shortcuts_player, player),
        ],
      );
    },
  );
}
