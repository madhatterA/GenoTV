import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';

/// Gives detail pages the app's favourites store, so the heart on any movie
/// or show page works without every route threading the repository through.
class FavouritesScope extends InheritedWidget {
  const FavouritesScope({
    required this.repository,
    required super.child,
    super.key,
  });

  final FavouritesRepository repository;

  static FavouritesRepository? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FavouritesScope>()?.repository;

  @override
  bool updateShouldNotify(FavouritesScope oldWidget) =>
      repository != oldWidget.repository;
}
