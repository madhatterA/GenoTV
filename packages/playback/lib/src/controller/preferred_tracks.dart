import 'package:contracts/contracts.dart';
import 'package:core/core.dart';

import 'media_kit_playback_controller.dart';

/// Codec names the engine behind [controller] can decode, or null when the
/// controller is not the mpv one (unknown, so nothing is declared unplayable).
Future<Set<String>?> engineDecoderCodecs(PlaybackController controller) async =>
    controller is MediaKitPlaybackController
    ? controller.decoderCodecs()
    : null;

/// Applies the viewer's language defaults once the engine has reported the
/// file's tracks: the first audio/subtitle track whose language tag matches is
/// selected; no match (or a null preference) leaves the engine default.
/// [audioRank] orders the tracks that match the audio language (lower is
/// better, null is unplayable); an unplayable or commentary track is passed
/// over while another match exists. Runs once, right after open, so
/// a track the viewer picks later is never replaced.
/// Completes without selecting anything if the controller closes first.
/// Frozen once per video. Tokens are ordered lexicographically; saved tracks
/// and playable-track filtering always precede these preferences.
class TrackRules {
  TrackRules({
    this.audioLanguage,
    this.subtitleLanguage,
    this.preferOriginal = false,
    this.autoSubtitles = true,
    this.hearingImpaired = 'No preference',
    this.preferForced = false,
    this.forcedBehaviour = 'Auto',
    this.allowAtmos = true,
    Set<String> passthroughCodecs = const {},
    List<String> quality = const [],
    List<String> priority = const [],
  }) : passthroughCodecs = Set.unmodifiable(passthroughCodecs),
       quality = List.unmodifiable(quality),
       priority = List.unmodifiable(priority);

  final PlayerLanguage? audioLanguage, subtitleLanguage;
  final bool preferOriginal, autoSubtitles, preferForced, allowAtmos;
  final String hearingImpaired, forcedBehaviour;
  final List<String> quality, priority;
  final Set<String> passthroughCodecs;

