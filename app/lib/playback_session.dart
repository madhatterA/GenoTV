import 'dart:async';

import 'package:contracts/contracts.dart';
import 'package:core/core.dart';
import 'package:transport/transport.dart' show StreamSourceImpl;
import 'package:platform_services/platform_services.dart'
    show
        AudioOutputServiceImpl,
        audioOutputLine,
        detectAudioCapability,
        planAudio;
import 'package:playback/playback.dart'
    show applyPreferredTracks, engineDecoderCodecs;
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;

import 'platform_policy.dart';
import 'playback_insight.dart';
import 'player_settings.dart';
import 'transport_options.dart';

/// Ranks tracks by the fallback-chain step they reach on [model] (then by
/// channels, more first); null marks a track the engine cannot play.
int? Function(Track) audioRankFor(
  AudioOutputService audio,
  AudioCapabilityModel model,
  Set<String>? decoders,
) => (track) {
  final plan = audio.plan(track, model, decoders: decoders);
  return plan.step == AudioPlanStep.unplayable
      ? null
      : plan.step.index * 100 - plan.channels;
};

typedef PlaybackControllerFactory = PlaybackController Function();

/// The episode that follows the one just played, with its chosen source.
typedef NextEpisode = ({MediaItem media, SourceSpec source});

/// Owns one transport handle and one playback controller for one media item.
/// The seek hint is deliberately advisory: the engine's Range request remains
/// the authoritative transport demand.
final class PlaybackSession {
  PlaybackSession({
    required MediaItem media,
    required this.streamSource,
    required SourceSpec source,
    required this.controllerFactory,
    this.releaseController,
    this.progress,
    this.policy,
    this.settings,
    this.originalLanguage,
    this.askResume,
    this.nextSource,
    this.logger,
    this.insight,
  }) {
    _media = media;
    _source = source;
  }

  /// The item now playing; changes when auto-play moves to the next episode.
  MediaItem get media => _media;
  late MediaItem _media;
  final StreamSource streamSource;
  final PlaybackControllerFactory controllerFactory;
  final Future<void> Function(PlaybackController)? releaseController;
  final ProgressRepository? progress;
  final PlatformPolicy? policy;

  /// Language and subtitle-size defaults applied when a video opens.
  final AppSettings? settings;

  /// The title's TMDB original_language, used when the file has no original flag.
  final String? originalLanguage;

  /// The resume prompt for the "Ask" setting; true resumes at the position.
  /// Without one, Ask resumes (the detail screen's Resume / Play choice is
  /// the prompt).
  final Future<bool> Function(Duration position)? askResume;

  /// The episode after [current] and its source, null when there is none;
  /// used when a video ends and "Auto-play next episode" is on.
  final Future<NextEpisode?> Function(MediaItem current, SourceSpec source)?
  nextSource;
  final AppLogger? logger;

  /// Live diagnostics and custom-option notes for the Advanced page.
  final PlaybackInsight? insight;
  StreamSubscription<Map<String, String>>? _diagnosticsSubscription;

  // Background preload: the next episode and its already opened source.
  NextEpisode? _preloadNext;
  StreamHandle? _preloadHandle;
  Future<void>? _preloadFuture;
  bool _preloadTried = false;

  final StreamController<PlaybackSessionSnapshot> _updates =
      StreamController<PlaybackSessionSnapshot>.broadcast();
  PlaybackController? _controller;
  StreamHandle? _handle;
  StreamSubscription<PlaybackState>? _stateSubscription;
  StreamSubscription<PlaybackEvent>? _eventSubscription;
  StreamSubscription<SourceStatus>? _statusSubscription;
  StreamSubscription<MediaInfo>? _mediaInfoSubscription;
  StreamSubscription<SettingDef>? _settingsSubscription;
  bool _engineReady = false;
  bool _ending = false;
  AppFailure? _transitionFailure;
  PlaybackState _playback = PlaybackState.initial();
  SourceStatus? _sourceStatus;
  AppFailure? _progressFailure;
  bool _wasPlaying = false;
  bool _disposed = false;
  Map<String, Object> _audioNextVideo = const {};
  int _audioGeneration = 0;
  AudioPlan? _audioPlan;
  MediaInfo? _audioInfo;
  AudioCapabilityModel? _audioModel;
  AudioCapabilityModel? _pcmAudioModel;
  int _audioRouteGeneration = 0;
  Set<String>? _decoders;
  String? _audioLineId;
  final ValueNotifier<String?> _audioOutput = ValueNotifier<String?>(null);

