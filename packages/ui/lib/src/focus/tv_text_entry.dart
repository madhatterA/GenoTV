import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_shell.dart';
import '../platform/adaptive_behavior.dart';

/// Wraps a text field so that on TV (directional pad) it can be focused and
/// passed over without the on-screen keyboard opening and trapping the D-pad:
/// the field stays read-only until Select is pressed on it, which makes it
/// editable and opens the keyboard. Editing ends when focus leaves the field
/// the keyboard is dismissed, or Back is pressed (through the shell's
/// `BackDispatcher`, the one path Android's Back takes). Elsewhere the field is always editable.
import '../platform/form_factor.dart';

class TvTextEntry extends StatefulWidget {
  const TvTextEntry({required this.builder, super.key});

  /// Builds the text field; pass [readOnly] to its `readOnly`.
  final Widget Function(BuildContext context, bool readOnly) builder;

  @override
  State<TvTextEntry> createState() => _TvTextEntryState();
}

class _TvTextEntryState extends State<TvTextEntry> with WidgetsBindingObserver {
  bool _editing = false;
  bool _keyboardSeen = false;
  VoidCallback? _unregisterBack;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unregisterBack?.call();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    if (!_editing) return;
    final view = View.maybeOf(context);
    final open = (view?.viewInsets.bottom ?? 0) > 0;
    if (open) {
      _keyboardSeen = true;
    } else if (_keyboardSeen) {
      _stopEditing();
    }
  }

  bool _onBack() {
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _stopEditing();
    return true;
  }

  void _stopEditing() {
    _unregisterBack?.call();
    _unregisterBack = null;
    if (!_editing) return;
    setState(() {
      _editing = false;
      _keyboardSeen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tv = (AdaptiveBehavior.of(context).formFactor == FormFactor.tv);
    if (!tv) return widget.builder(context, false);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) _stopEditing();
      },
      onKeyEvent: (_, event) {
        final select =
            event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter;
        if (_editing || !select) return KeyEventResult.ignored;
        if (event is KeyUpEvent) {
          _unregisterBack = context
              .getInheritedWidgetOfExactType<AppShellScope>()
              ?.backDispatcher
              .register(_onBack);
          setState(() => _editing = true);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) =>
                SystemChannels.textInput.invokeMethod<void>('TextInput.show'),
          );
        }
        return KeyEventResult.handled;
      },
      child: widget.builder(context, !_editing),
    );
  }
}