  TrackSelection select(
    PlaybackState state,
    Map<String, Map<String, dynamic>> metadata, {
    int? Function(Track)? audioRank,
    Set<String>? decoders,
    String? savedAudioTrackId,
    String? savedSubtitleTrackId,
    String? originalLanguage,
  }) {
    Map<String, dynamic> data(Track t) =>
        metadata['${t.type == TrackType.subtitle ? 'sub' : t.type.name}/${t.id}'] ??
        const {};
    bool flag(Track t, String key) => data(t)[key] == true;
    bool matches(Track t, String? code) =>
        code != null &&
        (t.language == code ||
            playerLanguages.any(
              (l) => l.code == code && l.matches(t.language),
            ));
    // Original audio is the mpv flag when any track carries it, else the
    // title's original language (TMDB) supplied by the caller.
    final hasOriginalFlag = state.tracks.audio.any((t) => flag(t, 'original'));
    bool isOriginal(Track t) =>
        hasOriginalFlag ? flag(t, 'original') : matches(t, originalLanguage);
    // Hearing-impaired is the mpv flag, else how release groups label it.
    bool isHearingImpaired(Track t) =>
        flag(t, 'hearing-impaired') ||
        RegExp(
          r'\b(SDH|CC|hearing[ -]impaired)\b',
          caseSensitive: false,
        ).hasMatch(t.title ?? '');
    int channels(Track t) =>
        (data(t)['demux-channel-count'] as num? ?? 0).toInt().clamp(0, 64);
    int codecPriority(Track t) {
      final codec = (t.codec ?? '').toLowerCase();
      final title = (t.title ?? '').toLowerCase();
      final profile = (data(t)['codec-profile'] as String? ?? '').toLowerCase();
      if (codec == 'dts') {
        final rank = switch (profile) {
          'dts-hd ma' => 12,
          'dts-hd hra' => 10,
          'dts-es' || 'dts 96/24' => 6,
          'dts express' => 1,
          _ => null,
        };
        if (rank != null) return rank;
      }
      if (codec == 'aac' && (profile == 'he-aac' || profile == 'he-aacv2')) {
        return 2;
      }
      if (allowAtmos &&
          ((codec == 'truehd' && title.contains('atmos')) ||
              title.contains('dts:x') ||
              title.contains('dts-x'))) {
        return 13;
      }
      if (codec == 'eac3' && allowAtmos && title.contains('atmos')) return 8;
      if (codec.startsWith('pcm_')) {
        if (RegExp(r'^pcm_[suf](24|32|64)').hasMatch(codec)) return 11;
        if (RegExp(r'^pcm_[suf]16').hasMatch(codec)) return 7;
        if (const {
          'pcm_s8',
          'pcm_u8',
          'pcm_alaw',
          'pcm_mulaw',
        }.contains(codec)) {
          return 1;
        }
      }
      return switch (codec) {
        'truehd_atmos' || 'dtshd_ma_x_imax' || 'dtshd_ma_x' => 13,
        'truehd' || 'dtshd_ma' || 'mlp' => 12,
        'flac' || 'alac' || 'ape' || 'wavpack' || 'pcm_bluray' => 11,
        'dtshd_hra' => 10,
        'dtshd' || 'dts-hd' || 'dts_hd' => 9,
        'eac3_ddp_atmos' => 8,
        'pcm' || 'pcm_dvd' => 7,
        'ac4' || 'dts_es' || 'dts_96_24' => 6,
        'eac3' || 'opus' => 5,
        'dts' => 4,
        'aac_lc' ||
        'aac' ||
        'aac_latm' ||
        'aac_ltp' ||
        'aac_ssr' ||
        'vorbis' ||
        'wmapro' => 3,
        'ac3' || 'he_aac' || 'he_aac_v2' => 2,
        'mp3' || 'mp2' || 'mp1' || 'wmav2' || 'dts_express' => 1,
        _ => 0,
      };
    }

    // Kodi: surround first; codec then channels for surround, reversed for stereo.
    int qualityScore(Track t) => channels(t) > 2
        ? -(100000 + codecPriority(t) * 100 + channels(t))
        : -(channels(t) * 100 + codecPriority(t));
    int score(Track t, String token) {
      if (token.startsWith('lang:')) {
        return matches(t, token.substring(5)) ? 0 : 1;
      }
      return switch (token) {
        'original' => isOriginal(t) ? 0 : 1,
        'atmos' =>
          allowAtmos && (t.title ?? '').toLowerCase().contains('atmos') ? 0 : 1,
        'lossless' =>
          const {
                    'truehd',
                    'mlp',
                    'flac',
                    'alac',
                    'dts-hd',
                    'dts_hd',
                  }.contains(t.codec) ||
                  (t.codec ?? '').startsWith('pcm_')
              ? 0
              : 1,
        'channels' => -channels(t),
        'quality' => qualityScore(t),
        'default' => t.isDefault ? 0 : 1,
        _ => 0,
      };
    }

    final playable = state.tracks.audio
        .where(
          (t) => audioRank != null
              ? audioRank(t) != null
              : decoders == null ||
                    decoders.contains(
                      (t.codec == 'dts-hd' || t.codec == 'dtshd')
                          ? 'dts'
                          : t.codec,
                    ) ||
                    passthroughCodecs.contains(t.codec),
        )
        .toList();
    final savedAudio = playable
        .where((t) => t.id == savedAudioTrackId)
        .firstOrNull;
    final main = playable
        .where((t) => !(t.title ?? '').toLowerCase().contains('commentary'))
        .toList();
    final pool = main.isEmpty ? playable : main;
    final original = pool.where(isOriginal).firstOrNull;
    final lang = preferOriginal && original != null
        ? original.language
        : audioLanguage?.code;
    final tokens = priority.isNotEmpty
        ? priority
        : [
            if (preferOriginal && original != null) 'original',
            if (lang != null) 'lang:$lang',
            for (final q in quality)
              if (q != 'highest-channel') q.toLowerCase(),
            if (quality.isNotEmpty) 'quality',
            'default',
          ];
    // Stable order makes the first track the final tie-breaker.
    Track? best = pool.firstOrNull;
    for (final t in pool.skip(1)) {
      for (final token in tokens) {
        final difference = score(t, token) - score(best!, token);
        if (difference < 0) best = t;
        if (difference != 0) break;
      }
    }
    final audio = savedAudio ?? best;
    final selectedAudioLanguage =
        audio?.language ??
        state.tracks.audio
            .where((t) => t.id == state.selected.audio.id)
            .firstOrNull
            ?.language;
    final savedSub = state.tracks.subtitle
        .where((t) => t.id == savedSubtitleTrackId)
        .firstOrNull;
    final available = state.tracks.subtitle
        .where((t) => forcedBehaviour != 'Never' || !flag(t, 'forced'))
        .toList();
    final forcedAudio = available
        .where((t) => flag(t, 'forced') && t.language == selectedAudioLanguage)
        .firstOrNull;
    final languageSubs = available
        .where((t) => subtitleLanguage?.matches(t.language) == true)
        .toList();
    Track? sub;
    if (!autoSubtitles) {
      sub = preferForced ? forcedAudio : null;
    } else if (subtitleLanguage?.code == 'forced_only') {
      sub = forcedAudio;
    } else {
      if (preferForced || forcedBehaviour == 'Always') {
        sub =
            languageSubs.where((t) => flag(t, 'forced')).firstOrNull ??
            forcedAudio;
      }
      if (sub == null && languageSubs.isNotEmpty) {
        final regular = languageSubs.where((t) => !flag(t, 'forced')).toList();
        final candidates = regular.isEmpty ? languageSubs : regular;
        sub = hearingImpaired == 'No preference'
            ? candidates.first
            : candidates
                      .where(
                        (t) =>
                            isHearingImpaired(t) ==
                            (hearingImpaired == 'Prefer'),
                      )
                      .firstOrNull ??
                  candidates.first;
      }
      // Auto forced fallback only when explicitly requested; empty language is Off.
      if (sub == null && preferForced) sub = forcedAudio;
    }
    sub = savedSub ?? sub;
    return TrackSelection(
      video: state.selected.video,
      audio: audio == null
          ? (state.tracks.audio.isEmpty
                ? state.selected.audio
                : const TrackChoice.off())
          : TrackChoice.specific(audio.id),
      subtitle: sub == null
          ? const TrackChoice.off()
          : TrackChoice.specific(sub.id),
    );
  }
}