  /// Plain-text audio path of the playing track, for the Info tab.
  ValueListenable<String?> get audioOutput => _audioOutput;
  late SourceSpec _source;

  /// Completes when the default track-selection pass for the opened file has
  /// finished (never throws).
  Future<void> defaultsDone = Future<void>.value();

  Stream<PlaybackSessionSnapshot> get updates => _updates.stream;
  PlaybackController? get controller => _controller;
  StreamHandle? get handle => _handle;

  /// The source being played now (changes when auto-play moves on).
  SourceSpec get source => _source;
  PlaybackSessionSnapshot get snapshot => PlaybackSessionSnapshot(
    playback: _playback,
    source: _sourceStatus,
    failure:
        _transitionFailure ??
        _sourceStatus?.failure ??
        _playback.failure ??
        _progressFailure,
  );

  Future<void> start({
    Map<String, String> headers = const {},
    Duration? resumeAt,
    double? contentFps,
    int? width,
    int? height,
    AudioStreamSpec? audioSpec,
  }) async {
    if (_disposed) {
      throw StateError('playback session is disposed');
    }
    if (_controller != null) {
      throw StateError('playback session already started');
    }

    _transitionFailure = null;
    final values = settings?.values;
    _audioNextVideo = values == null
        ? const {}
        : {
            for (final def in audioSettingDefs)
              if (def.apply != SettingApply.live)
                def.id: values.read<Object>(def),
          };
    final remember = values == null || rememberPositionOf(values);
    PlaybackProgress? saved;
    try {
      if (remember) saved = await progress?.get(media.id);
    } catch (error, stack) {
      _progressFailure = UnexpectedFailure(cause: error, stack: stack);
      _emit();
    }
    _preloadTried = false;
    final preloaded = _preloadHandle;
    final StreamHandle handle;
    if (preloaded != null && identical(_preloadNext?.source, _source)) {
      handle = preloaded;
      _preloadHandle = null;
      _preloadNext = null;
    } else {
      await _dropPreload();
      handle = await streamSource.open(
        _source,
        options: values == null
            ? const TransportOptions()
            : transportOptionsFor(values),
      );
    }
    final controller = controllerFactory();
    _handle = handle;
    _controller = controller;
    _stateSubscription = controller.state.listen(_onState);
    _eventSubscription = controller.events.listen(_onEvent);
    _statusSubscription = handle.status.listen(_onSourceStatus);
    _mediaInfoSubscription = controller.mediaInfo.listen(_onMediaInfo);
    try {
      await policy?.start(
        controller: controller,
        contentFps: contentFps,
        width: width,
        height: height,
        audioSpec: audioSpec,
      );
      // A retained engine still holds the previous video's audio-spdif/channels;
      // a stale pass-through decoder would be selected at open and never start.
      if (values != null) {
        await _applyAudioSettings(controller, values, beforeOpen: true);
      }
      await controller.open(
        handle.playbackUri,
        headers: headers.isEmpty ? _source.headers : headers,
        startAt: resumeAt ?? await _resumePosition(saved, values),
        engineOptions: values == null
            ? const {}
            : {
                ...engineOptionsFor(
                  values,
                  scope: changedEngineSettings(values),
                ),
                ...subtitleEngineOptionsFor(values),
              },
      );
      _engineReady = true;
      _diagnosticsSubscription = controller.diagnostics.listen(
        (raw) => insight?.update(raw),
      );
      if (values != null) await _applyCustomOptions(controller, values);
      if (values != null) await _applyAudioSettings(controller, values);
      if (values != null) {
        _settingsSubscription = values.changes.listen(
          (def) => _onSettingChanged(controller, values, def),
        );
      }
      defaultsDone = _applyDefaults(controller, saved);
      _emit();
    } catch (_) {
      await _closeCurrent();
      rethrow;
    }
  }

