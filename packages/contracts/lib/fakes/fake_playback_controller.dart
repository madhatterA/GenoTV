import 'dart:async';

import 'package:contracts/contracts.dart';

/// Controllable, deterministic [PlaybackController] fake. No `Future.delayed`
/// anywhere — a test drives the clock explicitly via [advanceTo].
class FakePlaybackController implements PlaybackController {
  FakePlaybackController();

  /// Returns a controller pre-wired to fail with [failure] as soon as
  /// [open] is called — the injection seam
  /// `runPlaybackControllerContractTests` uses to prove a failure reaches
  /// both [state] and [events], since nothing on the plain
  /// [PlaybackController] interface can trigger a failure from outside.
  factory FakePlaybackController.thatFailsOnOpen(PlaybackFailure failure) =>
      FakePlaybackController().._failOnOpen = failure;

  final StreamController<PlaybackState> _stateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<PlaybackEvent> _eventController =
      StreamController<PlaybackEvent>.broadcast();

  final StreamController<MediaInfo> _mediaInfoController =
      StreamController<MediaInfo>.broadcast();

  PlaybackState _current = PlaybackState.initial();
  bool _disposed = false;
  PlaybackFailure? _failOnOpen;

  /// Every position passed to [seek], in order.
  final List<Duration> recordedSeeks = [];

  void _emitState(PlaybackState state) {
    _current = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('PlaybackController used after dispose()');
  }

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    _checkNotDisposed();
    openedEngineOptions.add(engineOptions);
    if (_failOnOpen case final failure?) {
      failWith(failure);
      return;
    }
    _emitState(_current.copyWith(position: startAt ?? Duration.zero));
    emitEvent(
      MediaOpened(duration: _current.duration, tracks: _current.tracks),
    );
  }

  @override
  Future<void> play() async {
    _checkNotDisposed();
    _emitState(_current.copyWith(isPlaying: true));
  }

  @override
  Future<void> pause() async {
    _checkNotDisposed();
    _emitState(_current.copyWith(isPlaying: false));
  }

  @override
  Future<void> seek(Duration position) async {
    _checkNotDisposed();
    // Emitted before the seek takes effect (`planning/CONTRACTS.md` §3.2 /
    // §9 "seek, end to end").
    emitEvent(SeekRequested(position));
    recordedSeeks.add(position);
    advanceTo(position);
    emitEvent(SeekCompleted(position));
  }

  @override
  Future<void> setRate(double rate) async {
    _checkNotDisposed();
    _emitState(_current.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    _checkNotDisposed();
  }

  final recordedSubtitleDelays = <Duration>[];
  @override
  Future<void> setSubtitleDelay(Duration delay) async {
    _checkNotDisposed();
    recordedSubtitleDelays.add(delay);
  }

  final recordedAudioDelays = <Duration>[];
  @override
  Future<void> setAudioDelay(Duration delay) async {
    _checkNotDisposed();
    recordedAudioDelays.add(delay);
  }

  final recordedSubtitleScales = <double>[];
  @override
  Future<void> setSubtitleScale(double scale) async {
    _checkNotDisposed();
    recordedSubtitleScales.add(scale);
  }

  final recordedSubtitlePositions = <int>[];
  @override
  Future<void> setSubtitlePosition(int percent) async {
    _checkNotDisposed();
    recordedSubtitlePositions.add(percent);
  }

  final recordedAspectRatios = <String?>[];
  @override
  Future<void> setAspectRatio(String? ratio) async {
    _checkNotDisposed();
    recordedAspectRatios.add(ratio);
  }

  final recordedAudioOutput = <AudioPlan>[];
  @override
  Future<void> setAudioOutput(AudioPlan plan) async {
    _checkNotDisposed();
    recordedAudioOutput.add(plan);
  }

  final recordedFillScreen = <bool>[];

  /// The `engineOptions` of every [open] call, in order.
  final openedEngineOptions = <Map<String, String>>[];

  /// Every map passed to [setEngineOptions], in order.
  final recordedEngineOptions = <Map<String, String>>[];
  @override
  Future<void> setEngineOptions(Map<String, String> options) async {
    _checkNotDisposed();
    recordedEngineOptions.add(options);
  }

  /// Option names the fake rejects in [applyUserOptions], with the error text.
  final rejectedUserOptions = <String, String>{};

  /// Every map passed to [applyUserOptions], in order.
  final recordedUserOptions = <Map<String, String>>[];

  @override
  Future<Map<String, String>> applyUserOptions(
    Map<String, String> options,
  ) async {
    _checkNotDisposed();
    recordedUserOptions.add(options);
    return {
      for (final name in options.keys)
        if (rejectedUserOptions.containsKey(name))
          name: rejectedUserOptions[name]!,
    };
  }

  final StreamController<Map<String, String>> _diagnosticsController =
      StreamController<Map<String, String>>.broadcast();

  @override
  Stream<Map<String, String>> get diagnostics => _diagnosticsController.stream;

  void emitDiagnostics(Map<String, String> values) {
    if (!_diagnosticsController.isClosed) _diagnosticsController.add(values);
  }

  @override
  Future<void> setFillScreen(bool enabled) async {
    _checkNotDisposed();
    recordedFillScreen.add(enabled);
  }

  @override
  Future<void> selectTrack(TrackSelection selection) async {
    _checkNotDisposed();
    _emitState(_current.copyWith(selected: selection));
  }

  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {
    _checkNotDisposed();
  }

  @override
  Stream<PlaybackState> get state => _stateController.stream;

  @override
  Stream<PlaybackEvent> get events => _eventController.stream;

  @override
  Stream<MediaInfo> get mediaInfo => _mediaInfoController.stream;

  void emitMediaInfo(MediaInfo info) {
    if (!_mediaInfoController.isClosed) _mediaInfoController.add(info);
  }

  @override
  PlaybackState get currentState => _current;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stateController.close();
    await _eventController.close();
    await _mediaInfoController.close();
    await _diagnosticsController.close();
  }

  /// Drives the fake's clock directly.
  void advanceTo(Duration position) =>
      _emitState(_current.copyWith(position: position));

  void setTracks(TrackList tracks) =>
      _emitState(_current.copyWith(tracks: tracks));

  void setDuration(Duration duration) =>
      _emitState(_current.copyWith(duration: duration));

  void setBufferedAhead(Duration bufferedAhead) =>
      _emitState(_current.copyWith(bufferedAhead: bufferedAhead));

  void emitEvent(PlaybackEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
    if (event is PlaybackFailed) {
      _emitState(_current.copyWith(failure: event.failure));
    }
  }

  void failWith(PlaybackFailure failure) => emitEvent(PlaybackFailed(failure));
}