Future<void> applyPreferredTracks(
  PlaybackController controller, {
  PlayerLanguage? audio,
  PlayerLanguage? subtitle,
  int? Function(Track)? audioRank,
  String? savedAudioTrackId,
  String? savedSubtitleTrackId,
  TrackRules? rules,
  String? originalLanguage,
}) async {
  try {
    await _applyPreferredTracks(
      controller,
      audio: audio,
      subtitle: subtitle,
      audioRank: audioRank,
      savedAudioTrackId: savedAudioTrackId,
      savedSubtitleTrackId: savedSubtitleTrackId,
      rules: rules,
      originalLanguage: originalLanguage,
    );
  } finally {
    // Always report the pass as finished: the mpv controller resolves a held
    // audio decoder error against the final selection.
    if (controller is MediaKitPlaybackController) {
      await controller.defaultsApplied();
    }
  }
}

Future<void> _applyPreferredTracks(
  PlaybackController controller, {
  PlayerLanguage? audio,
  PlayerLanguage? subtitle,
  int? Function(Track)? audioRank,
  String? savedAudioTrackId,
  String? savedSubtitleTrackId,
  TrackRules? rules,
  String? originalLanguage,
}) async {
  if (rules == null &&
      audio == null &&
      subtitle == null &&
      audioRank == null &&
      savedAudioTrackId == null &&
      savedSubtitleTrackId == null) {
    return;
  }
  bool hasTracks(PlaybackState s) =>
      s.tracks.audio.isNotEmpty || s.tracks.subtitle.isNotEmpty;
  final state = hasTracks(controller.currentState)
      ? controller.currentState
      : await controller.state.firstWhere(
          hasTracks,
          orElse: () => controller.currentState,
        );
  if (rules != null) {
    final metadata = controller is MediaKitPlaybackController
        ? await controller.trackMetadata()
        : <String, Map<String, dynamic>>{};
    await controller.selectTrack(
      rules.select(
        state,
        metadata,
        audioRank: audioRank,
        decoders: await engineDecoderCodecs(controller),
        savedAudioTrackId: savedAudioTrackId,
        savedSubtitleTrackId: savedSubtitleTrackId,
        originalLanguage: originalLanguage,
      ),
    );
    return;
  }
  Track? pick(List<Track> tracks, PlayerLanguage? language, String? savedId) {
    final saved = tracks.where((t) => t.id == savedId).firstOrNull;
    if (saved != null) return saved;
    if (language == null) return null;
    for (final track in tracks) {
      if (language.matches(track.language)) return track;
    }
    return null;
  }

  Track? pickAudio() {
    final saved = state.tracks.audio
        .where((t) => t.id == savedAudioTrackId)
        .firstOrNull;
    if (saved != null && (audioRank == null || audioRank(saved) != null)) {
      return saved;
    }
    bool commentary(Track t) =>
        (t.title ?? '').toLowerCase().contains('commentary');
    Track? best(Iterable<Track> all) {
      final main = all.where((t) => !commentary(t)).toList();
      final pool = main.isEmpty ? all.toList() : main;
      if (audioRank == null) return pool.firstOrNull;
      Track? found;
      int? foundRank;
      for (final t in pool) {
        final r = audioRank(t);
        if (r != null && (foundRank == null || r < foundRank)) {
          found = t;
          foundRank = r;
        }
      }
      return found ?? pool.firstOrNull;
    }

    if (audio != null) {
      final matches = state.tracks.audio.where(
        (t) => audio.matches(t.language),
      );
      if (matches.isNotEmpty) return best(matches);
    }
    // No language match: leave the engine pick unless it cannot be played.
    if (audioRank == null) return null;
    final current = state.tracks.audio
        .where((t) => t.id == state.selected.audio.id)
        .firstOrNull;
    if (current != null && audioRank(current) != null) return null;
    final replacement = best(state.tracks.audio);
    return replacement == null || audioRank(replacement) == null
        ? null
        : replacement;
  }

  final audioTrack = pickAudio();
  final subtitleTrack = pick(
    state.tracks.subtitle,
    subtitle,
    savedSubtitleTrackId,
  );
  if (audioTrack == null && subtitleTrack == null) return;
  await controller.selectTrack(
    TrackSelection(
      video: state.selected.video,
      audio: audioTrack == null
          ? state.selected.audio
          : TrackChoice.specific(audioTrack.id),
      subtitle: subtitleTrack == null
          ? state.selected.subtitle
          : TrackChoice.specific(subtitleTrack.id),
    ),
  );
}
