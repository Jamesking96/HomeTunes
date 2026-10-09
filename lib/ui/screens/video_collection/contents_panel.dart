// A collection's contents opened under its row on the Collections tab. Part of
// video_collection_screen.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../video_collection_screen.dart';

/// A collection's contents shown in place under its row on the Collections tab (like an album's
/// songs on an artist page): name and details, Play / Continue, "Open collection page" and a
/// close button, then its seasons. With several seasons only the one with the next episode starts
/// open; the others open from their headings.
class CollectionContentsPanel extends StatefulWidget {
  final VideoCollection collection;
  final VoidCallback onClose;
  const CollectionContentsPanel({super.key, required this.collection, required this.onClose});

  @override
  State<CollectionContentsPanel> createState() => _CollectionContentsPanelState();
}

class _CollectionContentsPanelState extends State<CollectionContentsPanel> with _EpisodeSelection {
  Set<String>? _folded;

  @override
  void initState() {
    super.initState();
    // Opened low down the screen (under a tall card, say): scroll it up into view, keeping a
    // little of the card row above it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final scrollable = Scrollable.maybeOf(context);
      final box = context.findRenderObject();
      final view = scrollable?.context.findRenderObject();
      if (scrollable == null || box is! RenderBox || view is! RenderBox || !box.hasSize) return;
      final top = box.localToGlobal(Offset.zero, ancestor: view).dy;
      final height = view.size.height;
      if (top < height * 0.6) return;
      final position = scrollable.position;
      final to = (position.pixels + top - height * 0.35).clamp(position.minScrollExtent, position.maxScrollExtent);
      position.animateTo(to, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    // The collection as it is now (it may have been edited while open).
    final c = model.collectionNamed(widget.collection.name) ?? widget.collection;
    final next = model.nextUp(c);
    final groups = c.groups;
    final headed = [for (final (h, _) in groups) ?h];
    _folded ??= headed.length < 2
        ? <String>{}
        : {
            for (final (h, list) in groups)
              if (h != null && !list.any((v) => v.id == (next ?? c.videos.first).id)) h
          };
    final folded = _folded!;
    final started = next != null && (model.placeOf(next.id)?.inProgress ?? false);
    final details = [
      if (c.category != null) c.category!,
      if (c.year != null) '${c.year}',
      '${c.main.length} ${c.main.length == 1 ? 'video' : 'videos'}',
      if (c.totalDuration > Duration.zero) collectionLength(c.totalDuration),
      if (c.main.length > 1) '${model.watchedCount(c)} watched',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Material(
        key: ValueKey('collection-panel:${c.key}'),
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppShape.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SelectableTitle(c.name, maxLines: 1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(details, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                ]),
              ),
              if (next != null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: FilledButton.icon(
                    key: const ValueKey('panel-play'),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('${started ? 'Continue' : 'Play'} ${next.episodeLabel ?? ''}'.trim()),
                    onPressed: () => context.read<AppNav>().openVideo(next),
                  ),
                ),
              IconButton(
                key: const ValueKey('panel-open-page'),
                tooltip: 'Open collection page',
                icon: const Icon(Icons.open_in_new),
                onPressed: () => context.read<AppNav>().openVideoCollection(c.name),
              ),
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_vert),
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox;
                    showCollectionMenu(context, c, at: box.localToGlobal(box.size.center(Offset.zero)));
                  },
                ),
              ),
              IconButton(
                key: const ValueKey('panel-close'),
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: widget.onClose,
              ),
            ]),
          ),
          if (selectingVideos) selectionBar(c),
          for (final (heading, list) in groups) ...[
            if (heading != null)
              _GroupHeading(
                heading: heading,
                count: list.length,
                watched: list.where((v) => model.placeOf(v.id)?.watched ?? false).length,
                folded: folded.contains(heading),
                hasNext: list.any((v) => v.id == next?.id),
                onTap: () => setState(() => folded.contains(heading) ? folded.remove(heading) : folded.add(heading)),
                label: model.groupLabel(c, heading, list),
                special: VideoLibraryModel.isSpecialGroup(list),
                onRename: switch (seasonOfGroup(heading, list)) {
                  null => null,
                  final s => () => showSeasonTitleDialog(context, c, s.season, s.sub),
                },
                ticked: seasonTicked(list),
                onTick: selectingVideos ? () => tickSeason(list) : null,
                onMenu: (at) => headingMenu(at, c, heading, list,
                    folded: folded.contains(heading),
                    onFold: () =>
                        setState(() => folded.contains(heading) ? folded.remove(heading) : folded.add(heading))),
              ),
            if (heading == null || !folded.contains(heading))
              for (final v in list)
                SizedBox(
                  height: _VideoCollectionScreenState.rowExtent,
                  child: episodeRow(v, next, () => [for (final (_, l) in groups) for (final x in l) x.id]),
                ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}
