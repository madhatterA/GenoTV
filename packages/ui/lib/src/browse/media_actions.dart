import 'package:contracts/contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../detail/favourites_scope.dart';
import '../l10n_gen/app_strings.dart';
import '../play_flow/play_scope.dart';
import 'media_context_menu.dart';

/// "1:07" (h:mm) for a saved position, used by the Resume action.
String resumeTimeLabel(Duration position) {
  final minutes = position.inMinutes;
  return '${minutes ~/ 60}:${(minutes % 60).toString().padLeft(2, '0')}';
}

/// The one list of actions every poster offers (row, shelf, grid, search):
/// Play (or Resume), Details, Like/Unlike, plus [extra] (e.g. Remove on the
/// Continue row). Play of a movie opens the play flow (via [PlayScope]); other
/// titles need an episode, so Play opens their page. "Mark watched" is left out (Part 07 ESCALATIONS E1).
Future<List<MediaContextAction>> mediaActionsFor(
  BuildContext context,
  MediaItem item, {
  required ValueChanged<MediaItem>? onDetails,
  PlaybackProgress? progress,
  List<MediaContextAction> extra = const <MediaContextAction>[],
}) async {
  final strings = AppStrings.of(context);
  final repository = FavouritesScope.maybeOf(context);
  final liked = repository == null
      ? false
      : await repository.isFavourite(item.id);
  final playScope = PlayScope.maybeOf(context);
  final VoidCallback? play = item.kind == MediaKind.movie && playScope != null
      ? () => playScope.play(context, item)
      : onDetails == null
      ? null
      : () => onDetails(item);
  final resume =
      progress != null && progress.position >= const Duration(minutes: 1);
  return <MediaContextAction>[
    if (play != null)
      MediaContextAction(
        label: resume
            ? strings.menu_resumeAt(resumeTimeLabel(progress.position))
            : strings.common_play,
        icon: PhosphorIconsRegular.play,
        onSelected: play,
      ),
    if (onDetails != null)
      MediaContextAction(
        label: strings.common_details,
        icon: PhosphorIconsRegular.info,
        onSelected: () => onDetails(item),
      ),
    if (repository != null)
      MediaContextAction(
        label: liked ? strings.detail_unlike : strings.detail_like,
        icon: liked ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
        onSelected: () =>
            setLikedWithFeedback(context, repository, item.id, !liked),
      ),
    ...extra,
  ];
}

/// Opens the shared poster menu at [anchor] (null centres it) and returns focus
/// to [returnFocusTo] afterwards.
Future<void> showMediaActionsMenu(
  BuildContext context,
  MediaItem item, {
  required ValueChanged<MediaItem>? onDetails,
  PlaybackProgress? progress,
  List<MediaContextAction> extra = const <MediaContextAction>[],
  Offset? anchor,
  FocusNode? returnFocusTo,
}) async {
  final focus = returnFocusTo ?? FocusManager.instance.primaryFocus;
  final actions = await mediaActionsFor(
    context,
    item,
    onDetails: onDetails,
    progress: progress,
    extra: extra,
  );
  if (actions.isEmpty || !context.mounted) return;
  return showMediaContextMenu(
    context: context,
    actions: actions,
    anchor: anchor,
    returnFocusTo: focus,
  );
}
