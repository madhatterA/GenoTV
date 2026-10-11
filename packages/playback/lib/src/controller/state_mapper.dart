import 'package:contracts/contracts.dart';

/// media_kit observable -> contract mapping:
/// `position` -> `PlaybackState.position` (250 ms coalesced by the controller);
/// `duration` -> `duration`; `playing` -> `isPlaying`; `buffering` -> the
/// debounced `isBuffering` flag; `buffer` (absolute cache position) ->
/// `bufferedAhead`; `completed` -> `isCompleted` plus one `PlaybackEnded` event;
/// `tracks`/`track` -> `tracks`/`selected`; `error` -> `PlaybackFailure`.

PlaybackState applyPosition(PlaybackState state, Duration position) => state
    .copyWith(position: position < Duration.zero ? Duration.zero : position);

PlaybackState applyDuration(PlaybackState state, Duration duration) => state
    .copyWith(duration: duration < Duration.zero ? Duration.zero : duration);

PlaybackState applyPlaying(PlaybackState state, bool playing) => state.copyWith(
  isPlaying: playing,
  isBuffering: playing && state.isBuffering,
);

PlaybackState applyBuffering(PlaybackState state, bool buffering) =>
    state.copyWith(isBuffering: state.isPlaying && buffering);

PlaybackState applyCompleted(PlaybackState state, bool completed) =>
    state.copyWith(
      isCompleted: completed,
      isPlaying: completed ? false : state.isPlaying,
    );

PlaybackState applyBuffered(PlaybackState state, Duration buffer) {
  final ahead = buffer - state.position;
  final remaining = state.duration - state.position;
  final upper = remaining.isNegative ? Duration.zero : remaining;
  final value = ahead < Duration.zero ? Duration.zero : ahead;
  return state.copyWith(bufferedAhead: value > upper ? upper : value);
}

/// Picks one name from mpv's comma-separated `file-format` list: the entry
/// matching [path]'s extension (`.mkv` also matches `matroska`), else the first.
String? pickContainerFormat(String? formats, String path) {
  final entries = (formats ?? '').split(',').where((e) => e.isNotEmpty);
  if (entries.isEmpty) return null;
  final dot = path.lastIndexOf('.');
  final extension = dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  if (entries.contains(extension)) return extension;
  if (extension == 'mkv' && entries.contains('matroska')) return 'mkv';
  return entries.first;
}
