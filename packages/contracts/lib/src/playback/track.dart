/// One of the three kinds of track a media file can carry.
enum TrackType { video, audio, subtitle }

/// One track reported by the engine. Ids are stable strings from the
/// engine, never list indexes — indexes change when an external subtitle
/// is added mid-playback.
class Track {
  const Track({
    required this.id,
    required this.type,
    this.title,
    this.language,
    this.codec,
    this.isDefault = false,
  });

  final String id;
  final TrackType type;
  final String? title;
  final String? language;
  final String? codec;
  final bool isDefault;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Track &&
          other.id == id &&
          other.type == type &&
          other.title == title &&
          other.language == language &&
          other.codec == codec &&
          other.isDefault == isDefault);

  @override
  int get hashCode => Object.hash(id, type, title, language, codec, isDefault);

  @override
  String toString() => 'Track($type, $id, ${title ?? language ?? ''})';
}

/// All tracks a media file carries, by type.
class TrackList {
  const TrackList({
    this.video = const <Track>[],
    this.audio = const <Track>[],
    this.subtitle = const <Track>[],
  });

  final List<Track> video;
  final List<Track> audio;
  final List<Track> subtitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackList &&
          _listEquals(other.video, video) &&
          _listEquals(other.audio, audio) &&
          _listEquals(other.subtitle, subtitle));

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(video), Object.hashAll(audio), Object.hashAll(subtitle));
}

/// Which state a single track type's selection is in.
enum TrackSelectionMode { auto, off, specific }

/// One track type's selection: the engine's default (nothing chosen yet —
/// mpv/media_kit auto-selects), explicitly off (meaningful for subtitles,
/// which can be disabled — media_kit's own track API has this same
/// auto/no/specific tri-state), or one specific track by its stable
/// [Track.id].
///
/// `planning/CONTRACTS.md` §3 originally typed each selection as a bare
/// `String? ... // null = disabled`; corrected in this Phase. A single
/// nullable id cannot distinguish "off" from "not yet chosen", which this
/// Phase's own test requires — see decisions.md "TrackSelection needs a
/// tri-state, not a nullable id".
class TrackChoice {
  const TrackChoice.auto()
      : mode = TrackSelectionMode.auto,
        id = null;

  const TrackChoice.off()
      : mode = TrackSelectionMode.off,
        id = null;

  const TrackChoice.specific(String trackId)
      : mode = TrackSelectionMode.specific,
        id = trackId;

  final TrackSelectionMode mode;

  /// Non-null only when [mode] is [TrackSelectionMode.specific].
  final String? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TrackChoice && other.mode == mode && other.id == id);

  @override
  int get hashCode => Object.hash(mode, id);

  @override
  String toString() => switch (mode) {
        TrackSelectionMode.auto => 'TrackChoice.auto()',
        TrackSelectionMode.off => 'TrackChoice.off()',
        TrackSelectionMode.specific => 'TrackChoice.specific($id)',
      };
}

/// The active choice for each track type.
class TrackSelection {
  const TrackSelection({
    this.video = const TrackChoice.auto(),
    this.audio = const TrackChoice.auto(),
    this.subtitle = const TrackChoice.off(),
  });

  final TrackChoice video;
  final TrackChoice audio;
  final TrackChoice subtitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrackSelection &&
          other.video == video &&
          other.audio == audio &&
          other.subtitle == subtitle);

  @override
  int get hashCode => Object.hash(video, audio, subtitle);
}

/// A chapter marker.
class Chapter {
  const Chapter({required this.start, this.title});

  final Duration start;
  final String? title;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Chapter && other.start == start && other.title == title);

  @override
  int get hashCode => Object.hash(start, title);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
