import 'package:core/core.dart';

import '../l10n_gen/app_strings.dart';
import '../l10n_gen/app_strings_en.dart';

typedef FailureWarning = void Function(String code, AppFailure failure);

final Map<String, String Function(AppStrings)> _messages =
    <String, String Function(AppStrings)>{
      'transport.http.no_range_support': (s) =>
          s.failure_transportHttpNoRangeSupport,
      'transport.http.validator_changed': (s) =>
          s.failure_transportHttpValidatorChanged,
      'transport.http.unreachable': (s) => s.failure_transportHttpUnreachable,
      'transport.range.unsatisfiable': (s) =>
          s.failure_transportRangeUnsatisfiable,
      'transport.torrent.no_metadata': (s) =>
          s.failure_transportTorrentNoMetadata,
      'transport.torrent.no_peers': (s) => s.failure_transportTorrentNoPeers,
      'transport.torrent.stalled': (s) => s.failure_transportTorrentStalled,
      'transport.torrent.file_error': (s) =>
          s.failure_transportTorrentFileError,
      'transport.torrent.file_not_found': (s) =>
          s.failure_transportTorrentFileNotFound,
      'transport.engine.unavailable': (s) =>
          s.failure_transportEngineUnavailable,
      'transport.local.not_found': (s) => s.failure_transportLocalNotFound,
      'transport.local.not_readable': (s) =>
          s.failure_transportLocalNotReadable,
      'transport.local.empty': (s) => s.failure_transportLocalEmpty,
      'transport.local.unsupported_uri': (s) =>
          s.failure_transportLocalUnsupportedUri,
      'playback.open.failed': (s) => s.failure_playbackOpenFailed,
      'playback.decode.failed': (s) => s.failure_playbackDecodeFailed,
      'playback.engine.crashed': (s) => s.failure_playbackEngineCrashed,
      'playback.source.unreachable': (s) => s.failure_playbackSourceUnreachable,
      'playback.unsupported.codec': (s) => s.failure_playbackUnsupportedCodec,
      'playback.track.selection_failed': (s) =>
          s.failure_playbackTrackSelectionFailed,
      'playback.subtitle.load_failed': (s) =>
          s.failure_playbackSubtitleLoadFailed,
      'platform.unsupported': (s) => s.failure_platformUnsupported,
      'platform.permission_denied': (s) => s.failure_platformPermissionDenied,
      'platform.display.switch_failed': (s) =>
          s.failure_platformDisplaySwitchFailed,
      'platform.audio.device_lost': (s) => s.failure_platformAudioDeviceLost,
      'platform.probe.failed': (s) => s.failure_platformProbeFailed,
      'app.unexpected': (s) => s.failure_appUnexpected,
      'app.cancelled': (s) => s.failure_appCancelled,
    };

String messageForFailure(
  AppFailure failure, {
  AppStrings? strings,
  FailureWarning? onUnknown,
}) {
  final s = strings ?? AppStringsEn();
  final message = _messages[failure.code];
  if (message != null) return message(s);
  onUnknown?.call(failure.code, failure);
  return s.failure_unknown(failure.code);
}

Set<String> get knownFailureCodes => _messages.keys.toSet();
