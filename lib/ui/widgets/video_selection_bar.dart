// The bar shown instead of the search while videos are ticked (All videos, a collection's page and
// its in-place contents). Moved out of screens/videos_screen.dart in refactor phase 6 (9 Oct 2026),
// unchanged; it's built on the shared SelectionBar.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import 'escape_cancels.dart';
import '../screens/edit_video.dart';
import 'selection_bar.dart';

/// The bar shown instead of the search while videos are ticked (All videos, a collection's page
/// and its in-place contents): how many, Select all, Edit details (one or several), and mark
/// them watched or not watched.
class VideoSelectionBar extends StatelessWidget {
  const VideoSelectionBar({
    super.key,
    required this.selected,
    required this.onClear,
    required this.onSelectAll,
  });

  final Set<String> selected;
  final VoidCallback onClear, onSelectAll;

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    List<VideoItem> picked() => [for (final id in selected) model.byId(id)].whereType<VideoItem>().toList();
    // Esc cancels the selection, like the ✕ (0.1.48).
    return EscapeCancels(onCancel: onClear, child: SelectionBar(
      key: const ValueKey('video-selection-bar'),
      label: '${selected.length} selected',
      onClear: onClear,
      safeArea: false,
      actions: [
          TextButton(onPressed: onSelectAll, child: const Text('Select all')),
          IconButton(
            key: const ValueKey('selection-edit'),
            tooltip: selected.length == 1 ? 'Edit details' : 'Edit ${selected.length} videos',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showEditVideos(context, picked()),
          ),
          IconButton(
            tooltip: 'Mark as watched',
            icon: const Icon(Icons.check_circle_outline),
            onPressed: () async {
              await model.setWatched(selected.toList(), true);
              onClear();
            },
          ),
          IconButton(
            tooltip: 'Mark as not watched',
            icon: const Icon(Icons.remove_done),
            onPressed: () async {
              await model.setWatched(selected.toList(), false);
              onClear();
            },
          ),
      ],
    ));
  }
}
