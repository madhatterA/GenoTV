import 'dart:convert';
import 'dart:io';

import 'content_source_failure.dart';

Future<String> readSessionToken(File file, String key) async {
  try {
    final json = jsonDecode(await file.readAsString());
    final token = json is Map ? json[key] : null;
    if (token is String && token.trim().isNotEmpty) return token.trim();
  } catch (_) {
    // Missing, unreadable and malformed sessions have the same user action.
  }
  throw const ContentSourceFailure.authRequired();
}

Future<void> writeSession(File file, Map<String, String> session) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(session), flush: true);
}

Future<void> deleteSession(File file) async {
  if (await file.exists()) await file.delete();
}
