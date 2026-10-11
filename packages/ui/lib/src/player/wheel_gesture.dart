import 'dart:async';
import 'dart:math' as math;

import 'package:contracts/contracts.dart';

import '../focus/ui_command.dart';

/// Samples below this radius from center are pure rest-state noise (finger
/// resting near the middle of the circular touchpad) and are dropped without
/// even resetting angle tracking.
/// Source: `InputConfig.joystickDeadzone` (research/Rivulet/Rivulet/Config/InputConfig.swift:39).
const double kWheelDeadzone = 0.2;

/// Rotation is only tracked once the finger is out past this radius — inside
/// it, a touch is a tap/press, not a wheel gesture.
/// Source: `InputConfig.wheelRadiusThreshold` (InputConfig.swift:38).
const double kWheelRadiusThreshold = 0.7;

/// Accumulated rotation must exceed this many radians before it is applied
/// as a seek delta.
/// Source: `InputConfig.wheelRotationThreshold` (InputConfig.swift:37).
const double kWheelRotationThreshold = 0.3;

/// Content-seconds moved per radian of accumulated rotation.
/// Source: `InputConfig.wheelSecondsPerRadian` (InputConfig.swift:40).
const double kWheelSecondsPerRadian = 10;

/// The wheel commits its preview after this long without a new sample.
/// Source: `UniversalPlayerViewModel.wheelScrubbingIdleDelay` (line 399).
const Duration kWheelIdleCommitDelay = Duration(milliseconds: 800);

/// iPod-style circular clickpad scrubbing: tracks (x, y) samples in
/// [-1, 1]^2, accepts rotation only on the outer ring, accumulates angular
/// motion, and converts each threshold-crossing burst into a scrub preview
/// delta. Commits on 800 ms idle or Select; Down/Back cancels back to the
/// invocation position.
///
/// Source: `setupMicroGamepad`'s `dpad.valueChangedHandler`
/// (research/Rivulet/Rivulet/Views/Player/UniversalPlayerView.swift:174-227)
/// for the radius/angle/accumulation math, and
/// `UniversalPlayerViewModel.handleWheelRotation`
/// (research/Rivulet/Rivulet/Views/Player/UniversalPlayerViewModel.swift:3088-3116)
/// for the scrub-preview/idle-timer behavior.
class WheelGesture {
  WheelGesture({
    required this.controller,
    this.idleCommitDelay = kWheelIdleCommitDelay,
  });

  final PlaybackController controller;
  final Duration idleCommitDelay;

  double? _lastAngle;
  double _accumulatedRotation = 0;

  Duration? _invocationPosition;
  bool _wasPlayingAtInvocation = false;
  Duration _previewPosition = Duration.zero;
  Timer? _idleTimer;

  bool get isActive => _invocationPosition != null;
  Duration get previewPosition => _previewPosition;

  /// Feed one raw (x, y) sample, each in [-1, 1] — the circular touchpad's
  /// reported dpad position.
  void addSample(double x, double y) {
    final radius = math.sqrt(x * x + y * y);
    if (radius < kWheelDeadzone) {
      // Resting near center: noise, not a gesture. Drop silently.
      _lastAngle = null;
      _accumulatedRotation = 0;
      return;
    }
    if (radius <= kWheelRadiusThreshold) {
      // Off the outer ring but past the deadzone: not yet a wheel rotation
      // (e.g. mid-swipe toward center). Reset tracking, no seek.
      _lastAngle = null;
      _accumulatedRotation = 0;
      return;
    }

    final angle = math.atan2(y, x);
    final last = _lastAngle;
    _lastAngle = angle;
    if (last == null) return; // first sample on the ring just anchors tracking

    var delta = angle - last;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _accumulatedRotation += delta;

    if (_accumulatedRotation.abs() > kWheelRotationThreshold) {
      final rotation = _accumulatedRotation;
      _accumulatedRotation = 0;
      _applyRotation(rotation);
    }
  }

  void _applyRotation(double radians) {
    if (!isActive) {
      final state = controller.currentState;
      _invocationPosition = state.position;
      _wasPlayingAtInvocation = state.isPlaying;
      _previewPosition = state.position;
      controller.pause();
    }
    final deltaMs = (radians * kWheelSecondsPerRadian * 1000).round();
    final duration = controller.currentState.duration;
    _previewPosition = _clamp(
      _previewPosition + Duration(milliseconds: deltaMs),
      duration,
    );
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleCommitDelay, commit);
  }

  void handleCommand(UiCommand command) {
    switch (command.type) {
      case UiCommandType.selectDown:
        if (isActive) commit();
      case UiCommandType.directionDown:
      case UiCommandType.menuBack:
        if (isActive) cancel();
      default:
        break;
    }
  }

  Future<void> commit() async {
    if (!isActive) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    final target = _previewPosition;
    final resumePlaying = _wasPlayingAtInvocation;
    _reset();
    await controller.seek(target);
    if (resumePlaying) await controller.play();
  }

  Future<void> cancel() async {
    if (!isActive) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    final resumePlaying = _wasPlayingAtInvocation;
    _reset();
    if (resumePlaying) await controller.play();
  }

  void _reset() {
    _invocationPosition = null;
    _wasPlayingAtInvocation = false;
    _lastAngle = null;
    _accumulatedRotation = 0;
  }

  static Duration _clamp(Duration value, Duration duration) {
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  void dispose() {
    _idleTimer?.cancel();
  }
}
