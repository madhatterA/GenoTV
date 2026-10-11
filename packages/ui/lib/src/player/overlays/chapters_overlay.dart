import '../../l10n_gen/app_strings.dart';
import '../../l10n/app_text.dart';

import 'package:contracts/contracts.dart';
import 'package:flutter/material.dart';

import 'overlay_shell.dart';

class ChaptersOverlay extends StatelessWidget {
  const ChaptersOverlay({
    required this.chapters,
    required this.onSeek,
    required this.onClose,
    super.key,
  });

  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    if (chapters.isEmpty) return const SizedBox.shrink();
    return OverlayShell(
      title: AppStrings.of(context).player_chapters,
      onClose: onClose,
      child: ListView.builder(
        itemCount: chapters.length,
        itemBuilder: (context, index) {
          final chapter = chapters[index];
          return ListTile(
            key: ValueKey<String>('chapter-$index'),
            title: AppText(
              chapter.title ?? AppStrings.of(context).player_chapter(index + 1),
            ),
            subtitle: AppText(_time(chapter.start)),
            onTap: () => onSeek(chapter.start),
          );
        },
      ),
    );
  }

  String _time(Duration value) =>
      '${value.inMinutes.toString().padLeft(2, '0')}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';
}
