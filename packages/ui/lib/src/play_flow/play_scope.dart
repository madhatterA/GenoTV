import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

/// Lets a poster's "Play" action start the play flow for a movie without
/// every list threading a callback through. Without a scope Play opens Details.
class PlayScope extends InheritedWidget {
  const PlayScope({required this.play, required super.child, super.key});

  final void Function(BuildContext context, MediaItem item) play;

  static PlayScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlayScope>();

  @override
  bool updateShouldNotify(PlayScope oldWidget) => false;
}
