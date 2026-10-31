import 'dart:io';

import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'session_file.dart';

/// Per-user accounts for the online subtitle services (Part 03 p02). Nothing
/// is shared or shipped: SubDL and SubSource hold the user's own API key,
/// OpenSubtitles holds the user's JWT. The OpenSubtitles consumer key belongs
/// to the app owner and comes from the build config, never from the repo.
class SubtitleAccounts {
  SubtitleAccounts({
    required this.http,
    required this.logger,
    Directory? dir,
    Uri? subdlRoot,
    Uri? subsourceRoot,
    Uri? openSubtitlesRoot,
    String? consumerKey,
  }) : _dir = dir ?? sessionDirectory ?? Directory(Platform.environment['HOME'] ?? '.'),
       subdlRoot = subdlRoot ?? Uri.parse('https://api.subdl.com/api/v1'),
       subsourceRoot =
           subsourceRoot ?? Uri.parse('https://api.subsource.net/api/v1'),
       openSubtitlesRoot =
           openSubtitlesRoot ??
           Uri.parse('https://api.opensubtitles.com/api/v1'),
       consumerKey =
           consumerKey ?? const String.fromEnvironment('OPENSUBTITLES_API_KEY');

  final ProviderHttp http;
  final AppLogger logger;
  final Directory _dir;
  final Uri subdlRoot;
  final Uri subsourceRoot;
  final Uri openSubtitlesRoot;
  final String consumerKey;

  static const subdl = 'subdl';
  static const subsource = 'subsource';
  static const openSubtitles = 'opensubtitles';

  File _file(String id) => File('${_dir.path}/.$id-session.json');

  Future<bool> signedIn(String id) async {
    try {
      await readSessionToken(_file(id), 'token');
      return true;
    } on ContentSourceFailure {
      return false;
    }
  }

  /// The saved key or JWT; throws authRequired when not signed in.
  Future<String> token(String id) => readSessionToken(_file(id), 'token');

  /// SubDL and SubSource: [key] is the user's personal API key.
  /// A key is checked against the service first (API: subsource.net/api-docs,
  /// header `X-API-Key`; confirmed live 2026-10-29).
  Future<void> saveKey(String id, String key) async {
    key = key.trim();
    if (key.isEmpty)
      throw const ContentSourceFailure.authRequired('Enter a key.');
    if (id == subdl) {
      // A bad key answers 403 -> authRequired.
      await http.getJson(
        subdlRoot.replace(
          path: '${subdlRoot.path}/subtitles',
          queryParameters: {
            'api_key': key,
            'imdb_id': 'tt0133093',
            'subs_per_page': '1',
          },
        ),
      );
    }
    if (id == subsource) {
      // A bad key answers 401 -> authRequired.
      await http.getJson(
        subsourceRoot.replace(
          path: '${subsourceRoot.path}/movies/search',
          queryParameters: {'searchType': 'imdb', 'imdb': 'tt0133093'},
        ),
        headers: {'X-API-Key': key},
      );
    }
    await writeSession(_file(id), {'token': key});
    logger.info('$id key saved');
  }

  Future<void> signInOpenSubtitles(String user, String password) async {
    if (consumerKey.isEmpty) {
      throw const ContentSourceFailure.unavailable(
        'OpenSubtitles is not set up in this build.',
      );
    }
    final response = await http.postJson(
      openSubtitlesRoot.replace(path: '${openSubtitlesRoot.path}/login'),
      {'username': user, 'password': password},
      headers: {
        'Api-Key': consumerKey,
        'User-Agent': 'GenoTV v1.0',
        'Accept': 'application/json',
      },
    );
    final jwt = response is Map ? response['token'] : null;
    if (jwt is! String || jwt.isEmpty) {
      throw const ContentSourceFailure.authRequired(
        'OpenSubtitles rejected the sign-in.',
      );
    }
    await writeSession(_file(openSubtitles), {'token': jwt, 'user': user});
    logger.info('opensubtitles sign-in saved');
  }

  Future<void> signOut(String id) => deleteSession(_file(id));
}