  /// Applies the Advanced custom mpv options last, so they win. A line mpv
  /// rejects is listed under the field; playback is not affected.
  Future<void> _applyCustomOptions(
    PlaybackController controller,
    SettingsValues values,
  ) async {
    final parsed = parseCustomMpvOptions(
      values.read<String>(settingById('advanced.customMpvOptions')),
    );
    final rejected = {
      ...parsed.malformed,
      ...await controller.applyUserOptions(parsed.options),
    };
    insight?.customOptionsNote.value = rejected.isEmpty
        ? null
        : 'Rejected: ${rejected.entries.map((e) => '${e.key} (${e.value})').join('; ')}';
  }

  Future<Duration?> _resumePosition(
    PlaybackProgress? saved,
    SettingsValues? values,
  ) async {
    if (saved == null) return null;
    // Kodi 6.1 advanced defaults: ignore the first 180 s and the last 8 %.
    if (saved.position < const Duration(seconds: 180) ||
        saved.position >= saved.duration * 0.92) {
      return null;
    }
    final mode = values == null ? ResumeMode.ask : resumeModeOf(values);
    return switch (mode) {
      ResumeMode.always => saved.position,
      ResumeMode.never => null,
      ResumeMode.ask =>
        askResume == null || await askResume!(saved.position)
            ? saved.position
            : null,
    };
  }

  /// Applies a changed setting to the open video when it is a live one; a
  /// next-video setting waits for the next open. The engine reports a
  /// rejected value as a playback failure; the setting keeps the user's value.
  void _onSettingChanged(
    PlaybackController controller,
    SettingsValues values,
    SettingDef def,
  ) {
    final source = streamSource;
    if (def.target is TransportOption &&
        def.apply == SettingApply.live &&
        source is StreamSourceImpl) {
      unawaited(
        source
            .applyGlobalOptions(transportOptionsFor(values))
            .catchError(
              (Object error, StackTrace stack) => logger?.error(
                'applying transport setting ${def.id} failed',
                error: error,
                stack: stack,
              ),
            ),
      );
      return;
    }
    if (_engineReady && subtitleSettingDefs.contains(def)) {
      unawaited(
        controller
            .setEngineOptions(subtitleEngineOptionsFor(values, scope: {def}))
            .catchError((Object error, StackTrace stack) {
              logger?.error(
                'applying subtitle setting ${def.id} failed',
                error: error,
                stack: stack,
              );
              _transitionFailure = error is AppFailure
                  ? error
                  : UnexpectedFailure(cause: error, stack: stack);
              _emit();
            }),
      );
      return;
    }
    if (_engineReady &&
        audioSettingDefs.contains(def) &&
        def.apply == SettingApply.live) {
      if (def.id == 'audio.outputDevice' && policy?.audio != null) {
        unawaited(
          _refreshAudioDevice(controller, values).catchError((
            Object error,
            StackTrace stack,
          ) {
            logger?.error(
              'refreshing audio output failed',
              error: error,
              stack: stack,
            );
            _transitionFailure = error is AppFailure
                ? error
                : UnexpectedFailure(cause: error, stack: stack);
            _emit();
          }),
        );
        return;
      }
      _audioLineId = null;
      _updateAudioLine(controller.currentState);
      if (_audioPlan == null) {
        unawaited(
          _applyAudioSettings(controller, values).catchError(
            (Object error, StackTrace stack) => logger?.error(
              'applying audio setting failed',
              error: error,
              stack: stack,
            ),
          ),
        );
      }
      return;
    }
    if (!_engineReady ||
        def.apply != SettingApply.live ||
        !engineSettingDefs.contains(def)) {
      return;
    }
    unawaited(
      controller
          .setEngineOptions(engineOptionsFor(values, scope: {def}))
          .catchError(
            (Object error, StackTrace stack) => logger?.error(
              'applying setting ${def.id} failed',
              error: error,
              stack: stack,
            ),
          ),
    );
  }

