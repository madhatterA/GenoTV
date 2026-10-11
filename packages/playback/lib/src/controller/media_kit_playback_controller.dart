import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/ffi/ffi.dart'
    show StringUtf8Pointer, Utf8Pointer, Utf8, calloc;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_surface/video_surface.dart' as native;

import '../surface/hdr_policy.dart';
import '../surface/surface_output.dart';

import '../engine/engine_bootstrap.dart';
import '../tracks/track_mapper.dart';
import '../tracks/chapter_mapper.dart';
import 'buffering_model.dart' as buffering;
import 'seek_coalescer.dart';
import 'state_mapper.dart' as mapper;

/// The media_kit-backed implementation of [PlaybackController].
final class MediaKitPlaybackController
    implements PlaybackController, EngineProperties {
  /// Takes ownership of an injected [player], including its disposal.
  MediaKitPlaybackController({
    required AppLogger logger,
    this.resolveUri,
    this.failOnOpen,
    this.hdrPolicy = HdrPolicy.auto,
    mk.Player? player,
    SurfaceOutput? output,
  }) : _logger = logger.scoped('playback') {
    EngineBootstrap.ensureInitialised(logger: _logger);
    // libass: mpv draws the subtitles itself (sub-visibility yes); the native
    // surface has no Flutter subtitle overlay, so without it nothing shows.
    _player =
        player ??
        mk.Player(configuration: const mk.PlayerConfiguration(libass: true));
    surfaceOutput =
        output ??
        SurfaceOutput(
          attach: () => native.NativeVideoSurface.create(
            handle: _player.handle,
            hdrSource: _player.stream.videoParams.map(
              (p) => hdrPolicy.reportsHdr(p.gamma),
            ),
          ),
          texture: _attachTextureOutput,
          logger: _logger,
          onError: (error, stack) => _emitFailure(
            PlaybackFailure.engineCrashed(cause: error, stack: stack),
          ),
        );
    _seekCoalescer = SeekCoalescer(issue: _issueSeek);
    _bufferingDebouncer = buffering.BufferingDebouncer(
      onChanged: (value) => _emit(_current.copyWith(isBuffering: value)),
    );
    _subscriptions.addAll([
      _player.stream.position.listen(_onPosition),
      _player.stream.duration.listen(_onDuration),
      _player.stream.playing.listen(_onPlaying),
      _player.stream.buffering.listen(_onBuffering),
      _player.stream.buffer.listen(_onBuffer),
      _player.stream.completed.listen(_onCompleted),
      _player.stream.tracks.listen(_onTracks),
      _player.stream.track.listen(_onTrack),
      _player.stream.log.listen(_onEngineLog),
      _player.stream.error.listen(_onEngineError),
      _player.stream.videoParams.listen(_onVideoParams),
    ]);
  }

  late final mk.Player _player;
  late final SeekCoalescer _seekCoalescer;
  late final buffering.BufferingDebouncer _bufferingDebouncer;
  final AppLogger _logger;
  final Uri Function(Uri uri)? resolveUri;
  final PlaybackFailure? failOnOpen;
  final HdrPolicy hdrPolicy;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  final _stateController = StreamController<PlaybackState>.broadcast();
  final _eventController = StreamController<PlaybackEvent>.broadcast();
  final _mediaInfoController = StreamController<MediaInfo>.broadcast();

  /// The mpv properties [diagnostics] reports (mpv manual: video-params,
  /// frame-drop-count, video-bitrate, demuxer-cache-state, hwdec-current,
  /// current-ao, audio-out-params).
  static const diagnosticProperties = <String>[
    'video-codec',
    'hwdec-current',
    'video-params/w',
    'video-params/h',
    'video-params/pixelformat',
    'video-params/colormatrix',
    'video-params/gamma',
    'video-params/primaries',
    'video-params/sig-peak',
    'video-params/max-cll',
    'video-params/max-fall',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'video-bitrate',
    'audio-bitrate',
    'demuxer-cache-duration',
    'demuxer-cache-state',
    'audio-codec',
    'audio-params/format',
    'audio-params/samplerate',
    'audio-params/channels',
    'current-ao',
    'audio-out-params/format',
    'audio-out-params/samplerate',
    'audio-out-params/channels',
  ];
  final _diagnosticsController =
      StreamController<Map<String, String>>.broadcast();
  final _diagnostics = <String, String>{};
  bool _diagnosticsObserved = false;
  bool _diagnosticsScheduled = false;
  MediaInfo? _latestMediaInfo;
  final _externalSubtitleUris = <String>{};
  PlaybackState _current = PlaybackState.initial();
  VideoController? _videoController;
  late final SurfaceOutput surfaceOutput;

  bool get hasTextureOutput => _videoController != null;
  bool _disposed = false;
  String _openedPath = '';
  bool _opened = false;
  bool _endedEmitted = false;
  bool _engineBuffering = false;
  Duration _engineBuffer = Duration.zero;
  double? _containerFps;
  String? _containerFormat;
  DateTime? _lastPositionEmission;
  Duration? _pendingPosition;
  Timer? _positionTimer;
  Future<void> _liveOptionTail = Future<void>.value();

  @override
  Stream<PlaybackState> get state => Stream.multi((multi) {
    multi.add(_current);
    if (_stateController.isClosed) {
      multi.close();
      return;
    }
    final subscription = _stateController.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  Stream<PlaybackEvent> get events => _eventController.stream;

  @override
  Stream<MediaInfo> get mediaInfo => Stream.multi((multi) {
    if (_latestMediaInfo case final latest?) multi.add(latest);
    if (_mediaInfoController.isClosed) {
      multi.close();
      return;
    }
    final subscription = _mediaInfoController.stream.listen(
      multi.add,
      onError: multi.addError,
      onDone: multi.close,
    );
    multi.onCancel = subscription.cancel;
  }, isBroadcast: true);

  @override
  PlaybackState get currentState => _current;

  /// Codec names this engine build can decode (mpv `decoder-list`).
  Future<Set<String>> decoderCodecs() async {
    _checkUsable();
    final raw = await (_player.platform as mk.NativePlayer).getProperty(
      'decoder-list',
    );
    return {
      for (final d in jsonDecode(raw) as List) (d as Map)['codec'] as String,
    };
  }

  /// Metadata needed by the settings picker which media_kit's Track omits.
  /// Kept within playback; the cross-Part Track contract is unchanged.
  Future<Map<String, Map<String, dynamic>>> trackMetadata() async {
    _checkUsable();
    _requireOpen();
    final raw = await (_player.platform as mk.NativePlayer).getProperty(
      'track-list',
    );
    final tracks = jsonDecode(raw) as List;
    return {
      for (final t in tracks.cast<Map<String, dynamic>>())
        '${t['type']}/${t['id']}': t,
    };
  }

  /// The texture controller used by [VideoSurface].
  VideoController get videoController {
    return _videoController ??
        (throw StateError('texture video output has not been prepared'));
  }

  /// Native rendering must be released before this creates another mpv context.
  Future<void> _attachTextureOutput() async {
    final backend = _player.platform as mk.NativePlayer;
    for (final name in ['target-trc', 'target-prim', 'target-peak']) {
      await _setMpvProperty(backend, name, 'auto');
    }
    _videoController ??= VideoController(_player);
    WidgetsBinding.instance.ensureVisualUpdate();
    await _videoController!.platform.future;
    // A runtime fallback attaches after the original dimension event. Seed the
    // current dimensions explicitly instead of waiting for another media load.
    final params = _player.state.videoParams;
    if ((params.dw ?? 0) > 0 && (params.dh ?? 0) > 0) {
      final rotated = params.rotate == 90 || params.rotate == 270;
      await _videoController!.setSize(
        width: rotated ? params.dh : params.dw,
        height: rotated ? params.dw : params.dh,
      );
    }
  }

  @override
  Future<void> open(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration? startAt,
    Map<String, String> engineOptions = const {},
  }) async {
    _checkUsable();
    EngineBootstrap.ensureInitialised(logger: _logger);
    _endedEmitted = false;
    _opened = false;
    _latestMediaInfo = null;
    _defaultsDone = false;
    _heldDecoderCodec = null;
    _heldDecoderMessage = null;
    _pendingVideoDecoderError = null;
    _decoderOpenLogs = [];
    _current = PlaybackState.initial();
    _externalSubtitleUris.clear();
    if (_diagnostics.isNotEmpty) {
      _diagnostics.clear();
      _diagnosticsController.add(const <String, String>{});
    }
    if (failOnOpen case final failure?) {
      _emitFailure(failure);
      return;
    }
    final mediaUri = resolveUri?.call(uri) ?? uri;
    try {
      if (mediaUri.isScheme('file') &&
          !File(mediaUri.toFilePath()).existsSync()) {
        throw StateError('Media file does not exist: $mediaUri');
      }
      await surfaceOutput.prepare();
      await _liveOptionTail;
      await _applyEngineOptions(engineOptions);
      await _player.open(
        mk.Media(mediaKitResourceFor(mediaUri), httpHeaders: headers),
        play: false,
      );
      _opened = true;
      _openedPath = mediaUri.path;
      await _observeDiagnostics();
      if (!engineOptions.containsKey('sub-delay')) {
        await setSubtitleDelay(Duration.zero);
      }
      // A default the caller set through [engineOptions] is not a per-video
      // value, so it survives the reset to a clean per-video state.
      if (!engineOptions.containsKey('audio-delay')) {
        await setAudioDelay(Duration.zero);
      }
      if (!engineOptions.containsKey('sub-scale')) await setSubtitleScale(1);
      if (!engineOptions.containsKey('sub-pos')) await setSubtitlePosition(100);
      await setAspectRatio(null);
      if (!engineOptions.containsKey('panscan')) await setFillScreen(false);
      _refreshFromPlayer();
      final duration = await _durationAfterOpen();
      await _loadNativeMetadata();
      await _publishMediaInfo();
      _emitEvent(MediaOpened(duration: duration, tracks: _current.tracks));
      _logDiagnostics();
      if (startAt != null) await seek(startAt);
    } catch (error, stack) {
      final failure = _classifyFailure(error, stack);
      _emitFailure(failure);
      rethrow;
    }
  }

  Future<Duration> _durationAfterOpen() async {
    final current = _player.state.duration;
    if (current > Duration.zero) return current;
    try {
      return await _player.stream.duration
          .firstWhere((duration) => duration > Duration.zero)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
      return _player.state.duration;
    }
  }

  @override
  Future<void> play() async {
    _checkUsable();
    _requireOpen();
    _emit(_current.copyWith(isPlaying: true, isCompleted: false));
    try {
      await _player.play();
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    _checkUsable();
    _requireOpen();
    _emit(_current.copyWith(isPlaying: false, isBuffering: false));
    try {
      await _player.pause();
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> seek(Duration position) {
    _checkUsable();
    _requireOpen();
    return _seekCoalescer.request(
      clampSeekTarget(position, duration: _current.duration),
    );
  }

  Future<void> _issueSeek(Duration target) async {
    _emitEvent(SeekRequested(target));
    try {
      await _player.seek(target);
      final actual = _player.state.position;
      _emit(
        buffering.applyBuffered(
          mapper.applyPosition(_current, actual),
          _engineBuffer,
        ),
      );
      _emitEvent(SeekCompleted(actual));
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> setRate(double rate) async {
    _checkUsable();
    if (!rate.isFinite) {
      throw ArgumentError.value(rate, 'rate', 'must be finite');
    }
    final value = rate.clamp(0.25, 4.0).toDouble();
    try {
      await _player.setRate(value);
      _emit(_current.copyWith(rate: value));
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _checkUsable();
    if (!volume.isFinite) {
      throw ArgumentError.value(volume, 'volume', 'must be finite');
    }
    final value = volume.clamp(0.0, 1.0).toDouble();
    try {
      await _player.setVolume(mapVolumeToEngine(value));
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> setSubtitleDelay(Duration delay) {
    final seconds = delay.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds < -10 || seconds > 10) {
      throw ArgumentError.value(
        delay,
        'delay',
        'must be within -10…10 seconds',
      );
    }
    return _queueLiveOption('sub-delay', seconds.toString(), seconds);
  }

  @override
  Future<void> setAudioDelay(Duration delay) {
    final seconds = delay.inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds < -5 || seconds > 5) {
      throw ArgumentError.value(delay, 'delay', 'must be within -5…5 seconds');
    }
    return _queueLiveOption('audio-delay', seconds.toString(), seconds);
  }

  @override
  Future<void> setSubtitleScale(double scale) {
    if (!scale.isFinite || scale <= 0 || scale > 100) {
      throw ArgumentError.value(
        scale,
        'scale',
        'must be finite and within 0…100 (exclusive of 0)',
      );
    }
    return _queueLiveOption('sub-scale', scale.toString(), scale);
  }

  @override
  Future<void> setSubtitlePosition(int percent) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError.value(percent, 'percent', 'must be within 0…100');
    }
    return _queueLiveOption('sub-pos', percent.toString(), percent.toDouble());
  }

  @override
  Future<void> setAspectRatio(String? ratio) {
    const ratios = <String, double>{
      '16:9': 16 / 9,
      '4:3': 4 / 3,
      '21:9': 21 / 9,
      '2.39:1': 2.39,
    };
    if (ratio != null && !ratios.containsKey(ratio)) {
      throw ArgumentError.value(
        ratio,
        'ratio',
        'must be an approved aspect ratio or null',
      );
    }
    return _queueLiveOption(
      'video-aspect-override',
      // Bundled mpv 0.36: -1 restores automatic aspect; 'no' disables aspect handling.
      ratio ?? '-1',
      ratios[ratio] ?? -1,
    );
  }

  @override
  Future<void> setEngineOptions(Map<String, String> options) {
    final result = _liveOptionTail.then((_) async {
      try {
        await _applyEngineOptions(options);
      } catch (error, stack) {
        _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
        rethrow;
      }
    });
    _liveOptionTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Future<Map<String, String>> applyUserOptions(Map<String, String> options) {
    final result = _liveOptionTail.then((_) async {
      _checkUsable();
      final backend = _player.platform as mk.NativePlayer;
      final rejected = <String, String>{};
      for (final MapEntry(:key, :value) in options.entries) {
        try {
          await _setMpvProperty(backend, key, value);
        } on StateError catch (error) {
          rejected[key] = error.message;
          _logger.warn('custom mpv option rejected: ${error.message}');
        }
      }
      return rejected;
    });
    _liveOptionTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  @override
  Stream<Map<String, String>> get diagnostics => _diagnosticsController.stream;

  /// Reads each mpv property once, on demand (the stats overlay's 1 s
  /// refresh). mpv answers an error for a property with no value right now
  /// (e.g. `avsync` before the first frame); that is "not available", so the
  /// property is left out of the result rather than reported as an error.
  @override
  Future<Map<String, String>> readProperties(List<String> names) async {
    if (!_opened || _disposed) return const {};
    final native = _player.platform as mk.NativePlayer;
    final result = <String, String>{};
    for (final name in names) {
      try {
        final value = await native.getProperty(name);
        if (value.isNotEmpty) result[name] = value;
      } on Object {
        continue;
      }
    }
    return result;
  }

  /// Registers the mpv property observers once; mpv sends each property's
  /// current value right after it is observed, then on every change.
  Future<void> _observeDiagnostics() async {
    if (_diagnosticsObserved) return;
    _diagnosticsObserved = true;
    final backend = _player.platform as mk.NativePlayer;
    await backend.observeProperty('cache-buffering-state', (value) async {
      final progress = buffering.bufferingProgressFromMpv(value);
      if (_disposed || progress == null) return;
      _emit(_current.copyWith(bufferingProgress: progress));
    });
    for (final name in diagnosticProperties) {
      await backend.observeProperty(name, (value) async {
        if (_disposed) return;
        _diagnostics[name] = value;
        if (_diagnosticsScheduled) return;
        _diagnosticsScheduled = true;
        scheduleMicrotask(() {
          _diagnosticsScheduled = false;
          if (!_disposed && !_diagnosticsController.isClosed) {
            _diagnosticsController.add(Map.unmodifiable(_diagnostics));
          }
        });
      });
    }
  }

  Future<void> _applyEngineOptions(Map<String, String> options) async {
    _checkUsable();
    final backend = _player.platform as mk.NativePlayer;
    for (final MapEntry(:key, :value) in options.entries) {
      if (key == 'sub-codepage') _subtitleEncoding = value;
      await _setMpvProperty(backend, key, value);
      if (key == 'sub-codepage' &&
          _opened &&
          _externalSubtitleUris.isNotEmpty) {
        final tracks = await trackMetadata();
        for (final track in tracks.values) {
          if (track['type'] != 'sub' || track['external'] != true) continue;
          final path = track['external-filename'] as String?;
          if (path == null) {
            throw StateError('External subtitle path is missing');
          }
          final uri = Uri.parse(path);
          await _resolveSubtitleEncoding(uri.hasScheme ? uri : Uri.file(path));
          await backend.command(['sub-reload', track['id'].toString()]);
        }
      }
    }
  }

  /// The viewer's subtitle encoding choice; 'auto' is resolved per external
  /// file from its bytes (BOM or valid UTF-8 is utf-8, else cp1256), explicit
  /// choices pass through unchanged.
  String _subtitleEncoding = 'auto';

  Future<void> _resolveSubtitleEncoding(Uri uri) async {
    if (_subtitleEncoding != 'auto') return;
    final List<int> bytes;
    if (uri.isScheme('file')) {
      bytes = await File(uri.toFilePath()).readAsBytes();
    } else {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      try {
        // Subtitles are text: direct first, the backup proxy on failure.
        final response = await BackupRouter().send(
          client,
          'GET',
          uri,
          const {},
        );
        if (response.statusCode != HttpStatus.ok) {
          throw HttpException('Subtitle HTTP ${response.statusCode}', uri: uri);
        }
        final chunks = await response.toList().timeout(
          const Duration(seconds: 5),
        );
        bytes = [for (final chunk in chunks) ...chunk];
      } finally {
        client.close(force: true);
      }
    }
    var codepage = 'utf-8';
    final bom =
        bytes.length >= 2 &&
        ((bytes.length >= 4 &&
                bytes[0] == 0 &&
                bytes[1] == 0 &&
                bytes[2] == 0xfe &&
                bytes[3] == 0xff) ||
            (bytes[0] == 0xff && bytes[1] == 0xfe) ||
            (bytes[0] == 0xfe && bytes[1] == 0xff) ||
            (bytes.length >= 3 &&
                bytes[0] == 0xef &&
                bytes[1] == 0xbb &&
                bytes[2] == 0xbf));
    if (!bom) {
      try {
        utf8.decode(bytes);
      } on FormatException {
        codepage = 'cp1256';
      }
    }
    await _setMpvProperty(
      _player.platform as mk.NativePlayer,
      'sub-codepage',
      codepage,
    );
  }

  /// media_kit's `setProperty` discards mpv's return code, so a rejected name
  /// or value would go unnoticed. This calls libmpv directly and throws on a
  /// negative code.
  Future<void> _setMpvProperty(
    mk.NativePlayer backend,
    String name,
    String value,
  ) async {
    await backend.waitForPlayerInitialization;
    await backend.waitForVideoControllerInitializationIfAttached;
    final nameUtf8 = name.toNativeUtf8();
    final valueUtf8 = value.toNativeUtf8();
    final code = backend.mpv.mpv_set_property_string(
      backend.ctx,
      nameUtf8.cast(),
      valueUtf8.cast(),
    );
    calloc.free(nameUtf8);
    calloc.free(valueUtf8);
    if (code < 0) {
      final reason = backend.mpv
          .mpv_error_string(code)
          .cast<Utf8>()
          .toDartString();
      throw StateError('mpv rejected $name=$value: $reason ($code)');
    }
  }

  @override
  Future<void> setFillScreen(bool enabled) =>
      _queueLiveOption('panscan', enabled ? '1' : '0', enabled ? 1 : 0);

  @override
  Future<void> setAudioOutput(AudioPlan plan) {
    final result = _liveOptionTail.then((_) => _setAudioOutput(plan));
    _liveOptionTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _setAudioOutput(AudioPlan plan) async {
    _checkUsable();
    try {
      final backend = _player.platform as mk.NativePlayer;
      for (final (property, value) in [
        ('audio-spdif', plan.audioSpdif),
        ('audio-channels', plan.audioChannels),
        ('af', plan.af),
      ]) {
        await _setMpvProperty(backend, property, value);
        final actual = await backend.getProperty(property);
        if (actual != value) {
          throw StateError(
            'mpv did not apply $property=$value (read back $actual)',
          );
        }
      }
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  Future<void> _queueLiveOption(
    String property,
    String value,
    double expected,
  ) {
    final result = _liveOptionTail.then(
      (_) => _setLiveOption(property, value, expected),
    );
    // Keep the queue usable after rejection. The caller's result and failure event retain the error.
    _liveOptionTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<void> _setLiveOption(
    String property,
    String value,
    double expected,
  ) async {
    _checkUsable();
    try {
      final backend = _player.platform as mk.NativePlayer;
      await _setMpvProperty(backend, property, value);
      final actual = double.tryParse(await backend.getProperty(property));
      if (actual == null ||
          !actual.isFinite ||
          (actual - expected).abs() > 0.00001) {
        throw StateError(
          'mpv did not apply $property=$value (read back $actual)',
        );
      }
    } catch (error, stack) {
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
      rethrow;
    }
  }

  @override
  Future<void> selectTrack(TrackSelection selection) async {
    _checkUsable();
    _requireOpen();
    try {
      _validateChoice(selection.video, _current.tracks.video);
      _validateChoice(selection.audio, _current.tracks.audio);
      _validateChoice(selection.subtitle, _current.tracks.subtitle);
      await _player.setVideoTrack(_toVideo(selection.video));
      await _player.setAudioTrack(_toAudio(selection.audio));
      await _player.setSubtitleTrack(_toSubtitle(selection.subtitle));
      _emit(_current.copyWith(selected: selection));
    } catch (error, stack) {
      final failure = PlaybackFailure.trackSelectionFailed(
        trackId: _selectionId(selection),
        cause: error,
        stack: stack,
      );
      _emitFailure(failure);
      throw StateError(failure.toString());
    }
  }

  @override
  Future<void> addExternalSubtitle(Uri uri, {String? title}) async {
    _checkUsable();
    _requireOpen();
    if (!uri.isScheme('file') &&
        !uri.isScheme('http') &&
        !uri.isScheme('https')) {
      final error = ArgumentError.value(
        uri,
        'uri',
        'subtitle URI must be file or http(s)',
      );
      final failure = PlaybackFailure.subtitleLoadFailed(
        uri: uri,
        cause: error,
      );
      _emitFailure(failure);
      throw error;
    }
    final previous = _current.selected.subtitle;
    final key = uri.toString();
    if (_externalSubtitleUris.contains(key)) return;
    try {
      if (uri.isScheme('file') && !File(uri.toFilePath()).existsSync()) {
        throw StateError('Subtitle file does not exist: $uri');
      }
      await _resolveSubtitleEncoding(uri);
      final before = _player.state.tracks.subtitle.length;
      await _player.setSubtitleTrack(
        mk.SubtitleTrack.uri(uri.toString(), title: title),
      );
      if (_player.state.tracks.subtitle.length <= before) {
        await _player.stream.tracks
            .firstWhere((tracks) => tracks.subtitle.length > before)
            .timeout(const Duration(seconds: 5));
      }
      if (previous.mode == TrackSelectionMode.off) {
        await _player.setSubtitleTrack(mk.SubtitleTrack.no());
      } else if (previous.mode == TrackSelectionMode.specific &&
          previous.id != null) {
        await _player.setSubtitleTrack(
          mk.SubtitleTrack(previous.id!, null, null),
        );
      }
      _externalSubtitleUris.add(key);
      _refreshFromPlayer();
    } catch (error, stack) {
      final failure = PlaybackFailure.subtitleLoadFailed(
        uri: uri,
        cause: error,
        stack: stack,
      );
      _emitFailure(failure);
      throw StateError(failure.toString());
    }
  }

  Future<Map<String, String>> readDiagnostics() async {
    _checkUsable();
    if (!_opened) return const <String, String>{};
    final video = _player.state.videoParams;
    final audio = _player.state.audioParams;
    final result = <String, String>{'backend': 'libmpv'};
    void add(String key, Object? value) {
      if (value != null && value.toString().isNotEmpty) {
        result[key] = value.toString();
      }
    }

    add('pixelFormat', video.pixelformat);
    add(
      'decoder',
      _player.state.track.video.decoder ??
          _player.state.track.video.codec ??
          (_player.state.tracks.video.isEmpty
              ? null
              : _player.state.tracks.video.first.codec),
    );
    add('colorPrimaries', video.primaries);
    add('transferFunction', video.gamma);
    add('fps', _player.state.track.video.fps ?? _containerFps);
    add('containerFormat', _containerFormat);
    if (video.w != null && video.h != null) {
      result['resolution'] = '${video.w}x${video.h}';
    }
    add('audioFormat', audio.format);
    add('audioChannels', audio.channels);
    add('audioDevice', _player.state.audioDevice.name);
    if (!result.containsKey('decoder') ||
        !result.containsKey('fps') ||
        !result.containsKey('containerFormat')) {
      try {
        final dynamic native = _player.platform;
        if (!result.containsKey('decoder')) {
          add('decoder', await native.getProperty('video-codec'));
        }
        if (!result.containsKey('fps')) {
          final value = (await native.getProperty('container-fps')).toString();
          if (value.isNotEmpty) add('fps', double.tryParse(value));
        }
        if (!result.containsKey('containerFormat')) {
          add('containerFormat', await native.getProperty('file-format'));
        }
      } catch (error, stack) {
        _logger.warn(
          'extended media diagnostics unavailable',
          error: error,
          stack: stack,
        );
      }
    }
    return result;
  }

  void _logDiagnostics() {
    unawaited(
      readDiagnostics()
          .then((map) {
            _logger.info('media diagnostics', data: map);
          })
          .catchError((error, stack) {
            _logger.warn(
              'media diagnostics unavailable',
              error: error,
              stack: stack,
            );
          }),
    );
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _positionTimer?.cancel();
    _bufferingDebouncer.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    try {
      try {
        await surfaceOutput.dispose();
      } finally {
        await _player.dispose().timeout(const Duration(seconds: 3));
      }
    } on TimeoutException catch (error, stack) {
      _logger.warn('media engine teardown timed out');
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
    } catch (error, stack) {
      _logger.warn('media engine teardown failed', error: error, stack: stack);
      _emitFailure(PlaybackFailure.engineCrashed(cause: error, stack: stack));
    }
    await _stateController.close();
    await _eventController.close();
    await _mediaInfoController.close();
    await _diagnosticsController.close();
  }

  void _onPosition(Duration position) {
    final now = DateTime.now();
    if (_lastPositionEmission != null &&
        now.difference(_lastPositionEmission!) <
            const Duration(milliseconds: 250)) {
      _pendingPosition = position;
      _positionTimer ??= Timer(const Duration(milliseconds: 250), () {
        _positionTimer = null;
        final pending = _pendingPosition;
        _pendingPosition = null;
        if (pending != null) {
          _lastPositionEmission = DateTime.now();
          _emit(
            buffering.applyBuffered(
              mapper.applyPosition(_current, pending),
              _engineBuffer,
            ),
          );
        }
      });
      return;
    }
    _lastPositionEmission = now;
    _emit(
      buffering.applyBuffered(
        mapper.applyPosition(_current, position),
        _engineBuffer,
      ),
    );
  }

  void _onDuration(Duration duration) => _emit(
    buffering.applyBuffered(
      mapper.applyDuration(_current, duration),
      _engineBuffer,
    ),
  );

  void _onPlaying(bool playing) {
    _emit(mapper.applyPlaying(_current, playing));
    _bufferingDebouncer.update(
      engineBuffering: _engineBuffering,
      isPlaying: playing,
    );
  }

  void _onBuffering(bool value) {
    _engineBuffering = value;
    _bufferingDebouncer.update(
      engineBuffering: value,
      isPlaying: _current.isPlaying,
    );
  }

  void _onBuffer(Duration value) {
    _engineBuffer = value;
    _emit(buffering.applyBuffered(_current, value));
  }

  void _onCompleted(bool completed) {
    if (completed &&
        (_pendingVideoDecoderError != null ||
            _decoderOpenLogs.any((entry) => entry.video && !entry.resolved))) {
      _emitFailure(
        _classifyFailure(
          StateError(_pendingVideoDecoderError ?? 'Could not open codec.'),
          StackTrace.current,
        ),
      );
    }
    _emit(mapper.applyCompleted(_current, completed));
    if (completed && !_endedEmitted) {
      _endedEmitted = true;
      _emitEvent(const PlaybackEnded());
    } else if (!completed) {
      _endedEmitted = false;
    }
  }

  void _onTracks(mk.Tracks tracks) {
    _emit(_current.copyWith(tracks: mapTracks(tracks)));
    _publishMediaInfo();
  }

  void _onTrack(mk.Track track) {
    _emit(_current.copyWith(selected: mapSelection(track)));
    _publishMediaInfo();
  }

  int _mediaInfoGeneration = 0;

  /// Reads the current technical facts from mpv and emits them. Only the
  /// latest request may emit; a property mpv cannot report is simply unknown.
  Future<void> _publishMediaInfo() async {
    if (!_opened || _disposed) return;
    final generation = ++_mediaInfoGeneration;
    final native = _player.platform as mk.NativePlayer;
    Future<String?> read(String name) async {
      try {
        final value = await native.getProperty(name);
        return value.isEmpty ? null : value;
      } on Object {
        return null;
      }
    }

    Future<int?> readInt(String name) async =>
        int.tryParse(await read(name) ?? '') ??
        double.tryParse(await read(name) ?? '')?.round();
    Future<double?> readDouble(String name) async =>
        double.tryParse(await read(name) ?? '');

    final pixelFormat = await read('video-params/pixelformat');
    final size = await readInt('file-size');
    final durationSeconds = await readDouble('duration');
    final videoRate = await readInt('video-bitrate');
    final audioRate = await readInt('audio-bitrate');
    final fps = await readDouble('container-fps');
    final info = MediaInfo(
      container: mapper.pickContainerFormat(
        await read('file-format'),
        _openedPath,
      ),
      fileSizeBytes: size,
      duration: durationSeconds == null
          ? null
          : Duration(
              microseconds: (durationSeconds * Duration.microsecondsPerSecond)
                  .round(),
            ),
      bitrate: videoRate == null && audioRate == null
          ? (size != null && durationSeconds != null && durationSeconds > 0
                ? (size * 8 / durationSeconds).round()
                : null)
          : (videoRate ?? 0) + (audioRate ?? 0),
      videoCodec: await read('current-tracks/video/codec'),
      width: await readInt('video-params/w'),
      height: await readInt('video-params/h'),
      frameRate: fps != null && fps > 0 ? fps : null,
      bitDepth: pixelFormat == null
          ? null
          : int.tryParse(
                  RegExp(r'p0?(\d{2})(le|be)?$')
                          .firstMatch(pixelFormat)
                          ?.group(1) ??
                      '',
                ) ??
                8,
      colorMatrix: await read('video-params/colormatrix'),
      colorPrimaries: await read('video-params/primaries'),
      colorTransfer: await read('video-params/gamma'),
      audioCodec: await read('audio-codec-name'),
      audioChannels: await readInt('audio-params/channel-count'),
      audioChannelLayout: await read('audio-params/hr-channels'),
      audioSampleRate: await readInt('audio-params/samplerate'),
      subtitleFormat: await read('current-tracks/sub/codec'),
    );
    if (generation == _mediaInfoGeneration && !_mediaInfoController.isClosed) {
      _latestMediaInfo = info;
      _mediaInfoController.add(info);
    }
  }

  /// mpv reports this when the track it auto-selects at load has no decoder
  /// (e.g. TrueHD on the stock build) and keeps playing the rest. While another
  /// audio track exists the failure is held until [defaultsApplied] (the
  /// default track-selection pass for this file has finished); then it is only
  /// logged if another audio track is now selected, and emitted if not. A file
  /// with a single audio track fails at once.
  static const _audioDecoderInit = 'initialize a decoder for codec';
  bool _defaultsDone = false;
  String? _heldDecoderCodec;
  String? _heldDecoderMessage;

  /// Codec of the audio track mpv currently has selected (an `auto` choice
  /// resolves to the track mpv picked), read from the engine's track list.
  Future<String?> _selectedAudioCodec() async {
    final raw = await (_player.platform as mk.NativePlayer).getProperty(
      'track-list',
    );
    for (final t in jsonDecode(raw) as List) {
      if (t is Map && t['type'] == 'audio' && t['selected'] == true) {
        return t['codec'] as String?;
      }
    }
    return null;
  }

  bool get _hasOtherAudio =>
      _player.state.tracks.audio
          .where((t) => t.id != 'auto' && t.id != 'no')
          .length >
      1;

  Future<void> _resolveDecoderError(String codec, String message) async {
    // mpv drops a track whose decoder failed, so no selection at all also
    // means nobody replaced it.
    final now = await _selectedAudioCodec();
    if (now == null || now == codec) {
      _emitFailure(_classifyFailure(StateError(message), StackTrace.current));
    } else {
      _logger.warn('audio track not decodable but replaced: $message');
    }
  }

  String? _pendingVideoDecoderError;
  List<({bool video, bool resolved})> _decoderOpenLogs = [];

  void _onEngineLog(mk.PlayerLog entry) {
    if (entry.level == 'error' &&
        (entry.prefix == 'vd' || entry.prefix == 'ad') &&
        entry.text.trim() == 'Could not open codec.') {
      _decoderOpenLogs = [
        ..._decoderOpenLogs,
        (video: entry.prefix == 'vd', resolved: false),
      ];
    }
  }

  void _onVideoParams(mk.VideoParams params) {
    // video-params comes from a decoded frame, not the container's dimensions.
    if ((params.w ?? 0) > 0 &&
        (params.h ?? 0) > 0 &&
        (params.pixelformat?.isNotEmpty ?? false)) {
      _resolveVideoDecoderLogs();
      if (_pendingVideoDecoderError != null) {
        _logger.warn(
          'video decoder initialization recovered with decoded frames',
        );
        _pendingVideoDecoderError = null;
      }
    }
    _publishMediaInfo();
  }

  void _resolveVideoDecoderLogs() {
    _decoderOpenLogs = [
      for (final entry in _decoderOpenLogs)
        (video: entry.video, resolved: entry.resolved || entry.video),
    ];
  }

  void _onEngineError(String message) {
    // media_kit forwards log errors without their prefix. Keep the ordered
    // origins so an audio rejection with the same text remains a real failure.
    if (message.trim() == 'Could not open codec.' &&
        _decoderOpenLogs.isNotEmpty) {
      final entry = _decoderOpenLogs.first;
      _decoderOpenLogs = _decoderOpenLogs.skip(1).toList();
      if (entry.video) {
        if (!entry.resolved) _pendingVideoDecoderError = message;
        return;
      }
    }
    final codec = RegExp(r"codec '([^']+)'").firstMatch(message)?.group(1);
    if (message.contains(_audioDecoderInit) &&
        codec != null &&
        _hasOtherAudio) {
      if (_defaultsDone) {
        unawaited(_resolveDecoderError(codec, message));
      } else {
        _heldDecoderCodec = codec;
        _heldDecoderMessage = message;
      }
      return;
    }
    _emitFailure(_classifyFailure(StateError(message), StackTrace.current));
  }

  /// The default track-selection pass for the opened file is finished; a held
  /// audio decoder error is now resolved against the final selection.
  Future<void> defaultsApplied() async {
    _defaultsDone = true;
    final codec = _heldDecoderCodec;
    final message = _heldDecoderMessage;
    _heldDecoderCodec = null;
    _heldDecoderMessage = null;
    if (codec != null && message != null) {
      await _resolveDecoderError(codec, message);
    }
  }

  void _refreshFromPlayer() {
    _current = PlaybackState(
      position: _player.state.position,
      duration: _player.state.duration,
      bufferedAhead: Duration.zero,
      isPlaying: _player.state.playing,
      isBuffering: false,
      isCompleted: _player.state.completed,
      rate: _player.state.rate,
      tracks: mapTracks(_player.state.tracks),
      selected: mapSelection(_player.state.track),
      chapters: const <Chapter>[],
      // Opening metadata must not erase a terminal decoder error from this load.
      failure: _current.failure,
    );
    _emit(_current);
    _engineBuffer = _player.state.buffer;
    if (_engineBuffer > Duration.zero) {
      _emit(buffering.applyBuffered(_current, _engineBuffer));
    }
    _engineBuffering = _player.state.buffering;
    _bufferingDebouncer.update(
      engineBuffering: _engineBuffering,
      isPlaying: _current.isPlaying,
    );
  }

  Future<void> _loadNativeMetadata() async {
    final dynamic native = _player.platform;
    try {
      final rawChapters = await native.getProperty('chapter-list');
      final decoded = jsonDecode(rawChapters);
      if (decoded is List) {
        final chapters = <({Duration start, String? title})>[];
        for (final item in decoded) {
          if (item is! Map) continue;
          final time = (item['time'] as num?)?.toDouble();
          if (time == null || !time.isFinite || time < 0) continue;
          chapters.add((
            start: Duration(
              microseconds: (time * Duration.microsecondsPerSecond).round(),
            ),
            title: item['title']?.toString(),
          ));
        }
        _emit(_current.copyWith(chapters: mapChapters(chapters)));
      }
    } catch (error, stack) {
      _logger.warn('media chapters unavailable', error: error, stack: stack);
    }
    try {
      final fps = double.tryParse(await native.getProperty('container-fps'));
      if (fps != null && fps.isFinite && fps > 0) _containerFps = fps;
    } catch (error, stack) {
      _logger.warn('media fps unavailable', error: error, stack: stack);
    }
    try {
      final format = await native.getProperty('file-format');
      if (format is String && format.isNotEmpty) _containerFormat = format;
    } catch (error, stack) {
      _logger.warn(
        'media container metadata unavailable',
        error: error,
        stack: stack,
      );
    }
  }

  void _emit(PlaybackState value) {
    _current = value;
    if (!_stateController.isClosed) _stateController.add(value);
  }

  void _emitEvent(PlaybackEvent event) {
    if (!_eventController.isClosed) _eventController.add(event);
  }

  void _emitFailure(PlaybackFailure failure) {
    _pendingVideoDecoderError = null;
    _resolveVideoDecoderLogs();
    _emit(_current.copyWith(failure: failure));
    _emitEvent(PlaybackFailed(failure));
    _logger.failure(failure);
  }

  void _validateChoice(TrackChoice choice, List<Track> available) {
    if (choice.mode == TrackSelectionMode.specific &&
        !available.any((track) => track.id == choice.id)) {
      throw ArgumentError('Unknown track id: ${choice.id}');
    }
  }

  String _selectionId(TrackSelection selection) =>
      selection.video.id ??
      selection.audio.id ??
      selection.subtitle.id ??
      'auto';

  mk.VideoTrack _toVideo(TrackChoice choice) => switch (choice.mode) {
    TrackSelectionMode.auto => mk.VideoTrack.auto(),
    TrackSelectionMode.off => mk.VideoTrack.no(),
    TrackSelectionMode.specific => mk.VideoTrack(choice.id!, null, null),
  };

  mk.AudioTrack _toAudio(TrackChoice choice) => switch (choice.mode) {
    TrackSelectionMode.auto => mk.AudioTrack.auto(),
    TrackSelectionMode.off => mk.AudioTrack.no(),
    TrackSelectionMode.specific => mk.AudioTrack(choice.id!, null, null),
  };

  mk.SubtitleTrack _toSubtitle(TrackChoice choice) => switch (choice.mode) {
    TrackSelectionMode.auto => mk.SubtitleTrack.auto(),
    TrackSelectionMode.off => mk.SubtitleTrack.no(),
    TrackSelectionMode.specific => mk.SubtitleTrack(choice.id!, null, null),
  };

  void _checkUsable() {
    if (_disposed) throw StateError('PlaybackController used after dispose()');
  }

  void _requireOpen() {
    if (!_opened) throw StateError('PlaybackController has no open media');
  }

  PlaybackFailure _classifyFailure(Object error, StackTrace stack) {
    final message = error.toString().toLowerCase();
    if (message.contains('unsupported') && message.contains('codec')) {
      return PlaybackFailure.unsupportedCodec(
        codec: error.toString(),
        cause: error,
        stack: stack,
      );
    }
    if (message.contains('decode') || message.contains('demux')) {
      return PlaybackFailure.decodeFailed(cause: error, stack: stack);
    }
    if (message.contains('network') ||
        message.contains('connection') ||
        message.contains('http')) {
      return PlaybackFailure.sourceUnreachable(cause: error, stack: stack);
    }
    return PlaybackFailure.openFailed(cause: error, stack: stack);
  }
}

/// Converts a public URI to the resource form expected by media_kit.
///
/// media_kit accepts local files as filesystem paths; using [Uri.toString]
/// leaves percent-escaped spaces in the path passed to libmpv.
String mediaKitResourceFor(Uri uri) =>
    uri.isScheme('file') ? uri.toFilePath() : uri.toString();

/// Converts the public 0..1 volume contract to media_kit's 0..100 scale.
double mapVolumeToEngine(double volume) =>
    volume.clamp(0.0, 1.0).toDouble() * 100.0;

Duration clampSeekTarget(Duration position, {required Duration duration}) {
  if (position < Duration.zero) return Duration.zero;
  if (duration > Duration.zero && position > duration) return duration;
  return position;
}
