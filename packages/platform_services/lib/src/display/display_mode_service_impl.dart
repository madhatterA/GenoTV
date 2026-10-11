import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

import '../channel/platform_channel.dart';
import 'display_mode_lease_impl.dart';
import 'mode_matcher.dart';

final class DisplayModeServiceImpl
    with WidgetsBindingObserver
    implements DisplayModeService {
  DisplayModeServiceImpl({required this.channel});

  final PlatformChannel channel;
  final Set<DisplayModeLeaseImpl> _leases = {};
  List<DisplayMode>? _lastModes;
  String? _diagnostic;
  String? _matchDiagnostic;

  String? get diagnostic => _diagnostic;

  /// Requested fps, chosen/previous mode and approximation reason of the last matchFor.
  String? get matchDiagnostic => _matchDiagnostic;

  @override
  Future<List<DisplayMode>> availableModes() async {
    try {
      final raw = asMap(await channel.invoke(PlatformMethods.displayModes));
      final values = raw['modes'] is List ? raw['modes'] as List : const [];
      final modes = _deduplicate(
        values.map(_parse).whereType<DisplayMode>().toList(),
      );
      if (modes.isEmpty &&
          boolValue(raw['supported'], fallback: true) == false) {
        _diagnostic =
            stringValue(raw['reason']) ?? 'platform.unsupported: display modes';
      } else {
        _diagnostic = null;
      }
      _lastModes = modes;
      return List.unmodifiable(modes);
    } catch (error) {
      _diagnostic = 'platform.unsupported: ${error.runtimeType}';
      return const [];
    }
  }

  @override
  Future<DisplayModeLease?> matchFor({
    required double contentFps,
    int? width,
    int? height,
  }) async {
    final modes = _lastModes ?? await availableModes();
    final current = modes.where((mode) => mode.isCurrent).firstOrNull;
    final match = ModeMatcher.match(
      contentFps: contentFps,
      modes: modes,
      current: current,
      width: width,
      height: height,
    );
    if (match == null || current == null) {
      _matchDiagnostic =
          'display.match: requested ${contentFps}Hz, skipped, '
          'previous ${_describe(current)}, reason: '
          '${current == null ? 'no current mode' : 'current mode already satisfies or no acceptable mode'}';
      return null;
    }
    try {
      final applied = asMap(
        await channel.invoke(
          PlatformMethods.displayApply,
          _modePayload(match.mode),
        ),
      );
      if (applied['supported'] == false) {
        throw StateError(
          stringValue(applied['reason']) ?? 'display mode apply was rejected',
        );
      }
      final lease = DisplayModeLeaseImpl(
        channel: channel,
        previous: current,
        restoreArguments: _modePayload(current),
        onReleased: _leases.remove,
      );
      _leases.add(lease);
      WidgetsFlutterBinding.ensureInitialized().addObserver(this);
      _matchDiagnostic =
          'display.match: requested ${contentFps}Hz, chosen ${_describe(match.mode)}, '
          'previous ${_describe(current)}, switched: ${applied['switched']}'
          '${match.reason == null ? '' : ', reason: ${match.reason}'}';
      return lease;
    } catch (error, stack) {
      try {
        await channel.invoke(
          PlatformMethods.displayRestore,
          _modePayload(current),
        );
      } catch (_) {
        // The original failure is the actionable one; a subsequent restore is best effort.
      }
      throw PlatformFailure.displaySwitchFailed(cause: error, stack: stack);
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await restoreAll();
  }

  /// Lifecycle-observer restore path; the native process-exit hook covers the rest.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      restoreAll().catchError((Object _) {
        // restoreAll already left the native pending-restore record for the next launch.
      });
    }
  }

  static String _describe(DisplayMode? mode) => mode == null
      ? 'none'
      : '${mode.width}x${mode.height}@${mode.refreshHz}Hz';

  Future<void> restoreAll() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final lease in List<DisplayModeLeaseImpl>.of(_leases)) {
      try {
        await lease.release();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
  }

  static DisplayMode? _parse(Object? raw) {
    final map = asMap(raw);
    final width = intValue(map['width']);
    final height = intValue(map['height']);
    final refresh = doubleValue(map['refreshHz']);
    if (width == null || height == null || refresh == null) return null;
    return DisplayMode(
      width: width,
      height: height,
      refreshHz: refresh == 0 ? 60 : refresh, // Kodi macOS 4.4
      isCurrent: boolValue(map['isCurrent']),
    );
  }

  static List<DisplayMode> _deduplicate(List<DisplayMode> modes) {
    final result = <DisplayMode>[];
    for (final mode in modes) {
      final index = result.indexWhere(
        (other) =>
            other.width == mode.width &&
            other.height == mode.height &&
            (other.refreshHz - mode.refreshHz).abs() < 0.001,
      );
      if (index < 0) {
        result.add(mode);
      } else if (mode.isCurrent && !result[index].isCurrent) {
        result[index] = mode;
      }
    }
    final currentIndex = result.indexWhere((mode) => mode.isCurrent);
    if (currentIndex >= 0) {
      for (var index = 0; index < result.length; index++) {
        if (index != currentIndex && result[index].isCurrent) {
          result[index] = DisplayMode(
            width: result[index].width,
            height: result[index].height,
            refreshHz: result[index].refreshHz,
            isCurrent: false,
          );
        }
      }
    }
    result.sort((a, b) {
      final resolution = (a.width * a.height).compareTo(b.width * b.height);
      return resolution == 0 ? a.refreshHz.compareTo(b.refreshHz) : resolution;
    });
    return result;
  }

  static Map<String, Object?> _modePayload(DisplayMode mode) => {
    'width': mode.width,
    'height': mode.height,
    'refreshHz': mode.refreshHz.isFinite ? mode.refreshHz : 0,
  };
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
