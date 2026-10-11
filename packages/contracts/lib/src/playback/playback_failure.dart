import 'package:core/core.dart';

/// Playback engine failures, `playback.*` prefix
/// (`planning/CONTRACTS.md` §0 registry, owned by Part 02).
///
/// Lives in `packages/contracts`, not `packages/playback`: it is a field of
/// [PlaybackState] and [PlaybackFailed], both contract types, so the
/// contract must be able to name it without depending downward on
/// `packages/playback`.
///
/// One class with a named constructor per failure kind, not a class per
/// kind — the leaves are values carried by [PlaybackState] and
/// [PlaybackFailed], so a small hierarchy would be ceremony.
final class PlaybackFailure extends AppFailure {
  const PlaybackFailure.openFailed({required super.cause, super.stack})
    : super(code: _openFailed, message: 'Failed to open the media');

  const PlaybackFailure.decodeFailed({required super.cause, super.stack})
    : super(code: _decodeFailed, message: 'Failed to decode the media');

  const PlaybackFailure.engineCrashed({required super.cause, super.stack})
    : super(code: _engineCrashed, message: 'The playback engine crashed');

  const PlaybackFailure.sourceUnreachable({required super.cause, super.stack})
    : super(
        code: _sourceUnreachable,
        message: 'The media source became unreachable',
      );

  const PlaybackFailure.unsupportedCodec({
    required String codec,
    super.cause,
    super.stack,
  }) : super(code: _unsupportedCodec, message: 'Unsupported codec: $codec');

  const PlaybackFailure.trackSelectionFailed({
    required String trackId,
    super.cause,
    super.stack,
  }) : super(
         code: _trackSelectionFailed,
         message: 'Failed to select playback track: $trackId',
       );

  const PlaybackFailure.subtitleLoadFailed({
    required Uri uri,
    required super.cause,
    super.stack,
  }) : super(
         code: _subtitleLoadFailed,
         message: 'Failed to load external subtitle: $uri',
       );

  static const String _openFailed = 'playback.open.failed';
  static const String _decodeFailed = 'playback.decode.failed';
  static const String _engineCrashed = 'playback.engine.crashed';
  static const String _sourceUnreachable = 'playback.source.unreachable';
  static const String _unsupportedCodec = 'playback.unsupported.codec';
  static const String _trackSelectionFailed = 'playback.track.selection_failed';
  static const String _subtitleLoadFailed = 'playback.subtitle.load_failed';
}
