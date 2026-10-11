import '../platform/audio_plan.dart';
import 'media_info.dart';
import 'playback_event.dart';
import 'playback_state.dart';
import 'track.dart';

/// Provided by Part 02, over media_kit/libmpv. Consumed by Part 04 and
/// Part 07. Part 02 never learns whether a `Uri` is a torrent — it only
/// ever sees the localhost URI a `StreamHandle` hands it
/// (`planning/CONTRACTS.md` §3).
abstract interface class PlaybackController {
  /// [engineOptions] are mpv properties (name -> value) applied before the
  /// media loads. A rejected option fails the open with a [PlaybackFailure].
  Future<void> open(
    Uri uri, {
    Map<String, String> headers,
    Duration? startAt,
    Map<String, String> engineOptions,
  });
  Future<void> play();
  Future<void> pause();

  /// Emits [SeekRequested] on [events] before the engine is asked to seek.
  /// See [SeekRequested]'s doc comment for why.
  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  /// 0.0-1.0.
  Future<void> setVolume(double volume);

  /// Subtitle delay in seconds, from -10 to +10.
  Future<void> setSubtitleDelay(Duration delay);

  /// Audio delay in seconds, from -5 to +5.
  Future<void> setAudioDelay(Duration delay);

  /// Positive, finite subtitle font multiplier (at most 100); normal is 1.
  Future<void> setSubtitleScale(double scale);

  /// Vertical screen percentage, 0–100; original bottom position is 100.
  Future<void> setSubtitlePosition(int percent);

  /// Sets mpv properties (name -> value) on the running engine. Throws, and
  /// emits a [PlaybackFailure], if the engine rejects any of them.
  Future<void> setEngineOptions(Map<String, String> options);

  /// Applies user-written mpv options to the running engine one by one, in
  /// order, and returns the rejected ones as option name -> mpv's error text.
  /// A rejection never emits a [PlaybackFailure] and never stops playback.
  Future<Map<String, String>> applyUserOptions(Map<String, String> options);

  /// Live engine facts as mpv property name -> mpv's own value text, from
  /// property observers (no polling). Emits the full latest map when an
  /// observed property changes; an empty map means nothing is open.
  /// Broadcast, coalesced.
  Stream<Map<String, String>> get diagnostics;

  /// null = Auto; otherwise 16:9, 4:3, 21:9 or 2.39:1.
  Future<void> setAspectRatio(String? ratio);

  /// Crop to fill the video output when enabled.
  Future<void> setFillScreen(bool enabled);

  /// Applies [plan]'s mpv `audio-spdif`, `audio-channels` and `af` values to
  /// the engine. Throws if the engine does not accept any of them.
  Future<void> setAudioOutput(AudioPlan plan);
  Future<void> selectTrack(TrackSelection selection);
  Future<void> addExternalSubtitle(Uri uri, {String? title});

  /// Broadcast, coalesced: a fast burst of engine updates collapses to the
  /// latest state, not every intermediate one.
  Stream<PlaybackState> get state;

  /// Discrete, never coalesced: every event is delivered.
  Stream<PlaybackEvent> get events;

  /// Broadcast: the latest technical facts about the open media, re-emitted
  /// when a track changes. Unknown fields are null.
  Stream<MediaInfo> get mediaInfo;

  PlaybackState get currentState;

  /// Releases native resources deterministically, not at GC time.
  Future<void> dispose();
}