  Future<void> _applyDefaults(
    PlaybackController controller,
    PlaybackProgress? saved,
  ) async {
    final defaults = settings;
    PlayerLanguage? language(String? code) =>
        playerLanguages.where((l) => l.code == code).firstOrNull;
    // The session can end (or switch controllers) while these awaits run; that
    // is a normal end of this pass, not a failure to warn about.
    bool stale() => _disposed || _controller != controller;
    void warn(String what, Object error, StackTrace stack) {
      if (!stale()) logger?.warn(what, error: error, stack: stack);
    }

    // Each step is isolated so applyPreferredTracks always runs: it also tells
    // the engine the default track pass is finished.
    int? Function(Track)? rank;
    try {
      rank = await _audioRank(controller);
    } catch (error, stack) {
      warn('ranking audio tracks failed', error, stack);
    }
    try {
      if (defaults != null) {
        await controller.setEngineOptions(
          subtitleEngineOptionsFor(defaults.values),
        );
      }
    } catch (error, stack) {
      warn('applying subtitle size default failed', error, stack);
    }
    if (stale()) return;
    try {
      await applyPreferredTracks(
        controller,
        audioRank: rank,
        rules: defaults == null
            ? null
            : trackRulesFor(
                defaults.values,
                logger: logger,
                nextVideo: _audioNextVideo,
              ),
        savedAudioTrackId: saved?.audioTrackId,
        savedSubtitleTrackId: saved?.subtitleTrackId,
        originalLanguage: _media.originalLanguage ?? originalLanguage,
        audio: language(defaults?.preferredAudioLanguage),
        subtitle: language(defaults?.preferredSubtitleLanguage),
      );
    } catch (error, stack) {
      warn('applying language defaults failed', error, stack);
    }
    if (stale()) return;
    // Covers files whose tracks never change after the model is ready.
    _updateAudioLine(controller.currentState);
  }

  /// Orders audio tracks by the fallback-chain step they reach on the current
  /// output (then by channels); null marks a track this engine cannot play.
  /// Null when there is no platform policy to read the output from.
  Future<(AudioCapabilityModel, AudioCapabilityModel)>
  _detectAudioModels() async {
    final audio = policy!.audio;
    final values = settings?.values;
    final pcmId =
        values?.read<String>(settingById('audio.outputDevice')) ?? 'auto';
    final passthrough =
        _audioNextVideo['audio.passthroughDevice'] as String? ?? '';
    final pcm = await detectAudioCapability(audio, deviceId: pcmId);
    final bitstream = passthrough.isEmpty || passthrough == pcmId
        ? pcm
        : await detectAudioCapability(audio, deviceId: passthrough);
    return (pcm, bitstream);
  }

  Future<void> _refreshAudioDevice(
    PlaybackController controller,
    SettingsValues values,
  ) async {
    final generation = ++_audioRouteGeneration;
    final models = await _detectAudioModels();
    if (!_engineReady ||
        !identical(controller, _controller) ||
        generation != _audioRouteGeneration) {
      return;
    }
    _pcmAudioModel = models.$1;
    _audioModel = models.$2;
    _audioLineId = null;
    _updateAudioLine(controller.currentState);
    if (_audioPlan == null) await _applyAudioSettings(controller, values);
  }

