import 'package:contracts/contracts.dart';

/// The compact, safe-to-display parts of a provider stream.
class StreamDisplay {
  const StreamDisplay({
    required this.badges,
    required this.name,
    required this.fileName,
    this.release = false,
    this.seeders,
  });

  final List<String> badges;
  final String name;
  final String fileName;

  /// True when the info dialog shows a torrent release name, not a file name.
  final bool release;
  final int? seeders;
}

/// A provider that names each stream's site (`Site: <name>` label line, e.g.
/// Playtorrio Direct) lists independent streams; only unnamed HLS variants
/// of one title (30nama) collapse to a single Auto row.
bool _hasSite(SourceSpec spec) =>
    (spec.label ?? '').split('\n').any((l) => l.startsWith('Site: '));

List<SourceSpec> collapseHls(List<SourceSpec> streams) {
  bool collapsible(SourceSpec s) => s.kind == SourceKind.hlsUrl && !_hasSite(s);
  final hls = streams.where(collapsible).toList();
  if (hls.isEmpty) return streams;
  final auto = hls.firstWhere(
    (s) => (s.label ?? '').toLowerCase().contains('auto'),
    orElse: () => hls.first,
  );
  var included = false;
  return [
    for (final stream in streams)
      if (!collapsible(stream))
        stream
      else if (!included && (included = true))
        auto,
  ];
}

StreamDisplay parseStreamDisplay(
  SourceSpec spec, {
  required String providerName,
  String torrentName = 'Torrent',
}) {
  final fileName = streamFileName(spec);
  final torrent =
      spec.kind == SourceKind.torrentMagnet ||
      spec.kind == SourceKind.torrentFile;
  final metadata = <String, String>{
    for (final line in (spec.label ?? '').split('\n'))
      if (line.contains(': '))
        line.substring(0, line.indexOf(': ')): line.substring(
          line.indexOf(': ') + 2,
        ),
  };
  final group = torrent
      ? metadata['Release group']
      : RegExp(r'-([A-Za-z][A-Za-z0-9]{1,20})(?=[._-]|$)')
            .firstMatch(fileName)?[1];
  // The release group is a name, not a spec: `-CC.mkv` must not add a CC badge.
  final specText = group == null
      ? fileName
      : fileName.replaceFirst('-$group', '');
  final structured = '${spec.quality ?? ''} ${spec.label ?? ''}';
  final badges = <String>[];
  if (spec.kind == SourceKind.hlsUrl) {
    // Quality when known, then a plain HLS tag (owner 2026-10-10: the old
    // circular "auto" icon read as a refresh button).
    if (_resolution(spec.quality ?? '') case final resolution?) {
      badges.add(resolution);
    }
    badges.add('HLS');
  } else {
    final resolution =
        _resolution(spec.quality ?? '') ??
        _resolution(spec.label ?? '') ??
        _resolution(specText);
    if (resolution != null) badges.add(resolution);
    if (_has(structured, r'hdr10(?:\+|plus)') ||
        _has(specText, r'hdr10(?:\+|plus)')) {
      badges.add('HDR10+');
    } else if (_has(structured, r'hdr(?:10)?(?!\+|plus)') ||
        _has(specText, r'hdr(?:10)?(?!\+|plus)')) {
      badges.add('HDR');
    }
    if (_has(structured, r'dolby[ ._-]*vision|dovi|dv') ||
        _has(specText, r'dolby[ ._-]*vision|dovi|dv')) {
      badges.add('DV');
    }
    if (_has(structured, r'10[ ._-]*bit') || _has(specText, r'10[ ._-]*bit')) {
      badges.add('10-bit');
    }
    if (_has(structured, r'x26[45]|h[ ._-]*26[45]|hevc|avc') ||
        _has(specText, r'x26[45]|h[ ._-]*26[45]|hevc|avc')) {
      final codecSource = _has(structured, r'x26[45]|h[ ._-]*26[45]|hevc|avc')
          ? structured
          : specText;
      final hevc = _has(codecSource, r'x265|h[ ._-]*265|hevc');
      badges.add(hevc ? 'H.265' : 'H.264');
    }
    if (_has(
          structured,
          r'(?:soft|hard)[ ._-]*subs?|subs?|subtitles?|cc|closed[ ._-]*captions?',
        ) ||
        _has(
          specText,
          r'(?:soft|hard)[ ._-]*subs?|subs?|subtitles?|cc|closed[ ._-]*captions?',
        )) {
      badges.add('CC');
    }
  }
  final name = metadata['Site'] != null && metadata['Site']!.isNotEmpty
      ? metadata['Site']!
      : torrent
      ? group ?? torrentName
      : group == null ||
            _resolution(group) != null ||
            _has(
              group,
              r'hevc|avc|hdr|dovi|web|dl|bluray|x26[45]|hd|dts|aac|atmos',
            )
      ? providerName
      : group;
  return StreamDisplay(
    badges: badges,
    name: name,
    fileName: fileName,
    release: torrent && (spec.fileHint?.trim().isEmpty ?? true),
    seeders: int.tryParse(metadata['Seeders'] ?? ''),
  );
}

/// Percent-decodes [text]; text that is not valid percent-encoding (a bare
/// '%' as in "Movie 100% Uncut") is already plain, so it is kept as is.
String _decoded(String text) {
  try {
    return Uri.decodeComponent(text);
  } on ArgumentError {
    return text;
  } on FormatException {
    return text;
  }
}

/// The magnet's `dn` (display name), decoded safely; null when absent.
String? _magnetName(Uri uri) {
  for (final pair in uri.query.split('&')) {
    if (pair.startsWith('dn=')) {
      return _decoded(pair.substring(3).replaceAll('+', ' '));
    }
  }
  return null;
}

String streamFileName(SourceSpec spec) {
  final hint = spec.fileHint?.trim();
  if (hint != null && hint.isNotEmpty) {
    return _decoded(hint.split('?').first.split('/').last);
  }
  if (spec.kind == SourceKind.torrentMagnet ||
      spec.kind == SourceKind.torrentFile) {
    return spec.label?.split('\n').firstOrNull ?? _magnetName(spec.uri) ?? '';
  }
  return _decoded(spec.uri.path.split('/').last);
}

String? _resolution(String text) {
  if (_has(text, r'2160p|4k|uhd')) return '4K';
  if (_has(text, r'1080p')) return '1080p';
  if (_has(text, r'720p')) return '720p';
  if (_has(text, r'480p')) return '480p';
  return null;
}

bool _has(String text, String pattern) => RegExp(
  '(^|[^a-z0-9])(?:$pattern)(?=[^a-z0-9]|\$)',
  caseSensitive: false,
).hasMatch(text);
