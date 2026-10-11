import 'package:flutter/widgets.dart';

import '../theme/rivulet_tokens.dart';

/// The visual switch; its containing AppRow owns activation and focus.
class AppSwitch extends StatefulWidget {
  const AppSwitch({required this.value, super.key});

  final bool value;

  @override
  State<AppSwitch> createState() => _AppSwitchState();
}

class _AppSwitchState extends State<AppSwitch>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: RivuletMotion.fast,
    value: widget.value ? 1 : 0,
  );
  late final _alignment = AlignmentTween(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  ).animate(_controller.drive(CurveTween(curve: RivuletMotion.easeOut)));

  @override
  void didUpdateWidget(covariant AppSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = widget.value ? 1 : 0;
      } else {
        widget.value ? _controller.forward() : _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = RivuletTokens.of(context).colors;
    return Semantics(
      toggled: widget.value,
      child: AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? RivuletMotion.press
            : RivuletMotion.fast,
        curve: RivuletMotion.easeOut,
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: widget.value ? colors.accent : colors.tintFillHover,
          borderRadius: BorderRadius.circular(RivuletRadius.full),
        ),
        child: AlignTransition(
          alignment: _alignment,
          child: SizedBox(
            width: 20,
            height: 20,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.value ? colors.onAccent : colors.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