  Future<void> _applyAudioSettings(
    PlaybackController controller,
    SettingsValues values, {
    AudioPlan? plan,
    MediaInfo? info,
    bool beforeOpen = false,
  }) async {
    final generation = ++_audioGeneration;
    final audio = policy?.audio;
    final devices = audio is AudioOutputServiceImpl
        ? await audio.devices(
            passthroughDeviceId:
                _audioNextVideo['audio.passthroughDevice'] as String?,
          )
        : audio == null
        ? <AudioDevice>[]
        : await audio.devices();
    if (!(_engineReady || beforeOpen) ||
        !identical(controller, _controller) ||
        generation != _audioGeneration) {
      return;
    }
    plan = _audioPlan ?? plan;
    info = _audioInfo ?? info;
    final bitstream =
        plan != null &&
        const {
          AudioPlanStep.bitstream,
          AudioPlanStep.dtsCore,
          AudioPlanStep.ac3Encode,
        }.contains(plan.step);
    final device = selectedAudioDevice(
      values,
      devices,
      bitstream: bitstream,
      logger: logger,
      nextVideo: _audioNextVideo,
    );
    await controller.setEngineOptions(
      audioEngineOptionsFor(
        values,
        plan: plan,
        info: info,
        device: device,
        deviceId: selectedAudioDeviceId(
          values,
          devices,
          bitstream: bitstream,
          nextVideo: _audioNextVideo,
          passthroughDefault: audio is AudioOutputServiceImpl
              ? audio.passthroughDeviceId
              : null,
        ),
        nextVideo: _audioNextVideo,
      ),
    );
  }

  int? get _sessionMaxChannels {
    final audio = policy?.audio;
    return audio is AudioOutputServiceImpl ? audio.maxOutputChannels : null;
  }

  Future<int? Function(Track)?> _audioRank(
    PlaybackController controller,
  ) async {
    final audio = policy?.audio;
    if (audio == null) return null;
    final models = await _detectAudioModels();
    _pcmAudioModel = models.$1;
    final model = _audioModel = models.$2;
    final decoders = _decoders = await engineDecoderCodecs(controller);
    final values = settings?.values;
    if (values == null) return audioRankFor(audio, model, decoders);
    return (track) {
      final plan = planAudio(
        track,
        model,
        pcmModel: models.$1,
        decoders: decoders,
        overrides: audioPlanOverridesFor(
          values,
          maxChannels: _sessionMaxChannels,
          nextVideo: _audioNextVideo,
        ),
      );
      return plan.step == AudioPlanStep.unplayable
          ? null
          : plan.step.index * 100 - plan.channels;
    };
  }

  /// Starts a new source after disposing the old controller and handle.
  Future<void> switchSource(SourceSpec next, {MediaItem? media}) async {
    if (_disposed) throw StateError('playback session is disposed');
    final resumeAt = media == null
        ? _controller?.currentState.position ?? _playback.position
        : null;
    await _closeCurrent();
    if (media != null) _media = media;
    _source = next;
    await start(resumeAt: resumeAt);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _preloadFuture;
    await _dropPreload();
    await _closeCurrent();
    await _updates.close();
  }

  Future<void> _closeCurrent() async {
    await _stateSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _statusSubscription?.cancel();
    await _mediaInfoSubscription?.cancel();
    await _settingsSubscription?.cancel();
    _settingsSubscription = null;
    await _diagnosticsSubscription?.cancel();
    _diagnosticsSubscription = null;
    insight?.update(const {});
    _engineReady = false;
    _mediaInfoSubscription = null;
    _stateSubscription = null;
    _eventSubscription = null;
    _statusSubscription = null;
    _audioOutput.value = null;
    _audioLineId = null;
    _audioPlan = null;
    _audioInfo = null;
    await policy?.stop();
    if (progress != null && _controller != null) {
      await _saveProgress();
    }
    final controller = _controller;
    _controller = null;
    // Listeners rebind to the controller that replaces this one.
    _emit();
    if (controller != null) {
      final release = releaseController;
      if (release == null) {
        await controller.dispose();
      } else {
        await release(controller);
      }
    }
    final handle = _handle;
    _handle = null;
    if (handle != null) await handle.dispose();
  }

