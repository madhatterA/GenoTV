import '../../l10n/app_text.dart';
import '../../platform/adaptive_behavior.dart';

import 'package:flutter/material.dart';

class OverlayShell extends StatelessWidget {
  const OverlayShell({
    required this.title,
    required this.child,
    required this.onClose,
    super.key,
  });

  final String title;
  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: SizedBox(
      width: AdaptiveBehavior.isNarrowWidth(context) ? double.infinity : 420,
      child: Card(
        key: const ValueKey<String>('overlay-shell'),
        margin: EdgeInsets.zero,
        child: SafeArea(
          child: FocusScope(
            autofocus: true,
            child: Column(
              children: <Widget>[
                ListTile(
                  title: AppText(title),
                  trailing: IconButton(
                    key: const ValueKey<String>('close-player-overlay'),
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
