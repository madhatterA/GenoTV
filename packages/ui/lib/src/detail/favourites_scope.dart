import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../components/app_toast.dart';
import '../l10n_gen/app_strings.dart';

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

/// Saves a like/unlike and gives the feedback every Like action shares: a toast
/// with Undo on success, an error toast on failure. Returns whether it saved.
/// Undo sets the opposite explicit value for the same [id], so it cannot
/// double-apply; [onChanged] reports it so a caller can update its own state.
Future<bool> setLikedWithFeedback(
  BuildContext context,
  FavouritesRepository repository,
  String id,
  bool liked, {
  ValueChanged<bool>? onChanged,
}) async {
  final strings = AppStrings.of(context);
  Future<bool> save(bool value) async {
    try {
      await repository.setFavourite(id, value);
      return true;
    } on Object {
      return false;
    }
  }

  final ok = await save(liked);
  if (!context.mounted) return ok;
  if (!ok) {
    showAppToast(
      context,
      PhosphorIconsRegular.warning,
      strings.toast_saveFailed,
    );
    return false;
  }
  showAppToast(
    context,
    PhosphorIconsRegular.check,
    liked ? strings.toast_liked : strings.toast_unliked,
    actionLabel: strings.toast_undo,
    onAction: () async {
      if (await save(!liked)) onChanged?.call(!liked);
    },
  );
  return true;
}
