// ignore_for_file: prefer_initializing_formals

import 'package:contracts/contracts.dart';

import '../channel/platform_channel.dart';

final class DisplayModeLeaseImpl implements DisplayModeLease {
  DisplayModeLeaseImpl({
    required this.channel,
    required this.previous,
    required this.restoreArguments,
    void Function(DisplayModeLeaseImpl)? onReleased,
  }) : _onReleased = onReleased;

  final PlatformChannel channel;
  final DisplayMode previous;
  final Object? restoreArguments;
  final void Function(DisplayModeLeaseImpl)? _onReleased;
  bool _released = false;

  bool get isReleased => _released;

  @override
  Future<void> release() async {
    if (_released) return;
    try {
      final response = await channel.invoke(
        PlatformMethods.displayRestore,
        restoreArguments,
      );
      if (response is Map && response["supported"] == false) {
        throw StateError(
          response["reason"]?.toString() ?? "display mode restore was rejected",
        );
      }
      _released = true;
      _onReleased?.call(this);
    } catch (error, stack) {
      throw PlatformFailure.displaySwitchFailed(cause: error, stack: stack);
    }
  }
}
