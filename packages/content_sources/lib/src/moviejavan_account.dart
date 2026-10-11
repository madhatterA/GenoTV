import 'dart:io';

import 'package:core/core.dart';

import 'content_source_failure.dart';
import 'provider_http.dart';
import 'session_file.dart';

/// MovieJavan sign-in (email + password). Its REST API authenticates every
/// call with the app's fixed API-KEY and Basic header (from the 2026-09-18
/// capture, research/provider research/moviejavan) and returns the user id,
/// no token. Streams are not implemented yet; this only keeps the account.
class MovieJavanAccount {
  MovieJavanAccount({
    required this.http,
    required this.logger,
    File? sessionFile,
    Uri? apiRoot,
  }) : sessionFile =
           sessionFile ??
           File('${Platform.environment['HOME']}/.moviejavan-session.json'),
       apiRoot =
           apiRoot ??
           Uri.parse(
             'http://cdntmp.dnstmp10.q5eapp.ir/playstore/rest-api/v100',
           );

  final ProviderHttp http;
  final AppLogger logger;
  final File sessionFile;
  final Uri apiRoot;

  static const Map<String, String> _headers = {
    'API-KEY': '1661e8b60126d9f9',
    'Authorization': 'Basic YWRtaW46MTIzNA==',
    'User-Agent': 'okhttp/4.6.0',
  };

  /// True when a saved session exists.
  Future<bool> get signedIn async {
    try {
      await readSessionToken(sessionFile, 'user_id');
      return true;
    } on ContentSourceFailure {
      return false;
    }
  }

  Future<void> signIn(String email, String password) async {
    final response = await http.postForm(
      apiRoot.replace(path: '${apiRoot.path}/login'),
      {'email': email, 'password': password},
      headers: _headers,
    );
    final data = response is Map ? response : const {};
    final userId = data['user_id']?.toString() ?? '';
    if (data['status'] != 'success' || userId.isEmpty) {
      // Wrong credentials come back as HTTP 200 {"status":"error","data":…}.
      throw ContentSourceFailure.authRequired(
        data['data'] is String
            ? data['data'] as String
            : 'MovieJavan rejected the sign-in.',
      );
    }
    await writeSession(sessionFile, {'user_id': userId, 'email': email});
    logger.info('MovieJavan sign-in saved');
  }

  Future<void> signOut() => deleteSession(sessionFile);
}
