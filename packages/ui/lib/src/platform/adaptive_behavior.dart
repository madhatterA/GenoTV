import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../accessibility/ui_accessibility.dart';
import '../theme/rivulet_tokens.dart';
import 'form_factor.dart';

/// Input/output facts the composition root supplies (Part boundary: widgets
/// never read `dart:io` or `defaultTargetPlatform`). Defaults describe a
/// pointer + keyboard desktop; a touch phone or D-pad host passes its own.
@immutable

class PlatformCapabilities {
  const PlatformCapabilities({this.isTv = false});
  const PlatformCapabilities.touch() : this();
  const PlatformCapabilities.directionalPad() : this(isTv: true);
  final bool isTv;
}

/// Which input the user used last (DESIGN_SPEC §6.2).
enum InputMode { touch, pointer, keyboard, remote }

/// What a widget asks [AdaptiveBehavior.of] for.
@immutable
class DeviceProfile {
  const DeviceProfile({
    required this.formFactor,
    required this.inputMode,
    required this.blurAllowed,
    required this.capabilities,
  });

  final FormFactor formFactor;
  final InputMode inputMode;
  final bool blurAllowed;
  final PlatformCapabilities capabilities;
}

/// Touch only where a phone is the form factor; desktop starts as pointer and
/// becomes touch after a real touch PointerEvent (DESIGN_SPEC §6.2).
InputMode _initialInputMode(bool isTv, Size size) {
  final formFactor = resolveFormFactor(
    isTv: isTv,
    platform: defaultTargetPlatform,
    size: size,
  );
  return switch (formFactor) {
    FormFactor.tv => InputMode.remote,
    FormFactor.phone => InputMode.touch,
    _ => InputMode.pointer,
  };
}

/// The single place layout/input capability queries live. The composition
/// root passes the TV flag as `capabilities.isTv`; this widget
/// owns the live [InputMode].
class AdaptiveBehavior extends StatefulWidget {
  const AdaptiveBehavior({
    this.capabilities = const PlatformCapabilities(),
    required this.child,
    super.key,
  });

  final PlatformCapabilities capabilities;
  final Widget child;

  static PlatformCapabilities capabilitiesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Config>()?.capabilities ??
      const PlatformCapabilities();

  /// Form factor, live input mode and blur permission. Rebuilds the caller
  /// when the input mode, size or accessibility opacity changes.
  static DeviceProfile of(BuildContext context) {
    final capabilities = capabilitiesOf(context);
    final isTv = capabilities.isTv;
    final formFactor = resolveFormFactor(
      isTv: isTv,
      platform: defaultTargetPlatform,
      size: MediaQuery.sizeOf(context),
    );
    final notifier = context
        .dependOnInheritedWidgetOfExactType<_InputScope>()
        ?.notifier;
    return DeviceProfile(
      formFactor: formFactor,
      inputMode:
          notifier?.value ??
          _initialInputMode(isTv, MediaQuery.sizeOf(context)),
      blurAllowed:
          formFactor != FormFactor.tv && !UiAccessibility.opaqueOf(context),
      capabilities: capabilities,
    );
  }

  /// Every row of DESIGN_SPEC §4.5 for the current form factor and window.
  static RivuletSizes sizesOf(BuildContext context) =>
      RivuletSizes.of(of(context).formFactor, MediaQuery.sizeOf(context));

  /// Minimum hit target: 48 while the last input was touch, else §4.5's
  /// value; 0 on TV (focus, not hit targets).
  static double hitTargetOf(BuildContext context) {
    final profile = of(context);
    final sizes = RivuletSizes.of(
      profile.formFactor,
      MediaQuery.sizeOf(context),
    );
    if (profile.inputMode == InputMode.touch)
      return RivuletSizes.touchHitTarget;
    return sizes.minHitTarget ?? 0;
  }

  /// Phone-sized window (`shortestSide < 600`).
  static bool isCompactShortestSide(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide < 600;

  /// Landscape-phone height (`height < 500`).
  static bool isShortHeight(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 500;

  /// Full-width side panels below this width (`width < 700`).
  static bool isNarrowWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700;

  @override
  State<AdaptiveBehavior> createState() => _AdaptiveBehaviorState();
}

class _AdaptiveBehaviorState extends State<AdaptiveBehavior> {
  late final ValueNotifier<InputMode> _mode = ValueNotifier(
    _initialInputMode(
      widget.capabilities.isTv,
      MediaQuery.sizeOf(context),
    ),
  );

  bool get _isTv => widget.capabilities.isTv;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(AdaptiveBehavior oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isTv) _set(InputMode.remote);
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
    _mode.dispose();
    super.dispose();
  }

  void _set(InputMode mode) {
    if (_mode.value != mode) _mode.value = mode;
  }

  void _onPointer(PointerEvent event) {
    if (_isTv) return;
    if (event is! PointerDownEvent && event is! PointerHoverEvent) return;
    switch (event.kind) {
      case PointerDeviceKind.touch:
        _set(InputMode.touch);
      case PointerDeviceKind.mouse || PointerDeviceKind.trackpad:
        _set(InputMode.pointer);
      default:
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_isTv) {
      _set(InputMode.remote);
    } else if (_navigationKeys.contains(event.logicalKey)) {
      _set(InputMode.keyboard);
    }
    return false;
  }

  static final _navigationKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  };

  @override
  Widget build(BuildContext context) => _Config(
    capabilities: widget.capabilities,
    child: _InputScope(notifier: _mode, child: widget.child),
  );
}

class _Config extends InheritedWidget {
  const _Config({required this.capabilities, required super.child});

  final PlatformCapabilities capabilities;

  @override
  bool updateShouldNotify(_Config oldWidget) =>
      capabilities != oldWidget.capabilities;
}

class _InputScope extends InheritedNotifier<ValueNotifier<InputMode>> {
  const _InputScope({required super.notifier, required super.child});
}
