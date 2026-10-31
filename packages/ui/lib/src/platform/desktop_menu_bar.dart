import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_gen/app_strings.dart';

/// The macOS menu bar (App > Settings, View > Search / Refresh / Full Screen,
/// Help > Keyboard Shortcuts). Built on macOS only; every other platform gets
/// [child] untouched.
class DesktopMenuBar extends StatelessWidget {
  const DesktopMenuBar({
    required this.onSearch,
    required this.onSettings,
    required this.onRefresh,
    required this.onShortcuts,
    required this.child,
    super.key,
  });

  final VoidCallback onSearch;
  final VoidCallback onSettings;
  final VoidCallback onRefresh;
  final VoidCallback onShortcuts;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.macOS) return child;
    final s = AppStrings.of(context);
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'GenoTV',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: '${s.common_settings}…',
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelected: onSettings,
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(
          label: s.menuBar_view,
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: s.common_search,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
              ),
              onSelected: onSearch,
            ),
            PlatformMenuItem(
              label: s.shortcuts_refresh,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyR,
                meta: true,
              ),
              onSelected: onRefresh,
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.toggleFullScreen,
            ),
          ],
        ),
        PlatformMenu(
          label: s.menuBar_help,
          menus: <PlatformMenuItem>[
            PlatformMenuItem(label: s.shortcuts_title, onSelected: onShortcuts),
          ],
        ),
      ],
      child: child,
    );
  }
}
