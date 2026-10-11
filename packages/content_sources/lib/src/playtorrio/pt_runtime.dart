import 'package:core/core.dart';

/// Stands in for Flutter's `debugPrint`/`kDebugMode` in the PlayTorrio
/// scrapers so their messages go to the app logger (CLAUDE.md: no print).
AppLogger? ptLogger;

const bool kDebugMode = true;

void debugPrint(String? message, {int? wrapWidth}) {
  if (message != null) ptLogger?.debug('[PlaytorrioDirect] $message');
}
