// The right-click / press-and-hold menu on a season or group heading (All videos and a
// collection's page): Select all in it, Unselect, watched / not watched, Season title…, Fold.
// Split out of screens/videos_screen.dart in refactor phase 6 (9 Oct 2026), unchanged.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/video_item.dart';
import '../../state/video_library_model.dart';

enum _GroupAction { selectAll, unselect, watched, unwatched, rename, special, fold }

/// The right-click (or long-press) menu on a season's heading (a collection's page, its in-place
/// contents and All videos' group headings): Select all in the season, unselect it, mark it
/// watched or not watched, and — where given — name the season and fold it up or open it.
Future<void> showVideoGroupMenu(
  BuildContext context, {
  required Offset at,
  required String heading,
  required List<VideoItem> list,
  required Set<String> selected,
  required VoidCallback onSelectAll,
  required VoidCallback onUnselect,
  VoidCallback? onRename,
  VoidCallback? onSpecial,
  bool special = false,
  bool? folded,
  VoidCallback? onFold,
}) async {
  final model = context.read<VideoLibraryModel>();
  final ids = [for (final v in list) v.id];
  final allTicked = ids.every(selected.contains);
  final anyTicked = ids.any(selected.contains);
  final allWatched = list.every((v) => model.placeOf(v.id)?.watched ?? false);
  final anyWatched = list.any((v) => model.placeOf(v.id)?.watched ?? false);
  PopupMenuItem<_GroupAction> item(_GroupAction a, String key, IconData icon, String text) => PopupMenuItem(
        key: ValueKey(key),
        value: a,
        child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text)),
      );
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final picked = await showMenu<_GroupAction>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (!allTicked)
        item(_GroupAction.selectAll, 'group-select-all', Icons.select_all, 'Select all in $heading (${list.length})'),
      if (anyTicked) item(_GroupAction.unselect, 'group-unselect', Icons.deselect, 'Unselect $heading'),
      if (!allWatched) item(_GroupAction.watched, 'group-watched', Icons.check_circle_outline, 'Mark as watched'),
      if (anyWatched) item(_GroupAction.unwatched, 'group-unwatched', Icons.remove_done, 'Mark as not watched'),
      if (onRename != null) item(_GroupAction.rename, 'group-rename', Icons.edit_outlined, 'Season title…'),
      // Special seasons (0.1.66): mark a season special with a title, or make it normal again.
      if (onSpecial != null)
        item(_GroupAction.special, 'group-special', special ? Icons.star_outline : Icons.auto_awesome_outlined,
            special ? 'Not special any more' : 'Mark as special…'),
      if (onFold != null && folded != null)
        item(_GroupAction.fold, 'group-fold', folded ? Icons.unfold_more : Icons.unfold_less, folded ? 'Open' : 'Fold up'),
    ],
  );
  switch (picked) {
    case _GroupAction.selectAll:
      onSelectAll();
    case _GroupAction.unselect:
      onUnselect();
    case _GroupAction.watched:
      await model.setWatched(ids, true);
    case _GroupAction.unwatched:
      await model.setWatched(ids, false);
    case _GroupAction.rename:
      onRename?.call();
    case _GroupAction.special:
      onSpecial?.call();
    case _GroupAction.fold:
      onFold?.call();
    case null:
  }
}
