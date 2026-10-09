// A collection on the Collections and Favourites tabs (CollectionCard: its poster or first video's
// picture, name, category, how many videos and how many are watched) and its menu. Part of
// video_collection_screen.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../video_collection_screen.dart';

/// "12 h 5 min", "45 min".
String collectionLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// How tall a collection card is at [width]: its picture (16:9 unless [shape] says otherwise)
/// plus two lines of text.
double collectionCardHeight(double width, [PictureShape shape = PictureShape.wide]) =>
    (width - 16) / shape.aspect + 16 + 70;

/// One collection in a grid.
class CollectionCard extends StatelessWidget {
  final VideoCollection collection;

  /// What a tap does (the Collections tab opens its contents under the row); without it, a tap
  /// opens the collection's page.
  final VoidCallback? onTap;

  /// Its contents are showing under its row.
  final bool highlighted;

  /// Select mode: [onSelect] ticks or unticks it (right-click › Select, or press and hold).
  final bool selecting;
  final bool selected;
  final VoidCallback? onSelect;

  const CollectionCard({
    super.key,
    required this.collection,
    this.onTap,
    this.highlighted = false,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final c = collection;
    final accent = Theme.of(context).colorScheme.primary;
    final watched = model.watchedCount(c);
    final total = c.main.length;
    final details = [
      if (c.category != null) c.category!,
      total == 1 ? (c.videos.length == 1 ? '1 video' : '1 video + extras') : '$total videos',
      if (c.year != null) '${c.year}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onSecondaryTapUp: (d) => showCollectionMenu(context, c, at: d.globalPosition, onSelect: onSelect),
        onLongPress: onSelect ??
            () {
              final box = context.findRenderObject() as RenderBox;
              showCollectionMenu(context, c, at: box.localToGlobal(box.size.center(Offset.zero)));
            },
        child: InkWell(
          borderRadius: AppShape.circular(8),
          // Selecting: a tap ticks / unticks (Shift + click: a range, 0.1.47); Shift + click when
          // nothing is ticked starts selecting.
          onTap: () {
            if (onSelect != null && (selecting || shiftHeld)) {
              onSelect!();
            } else {
              (onTap ?? () => context.read<AppNav>().openVideoCollection(c.name))();
            }
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: model.collectionShapeOf(c).aspect,
              child: ClipRRect(
                borderRadius: AppShape.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  // A picture of another shape is shown whole, over a blurred copy. Hovering it
                  // shows a play button (like album covers) that plays or carries on.
                  _PlayablePoster(collection: c, enabled: !selecting),
                  if (model.isFavourite(c))
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Icon(Icons.favorite, color: accent, size: 20, shadows: const [Shadow(blurRadius: 4)]),
                    ),
                  if (total > 0 && watched > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                          value: watched / total, minHeight: 4, color: accent, backgroundColor: Colors.black45),
                    ),
                  if (selecting)
                    Positioned(
                      left: 4,
                      top: 4,
                      child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: selected ? accent : Colors.white70, shadows: const [Shadow(blurRadius: 4)]),
                    ),
                  if (selected) Container(color: accent.withValues(alpha: 0.25)),
                  // Its contents are open under the row.
                  if (highlighted)
                    DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: accent, width: 3),
                        borderRadius: AppShape.circular(8),
                      ),
                    ),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(details, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            if (total > 1)
              Text(watched == total ? 'All watched' : '$watched of $total watched',
                  maxLines: 1, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

/// A collection's picture with a play button that shows on hover (plays the next episode, or
/// carries on with it).
class _PlayablePoster extends StatelessWidget {
  final VideoCollection collection;
  final bool enabled;
  const _PlayablePoster({required this.collection, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final picture = PosterPicture(file: model.coverFile(collection));
    final next = model.nextUp(collection);
    if (!enabled || next == null) return picture;
    final started = model.placeOf(next.id)?.inProgress ?? false;
    final what = next.episodeLabel ?? next.title;
    return HoverPlayCover(
      tooltip: started ? 'Continue $what' : 'Play $what',
      onPlay: () => context.read<AppNav>().openVideo(next),
      child: picture,
    );
  }
}

/// A collection's menu (right-click / press and hold on its card, ⋮ on its page). [onSelect]
/// adds "Select" (the Collections tab's select mode).
Future<void> showCollectionMenu(BuildContext context, VideoCollection c,
    {required Offset at, VoidCallback? onSelect}) async {
  final model = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final fav = model.isFavourite(c);
  final allWatched = model.watchedCount(c) == c.main.length && c.main.isNotEmpty;
  final next = model.nextUp(c);
  final lib = model.library;
  final link = QuickLink(QuickLinkKind.collection, c.name, c.name);
  final linked = lib.isQuickLink(link.kind, link.id);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      const PopupMenuItem(
          value: 'open', child: ListTile(leading: Icon(Icons.open_in_new), title: Text('Open collection page'))),
      if (next != null)
        PopupMenuItem(
          value: 'play',
          child: ListTile(
            leading: const Icon(Icons.play_arrow),
            title: Text(model.placeOf(next.id)?.inProgress ?? false ? 'Continue' : 'Play'),
            subtitle: Text(next.episodeLabel ?? next.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      PopupMenuItem(
        value: 'fav',
        child: ListTile(
          leading: Icon(fav ? Icons.favorite : Icons.favorite_border),
          title: Text(fav ? 'Remove from favourites' : 'Add to favourites'),
        ),
      ),
      // A quick link in the sidebar (0.1.64).
      PopupMenuItem(
          value: 'link',
          child: ListTile(leading: Icon(quickLinkMenuIcon(linked)), title: Text(quickLinkMenuText(linked)))),
      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit collection…'))),
      const PopupMenuItem(value: 'poster', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Change poster…'))),
      PopupMenuItem(
        value: 'watched',
        child: ListTile(
          leading: Icon(allWatched ? Icons.remove_done : Icons.done_all),
          title: Text(allWatched ? 'Mark all as not watched' : 'Mark all as watched'),
        ),
      ),
      copyTitleMenuItem('copy'),
      // Where it comes from (0.1.44).
      const PopupMenuItem(value: 'details', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Details…'))),
      if (onSelect != null)
        const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.check_box_outlined), title: Text('Select'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'copy':
      await copyTitle(context, c.name);
    case 'details':
      await openCollectionDetails(context, c);
    case 'select':
      onSelect?.call();
    case 'open':
      nav.openVideoCollection(c.name);
    case 'play':
      if (next != null) nav.openVideo(next);
    case 'fav':
      await model.setFavourite(c, !fav);
    case 'link':
      await lib.toggleQuickLink(link);
    case 'edit':
      await showEditCollection(context, c);
    case 'poster':
      await showCollectionPosterOptions(context, c);
    case 'watched':
      await model.setWatched([for (final v in c.main) v.id], !allWatched);
  }
}