  void _onState(PlaybackState state) {
    final stopped = _wasPlaying && !state.isPlaying;
    _wasPlaying = state.isPlaying;
    _playback = state;
    _updateAudioLine(state);
    _emit();
    if (stopped) unawaited(_saveProgress());
    _maybePreload(state);
  }

  /// "Background preloading": at the watched threshold (90 %) the next
  /// episode's source is opened so transport starts fetching; the opened
  /// source is handed to the next playback.
  void _maybePreload(PlaybackState state) {
    final values = settings?.values;
    final next = nextSource;
    if (values == null ||
        next == null ||
        _preloadTried ||
        !_engineReady ||
        !values.read<bool>(settingById('performance.backgroundPreload')) ||
        state.duration <= Duration.zero ||
        state.position < state.duration * 0.9) {
      return;
    }
    _preloadTried = true;
    _preloadFuture = _preload(next, values);
  }

  Future<void> _preload(
    Future<NextEpisode?> Function(MediaItem, SourceSpec) next,
    SettingsValues values,
  ) async {
    try {
      final following = await next(_media, _source);
      if (following == null || _disposed) return;
      final handle = await streamSource.open(
        following.source,
        options: transportOptionsFor(values),
      );
      if (_disposed) {
        await handle.dispose();
        return;
      }
      _preloadNext = following;
      _preloadHandle = handle;
    } catch (error, stack) {
      logger?.warn(
        'preloading the next episode failed',
        error: error,
        stack: stack,
      );
    }
  }

  Future<void> _dropPreload() async {
    final handle = _preloadHandle;
    _preloadHandle = null;
    _preloadNext = null;
    if (handle != null) await handle.dispose();
  }

  /// Shows the playing audio track's output path in the Info tab.
  void _updateAudioLine(PlaybackState state) {
    final audio = policy?.audio;
    final model = _audioModel;
    final id = state.selected.audio.id;
    if (audio == null || model == null || id == _audioLineId) return;
    _audioLineId = id;
    final track = state.tracks.audio.where((t) => t.id == id).firstOrNull;
    if (track == null) {
      _audioOutput.value = null;
      return;
    }
    final values = settings?.values;
    final plan = _audioPlan = values == null
        ? audio.plan(
            track,
            model,
            channels: _audioInfo?.audioChannels,
            decoders: _decoders,
          )
        : planAudio(
            track,
            model,
            pcmModel: _pcmAudioModel,
            channels: audioFilterOutputChannelsFor(
              values,
              sourceChannels: _audioInfo?.audioChannels,
              maxChannels: _sessionMaxChannels,
              model: model,
              nextVideo: _audioNextVideo,
            ),
            decoders: _decoders,
            overrides: audioPlanOverridesFor(
              values,
              maxChannels: _sessionMaxChannels,
              nextVideo: _audioNextVideo,
            ),
          );
    _audioOutput.value = audioOutputLine(track, plan);
    final controller = _controller;
    if (controller == null) return;
    unawaited(
      (values == null
              ? controller.setAudioOutput(plan)
              : _applyAudioSettings(controller, values, plan: plan))
          .catchError(
            (Object error, StackTrace stack) => logger?.error(
              'applying audio output plan failed',
              error: error,
              stack: stack,
            ),
          ),
    );
  }

