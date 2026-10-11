import '../l10n_gen/app_strings.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../components/orb_loader.dart';
import '../theme/rivulet_tokens.dart';

import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// One alert per continuous outage. Dismissal does not imply recovery.
import '../components/app_button.dart';
import 'empty_view.dart';

class ConnectionOutageController extends ChangeNotifier {
  ConnectionOutageController({AppLogger? logger})
    : _logger = logger ?? ConsoleLogger();

  final AppLogger _logger;
  bool _isDown = false;
  bool _visible = false;
  bool _retrying = false;
  bool _retryFailed = false;
  bool _disposed = false;
  int _outageEpoch = 0;

  bool get isDown => _isDown;
  bool get visible => _visible;
  bool get retrying => _retrying;
  bool get retryFailed => _retryFailed;
  int get outageEpoch => _outageEpoch;

  void updateConnection({required bool healthy}) {
    if (_disposed || healthy == !_isDown) return;
    _isDown = !healthy;
    _visible = !healthy;
    _retrying = false;
    _retryFailed = false;
    if (!healthy) _outageEpoch++;
    notifyListeners();
  }

  void dismiss() {
    if (_disposed || !_visible) return;
    _visible = false;
    notifyListeners();
  }

  Future<void> retry(Future<void> Function() onRetry) async {
    if (_disposed || !_isDown || _retrying) return;
    final epoch = _outageEpoch;
    _retrying = true;
    _retryFailed = false;
    notifyListeners();
    try {
      await onRetry();
      if (!_disposed && _isDown && epoch == _outageEpoch) {
        updateConnection(healthy: true);
      }
    } catch (error, stack) {
      _logger.error(
        'Connection outage retry failed',
        error: error,
        stack: stack,
      );
      if (!_disposed && _isDown && epoch == _outageEpoch) {
        _retrying = false;
        _retryFailed = true;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Network work belongs to the caller. Native buttons supply focus/activation.
class ConnectionOutageBanner extends StatefulWidget {
  const ConnectionOutageBanner({
    required this.controller,
    required this.onRetry,
    this.hasUsableContent = false,
    super.key,
  });

  final ConnectionOutageController controller;
  final Future<void> Function() onRetry;

  /// True when other content is on screen: Retry then never takes focus.
  final bool hasUsableContent;

  @override
  State<ConnectionOutageBanner> createState() => _ConnectionOutageBannerState();
}

class _ConnectionOutageBannerState extends State<ConnectionOutageBanner> {
  ModalRoute<dynamic>? _route;
  LocalHistoryEntry? _history;
  ConnectionOutageController get controller => widget.controller;
  Future<void> Function() get onRetry => widget.onRetry;

  @override
  void initState() {
    super.initState();
    controller.addListener(_syncHistory);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (_route != route) {
      _removeHistory();
      _route = route;
    }
    _syncHistory();
  }

  @override
  void didUpdateWidget(ConnectionOutageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_syncHistory);
      _removeHistory();
      controller.addListener(_syncHistory);
      _syncHistory();
    }
  }

  void _syncHistory() {
    if (!controller.visible) {
      _removeHistory();
    } else if (_history == null && _route != null) {
      final outage = controller;
      late final LocalHistoryEntry entry;
      entry = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_history != entry) return;
          _history = null;
          outage.dismiss();
        },
      );
      _history = entry;
      _route!.addLocalHistoryEntry(entry);
    }
  }

  void _removeHistory() {
    final entry = _history;
    _history = null;
    entry?.remove();
  }

  @override
  void dispose() {
    controller.removeListener(_syncHistory);
    _removeHistory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => PopScope(
      canPop: !controller.visible,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.dismiss();
      },
      child: controller.visible
          ? CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape):
                    controller.dismiss,
                const SingleActivator(LogicalKeyboardKey.goBack):
                    controller.dismiss,
              },
              child: Semantics(
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: RivuletSpacing.s24,
                  ),
                  child: EmptyView(
                    icon: PhosphorIconsRegular.wifiSlash,
                    headline: AppStrings.of(context).state_offline,
                    body: controller.retrying
                        ? AppStrings.of(context).state_reconnecting
                        : controller.retryFailed
                        ? AppStrings.of(context).state_retryFailed
                        : AppStrings.of(context).state_offlineBody,
                    action: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: RivuletSpacing.s12,
                      runSpacing: RivuletSpacing.s12,
                      children: [
                        AppButton.primary(
                          autofocus: !widget.hasUsableContent,
                          label: AppStrings.of(context).common_retry,
                          onActivate: controller.retrying
                              ? null
                              : () => controller.retry(onRetry),
                        ),
                        if (controller.retrying) const OrbLoader.small(),
                        AppButton.secondary(
                          label: AppStrings.of(context).common_dismiss,
                          onActivate: controller.dismiss,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    ),
  );
}
