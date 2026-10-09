// A season's own title (the pencil on a season heading): showSeasonTitleDialog. Split out of
// video_collection_screen.dart in refactor phase 6 (9 Oct 2026), unchanged.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/video_item.dart';
import '../../../state/video_library_model.dart';
import '../../theme.dart';
import '../../widgets/save_nfo.dart';

/// Name a season ("Season 1 – Offline News"). The title the season's folder gives is offered;
/// an empty box shows none. Saved into the series' tvshow.nfo too when that's ticked.
Future<void> showSeasonTitleDialog(BuildContext context, VideoCollection c, int season, [int? sub]) async {
  final model = context.read<VideoLibraryModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await showDialog<String>(
    context: context,
    builder: (_) => _SeasonTitleDialog(
      season: seasonText(season, sub),
      current: model.seasonTitleOf(c, season, sub) ?? '',
      fromFolder: model.folderSeasonTitle(c, season, sub),
    ),
  );
  if (result == null) return;
  final errors =
      await model.setSeasonTitle(c, season, result.trim(), sub: sub, writeNfo: canSaveNfo && model.saveNfo);
  if (errors.isNotEmpty) {
    messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t save into tvshow.nfo (${errors.first})')));
  }
}

class _SeasonTitleDialog extends StatefulWidget {
  /// "1", or "1.2".
  final String season;
  final String current;
  final String? fromFolder;
  const _SeasonTitleDialog({required this.season, required this.current, required this.fromFolder});

  @override
  State<_SeasonTitleDialog> createState() => _SeasonTitleDialogState();
}

class _SeasonTitleDialogState extends State<_SeasonTitleDialog> {
  late final controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final season = widget.season, fromFolder = widget.fromFolder;
    return AlertDialog(
        title: Text('Season $season title'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              key: const ValueKey('season-title-field'),
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. Offline News',
                prefixText: 'Season $season – ',
                suffixIcon: IconButton(
                  tooltip: 'No title',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(controller.clear),
                ),
              ),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 8),
            if (fromFolder != null)
              TextButton.icon(
                key: const ValueKey('season-title-folder'),
                icon: const Icon(Icons.folder_outlined),
                label: Text('Use the folder\'s title: $fromFolder', maxLines: 1, overflow: TextOverflow.ellipsis),
                onPressed: () => setState(() => controller.text = fromFolder),
              )
            else
              Text('The season\'s folder doesn\'t give it a title.',
                  style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SaveNfoCheckbox(),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const ValueKey('season-title-save'),
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      );
  }
}