  /// The engine only knows the frame rate once the file is open, so the
  /// display is matched from the first media info that carries one; the lease
  /// is released by the policy's stop.
  void _onMediaInfo(MediaInfo info) {
    final channelsChanged = _audioInfo?.audioChannels != info.audioChannels;
    _audioInfo = info;
    if (channelsChanged && _engineReady && _controller != null) {
      _audioLineId = null;
      _updateAudioLine(_controller!.currentState);
    }
    final controller = _controller;
    final values = settings?.values;
    if (_engineReady && controller != null && values != null) {
      unawaited(
        _applyAudioSettings(controller, values, info: info).catchError(
          (Object error, StackTrace stack) => logger?.error(
            'applying audio sample rate failed',
            error: error,
            stack: stack,
          ),
        ),
      );
    }
    final fps = info.frameRate;
    final p = policy;
    if (p == null || fps == null || fps <= 0) return;
    unawaited(
      p
          .matchDisplay(contentFps: fps, width: info.width, height: info.height)
          .catchError(
            (Object error, StackTrace stack) => logger?.error(
              'display matching failed',
              error: error,
              stack: stack,
            ),
          ),
    );
  }

  void _onSourceStatus(SourceStatus status) {
    _sourceStatus = status;
    _emit();
  }

  void _onEvent(PlaybackEvent event) {
    if (event is SeekRequested) unawaited(_hintSeek(event.to));
    if (event is PlaybackEnded) unawaited(_onEnded());
    _emit();
  }

  Future<void> _onEnded() async {
    if (_ending || _disposed) return;
    _ending = true;
    final outgoing = _controller;
    try {
      await _saveProgress(completed: true);
      final values = settings?.values;
      final next = nextSource;
      if (values == null || next == null || !autoPlayNextOf(values)) return;
      await _preloadFuture;
      final following = _preloadNext ?? await next(_media, _source);
      if (following == null || _disposed || outgoing != _controller) return;
      await switchSource(following.source, media: following.media);
      await _controller?.play();
    } catch (error, stack) {
      if (_disposed || (outgoing != _controller && _controller != null)) return;
      _transitionFailure = error is AppFailure
          ? error
          : UnexpectedFailure(cause: error, stack: stack);
      _emit();
      logger?.error(
        'starting the next episode failed',
        error: error,
        stack: stack,
      );
    } finally {
      _ending = false;
    }
  }

  Future<void> _hintSeek(Duration requested) async {
    final handle = _handle;
    final duration = _controller?.currentState.duration ?? _playback.duration;
    final totalBytes = handle?.totalBytes;
    if (handle == null || totalBytes == null || duration <= Duration.zero) {
      return;
    }
    final bounded = requested < Duration.zero
        ? Duration.zero
        : requested > duration
        ? duration
        : requested;
    // Estimate only: VBR content makes time-to-byte inexact by design.
    final offset =
        (totalBytes.toDouble() *
                bounded.inMicroseconds /
                duration.inMicroseconds)
            .round();
    await handle.seekHint(offset);
  }

  Future<void> _saveProgress({bool completed = false}) async {
    final repository = progress;
    final values = settings?.values;
    if (repository == null ||
        _controller == null ||
        (values != null && !rememberPositionOf(values))) {
      return;
    }
    try {
      final selected = _playback.selected;
      await repository.upsert(
        PlaybackProgress(
          mediaId: media.id,
          position: _playback.position,
          duration: _playback.duration,
          updatedAt: DateTime.now().toUtc(),
          // Kodi 6.1: watched from 90 %.
          completed:
              completed ||
              _playback.isCompleted ||
              (_playback.duration > Duration.zero &&
                  _playback.position >= _playback.duration * 0.9),
          audioTrackId: selected.audio.id,
          subtitleTrackId: selected.subtitle.id,
        ),
      );
    } catch (error, stack) {
      _progressFailure = UnexpectedFailure(cause: error, stack: stack);
      _emit();
    }
  }

  void _emit() {
    if (!_updates.isClosed) _updates.add(snapshot);
  }
}

final class PlaybackSessionSnapshot {
  const PlaybackSessionSnapshot({
    required this.playback,
    required this.source,
    this.failure,
  });

  final PlaybackState playback;
  final SourceStatus? source;
  final AppFailure? failure;
}
