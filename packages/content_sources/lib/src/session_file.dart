import 'dart:convert';
import 'dart:io';

import 'content_source_failure.dart';

/// Where provider session files live. null = the home folder (desktop, Android, iOS). tvOS sets this to
/// an app-writable folder at start-up, because its home is read-only on a real Apple TV.
Directory? sessionDirectory;

File defaultSessionFile(String name) =>
    File('${sessionDirectory?.path ?? Platform.environment['HOME']}/.$name-session.json');

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
