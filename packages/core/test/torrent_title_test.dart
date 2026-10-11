import 'dart:convert';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

// Frozen PlayTorrio V3 output (39b736f), with owner-approved numeric-title regression expectations.
// Do not regenerate expectations as part of a test run.
final _oracle = jsonDecode(r'''
{
  "rows": [
    {
      "name": "Inception.2010.1080p.BluRay.x264-GROUP",
      "path": false,
      "expected": {
        "year": 2010,
        "resolution": "1080p",
        "source": "bluray",
        "codec": "x264",
        "group": "GROUP",
        "title": "Inception"
      }
    },
    {
      "name": "The.Matrix.1999.2160p.UHD.BluRay.REMUX.HEVC.HDR.DV-GROUP",
      "path": false,
      "expected": {
        "year": 1999,
        "resolution": "2160p",
        "resolutionlist": [
          "2160p",
          "4k"
        ],
        "remux": true,
        "source": "bluray",
        "codec": "h265",
        "color": "HDR",
        "colorlist": [
          "HDR",
          "DV"
        ],
        "group": "GROUP",
        "title": "The Matrix"
      }
    },
    {
      "name": "Interstellar (2014) 720p WEB-DL H.264",
      "path": false,
      "expected": {
        "year": 2014,
        "resolution": "720p",
        "source": "web-dl",
        "codec": "h264",
        "group": "H.264",
        "encoder": "DL",
        "title": "Interstellar"
      }
    },
    {
      "name": "Dune.Part.Two.2024.2160p.WEB-DL.DDP5.1.Atmos.H.265",
      "path": false,
      "expected": {
        "year": 2024,
        "resolution": "2160p",
        "source": "web-dl",
        "codec": "h265",
        "audio": "atmos",
        "audiolist": [
          "atmos",
          "ddp"
        ],
        "channels": 5.1,
        "title": "Dune Part Two"
      }
    },
    {
      "name": "Blade Runner 2049 2017 1080p BluRay x265",
      "path": false,
      "expected": {
        "year": 2017,
        "resolution": "1080p",
        "source": "bluray",
        "codec": "x265",
        "title": "Blade Runner 2049"
      }
    },
    {
      "name": "2001 A Space Odyssey 1968 1080p BluRay",
      "path": false,
      "expected": {
        "year": 1968,
        "resolution": "1080p",
        "source": "bluray",
        "title": "2001 A Space Odyssey"
      }
    },
    {
      "name": "1917 2019 1080p",
      "path": false,
      "expected": {
        "year": 2019,
        "resolution": "1080p",
        "title": "1917"
      }
    },
    {
      "name": "01 - Pilot.mkv",
      "path": false,
      "expected": {
        "container": "mkv",
        "group": "Pilot",
        "episode": 1,
        "title": ""
      }
    },
    {
      "name": "Show/Season 05/01 - Pilot.mkv",
      "path": true,
      "expected": {
        "container": "mkv",
        "group": "Pilot",
        "episode": 1,
        "title": "",
        "season": 5
      }
    },
    {
      "name": "1917.2019.1080p.BluRay.x264",
      "path": false,
      "expected": {
        "year": 2019,
        "resolution": "1080p",
        "source": "bluray",
        "codec": "x264",
        "title": "1917"
      }
    },
    {
      "name": "The.Godfather.1972.1080p.REMASTERED.BluRay",
      "path": false,
      "expected": {
        "year": 1972,
        "resolution": "1080p",
        "remastered": true,
        "source": "bluray",
        "title": "The Godfather"
      }
    },
    {
      "name": "Alien.1979.4K.HDR.REMUX",
      "path": false,
      "expected": {
        "year": 1979,
        "resolution": "4k",
        "remux": true,
        "color": "HDR",
        "title": "Alien"
      }
    },
    {
      "name": "Arrival.2016.UHD.HEVC.DV",
      "path": false,
      "expected": {
        "year": 2016,
        "resolution": "4k",
        "codec": "h265",
        "color": "DV",
        "title": "Arrival"
      }
    },
    {
      "name": "Breaking.Bad.S01E02.1080p.WEB-DL",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "source": "web-dl",
        "group": "DL",
        "season": 1,
        "episode": 2,
        "title": "Breaking Bad"
      }
    },
    {
      "name": "Game.of.Thrones.S08E06.2160p.HDR",
      "path": false,
      "expected": {
        "resolution": "2160p",
        "color": "HDR",
        "season": 8,
        "episode": 6,
        "title": "Game of Thrones"
      }
    },
    {
      "name": "The.Office.1x02.720p.HDTV",
      "path": false,
      "expected": {
        "resolution": "720p",
        "source": "hdtv",
        "season": 1,
        "episode": 2,
        "title": "The Office"
      }
    },
    {
      "name": "Friends.02X03.480p.DVDRip",
      "path": false,
      "expected": {
        "resolution": "480p",
        "source": "dvdrip",
        "season": 2,
        "episode": 3,
        "title": "Friends"
      }
    },
    {
      "name": "Lost.S01E01-E04.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "group": "E04.1080p",
        "season": 1,
        "episode": 1,
        "episodelist": [
          1,
          4
        ],
        "episodeRange": [
          1,
          4
        ],
        "title": "Lost"
      }
    },
    {
      "name": "Dark.S02E03-E04.720p",
      "path": false,
      "expected": {
        "resolution": "720p",
        "group": "E04.720p",
        "season": 2,
        "episode": 3,
        "episodelist": [
          3,
          4
        ],
        "episodeRange": [
          3,
          4
        ],
        "title": "Dark"
      }
    },
    {
      "name": "Fargo.01x01-04.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "group": "04.1080p",
        "season": 1,
        "episode": 1,
        "episodeRange": [
          1,
          4
        ],
        "title": "Fargo"
      }
    },
    {
      "name": "Show.E01-E04.720p",
      "path": false,
      "expected": {
        "resolution": "720p",
        "group": "E04.720p",
        "episode": 1,
        "episodeRange": [
          1,
          4
        ],
        "title": "Show"
      }
    },
    {
      "name": "Show.01-04.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "group": "04.1080p",
        "season": 1,
        "episode": 4,
        "episodeRange": [
          1,
          4
        ],
        "title": "Show"
      }
    },
    {
      "name": "Show.S02.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 2,
        "title": "Show"
      }
    },
    {
      "name": "The.Wire.S05.720p.WEBRip",
      "path": false,
      "expected": {
        "resolution": "720p",
        "source": "webrip",
        "season": 5,
        "title": "The Wire"
      }
    },
    {
      "name": "Show.2xall.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 2,
        "title": "Show"
      }
    },
    {
      "name": "Show.Season.3.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 3,
        "title": "Show"
      }
    },
    {
      "name": "Show.Saison-04.720p",
      "path": false,
      "expected": {
        "resolution": "720p",
        "group": "04.720p",
        "season": 4,
        "title": "Show"
      }
    },
    {
      "name": "Show.5 серия.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "episode": 5,
        "title": "Show"
      }
    },
    {
      "name": "Show.серия 5.720p",
      "path": false,
      "expected": {
        "resolution": "720p",
        "episode": 5,
        "title": "Show"
      }
    },
    {
      "name": "Show.сезон 2.5 серия.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "episode": 5,
        "season": 2,
        "title": "Show"
      }
    },
    {
      "name": "Show.3 sezon.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 3,
        "title": "Show"
      }
    },
    {
      "name": "Show/Season 3/02 - Episode.mkv",
      "path": true,
      "expected": {
        "container": "mkv",
        "group": "Episode",
        "episode": 2,
        "title": "",
        "season": 3
      }
    },
    {
      "name": "Show\\Season 3\\03 - Episode.mkv",
      "path": true,
      "expected": {
        "container": "mkv",
        "group": "Episode",
        "episode": 3,
        "title": "",
        "season": 3
      }
    },
    {
      "name": "Show/Season 3/Show.S02E04.1080p.mkv",
      "path": true,
      "expected": {
        "resolution": "1080p",
        "container": "mkv",
        "season": 2,
        "episode": 4,
        "title": "Show"
      }
    },
    {
      "name": "Show/S04/05.mkv",
      "path": true,
      "expected": {
        "container": "mkv",
        "episode": 5,
        "title": "",
        "season": 4
      }
    },
    {
      "name": "Show.S01E02.E03.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 1,
        "episode": 2,
        "episodelist": [
          2,
          3
        ],
        "episodeRange": [
          2,
          3
        ],
        "title": "Show"
      }
    },
    {
      "name": "Show.S01E02.Season.3.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 1,
        "seasonlist": [
          1,
          3
        ],
        "episode": 2,
        "title": "Show"
      }
    },
    {
      "name": "Movie.2020.1080p.UHD.BluRay.WEB-DL",
      "path": false,
      "expected": {
        "year": 2020,
        "resolution": "1080p",
        "resolutionlist": [
          "1080p",
          "4k"
        ],
        "source": "bluray",
        "sourcelist": [
          "bluray",
          "web-dl"
        ],
        "group": "DL",
        "title": "Movie"
      }
    },
    {
      "name": "Movie.2021.1080p.x265.HEVC.HDR.DV.REMUX",
      "path": false,
      "expected": {
        "year": 2021,
        "resolution": "1080p",
        "remux": true,
        "codec": "h265",
        "codeclist": [
          "h265",
          "x265"
        ],
        "color": "HDR",
        "colorlist": [
          "HDR",
          "DV"
        ],
        "title": "Movie"
      }
    },
    {
      "name": "The.Lord.of.the.Rings.2001.EXTENDED.1080p.BluRay",
      "path": false,
      "expected": {
        "year": 2001,
        "resolution": "1080p",
        "extended": true,
        "source": "bluray",
        "title": "The Lord of the Rings"
      }
    },
    {
      "name": "Spider-Man.No.Way.Home.2021.1080p.WEB-DL",
      "path": false,
      "expected": {
        "year": 2021,
        "resolution": "1080p",
        "source": "web-dl",
        "group": "DL",
        "title": "Spider-Man No Way Home"
      }
    },
    {
      "name": "Show.1×02.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 1,
        "episode": 2,
        "title": "Show"
      }
    },
    {
      "name": "Show.1Х02.1080p",
      "path": false,
      "expected": {
        "resolution": "1080p",
        "season": 1,
        "episode": 2,
        "title": "Show"
      }
    }
  ],
  "scores": [
    {
      "title": "Inception",
      "query": "inception",
      "expected": 10000
    },
    {
      "title": "The Matrix",
      "query": "Matrix",
      "expected": 10000
    },
    {
      "title": "An Education",
      "query": "Education",
      "expected": 10000
    },
    {
      "title": "Vampire Diaries Season Two",
      "query": "vampire diaries",
      "expected": 11000
    },
    {
      "title": "Vampire Weekend",
      "query": "vampire diaries",
      "expected": 10
    },
    {
      "title": "Matrix",
      "query": "",
      "expected": 0
    }
  ],
  "pilot": {
    "container": "mkv",
    "group": "Pilot",
    "episode": 1,
    "title": "",
    "season": 5
  }
}
''') as Map<String, dynamic>;

void main() {
  final parser = ParseTorrentTitle();
  final rows = _oracle['rows'] as List<dynamic>;
  final scores = _oracle['scores'] as List<dynamic>;
  assert(rows.length == 43);
  assert(scores.length == 6);

  for (final row in rows.cast<Map<String, dynamic>>()) {
    final name = row['name'] as String;
    test('release: $name', () {
      final actual = row['path'] == true
          ? parser.parsePath(name)
          : parser.parse(name);
      expect(actual, row['expected']);
    });
  }

  test('parsePath inherits season 5 and episode 1 for Pilot', () {
    final actual = parser.parsePath('Show/Season 05/01 - Pilot.mkv');
    expect(actual, _oracle['pilot']);
    expect(actual['season'], 5);
    expect(actual['episode'], 1);
  });

  for (final row in scores.cast<Map<String, dynamic>>()) {
    test('relevance: ${row['title']} / ${row['query']}', () {
      expect(
        RelevanceScorer.score(
          title: row['title'] as String,
          query: row['query'] as String,
        ),
        row['expected'],
      );
    });
  }
}
