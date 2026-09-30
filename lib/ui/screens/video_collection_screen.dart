// Videos (0.1.32): collections, which work like albums.
//
// A collection is a series, a film or a folder of home videos (VideoCollection, built by
// VideoLibraryModel from each video's collection name). This file has:
//  * CollectionCard: a collection on the Collections and Favourites tabs: its poster (or its
//    first video's picture), name, category, how many videos and how many are watched;
//  * VideoCollectionScreen: its page: picture, details and description, Play / Continue (the
//    next episode to watch), a favourite heart, Edit collection, Mark all as watched, then its
//    videos under Season 1…, named parts, Specials and Extras;
//  * showEditCollection: Edit collection. Like editing an album, a new name, category, year or
//    genre is saved on every video in it (as edits, the files aren't changed); the description
//    belongs to the collection.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show HoverPlayCover;
import '../widgets/save_nfo.dart';
import 'video_pictures.dart';
import 'videos_screen.dart' show showVideoMenu, videoLength;

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

/// A picture from disk, or a placeholder.
class _Picture extends StatelessWidget {
  final String? file;
  final IconData icon;
  const _Picture({required this.file, this.icon = Icons.video_library_outlined});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surface,
        child: file != null
            ? Image.file(File(file!), fit: BoxFit.cover, cacheWidth: 640,
                errorBuilder: (_, _, _) => Center(child: Icon(icon, size: 40, color: AppColors.textDim)))
            : Center(child: Icon(icon, size: 40, color: AppColors.textDim)),
      );
}

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
          onTap: selecting ? onSelect : (onTap ?? () => context.read<AppNav>().openVideoCollection(c.name)),
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

class _CollectionContentsPanelState extends State<CollectionContentsPanel> {
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
                  Text(c.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
          for (final (heading, list) in groups) ...[
            if (heading != null)
              _GroupHeading(
                heading: heading,
                count: list.length,
                watched: list.where((v) => model.placeOf(v.id)?.watched ?? false).length,
                folded: folded.contains(heading),
                hasNext: list.any((v) => v.id == next?.id),
                onTap: () => setState(() => folded.contains(heading) ? folded.remove(heading) : folded.add(heading)),
              ),
            if (heading == null || !folded.contains(heading))
              for (final v in list)
                SizedBox(
                  height: _VideoCollectionScreenState.rowExtent,
                  child: EpisodeRow(video: v, isNext: v.id == next?.id),
                ),
          ],
          const SizedBox(height: 8),
        ]),
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
      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit collection…'))),
      const PopupMenuItem(value: 'poster', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Change poster…'))),
      PopupMenuItem(
        value: 'watched',
        child: ListTile(
          leading: Icon(allWatched ? Icons.remove_done : Icons.done_all),
          title: Text(allWatched ? 'Mark all as not watched' : 'Mark all as watched'),
        ),
      ),
      if (onSelect != null)
        const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.check_box_outlined), title: Text('Select'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'select':
      onSelect?.call();
    case 'open':
      nav.openVideoCollection(c.name);
    case 'play':
      if (next != null) nav.openVideo(next);
    case 'fav':
      await model.setFavourite(c, !fav);
    case 'edit':
      await showEditCollection(context, c);
    case 'poster':
      await showCollectionPosterOptions(context, c);
    case 'watched':
      await model.setWatched([for (final v in c.main) v.id], !allWatched);
  }
}

/// A collection's page.
class VideoCollectionScreen extends StatefulWidget {
  final String name;
  const VideoCollectionScreen({super.key, required this.name});

  @override
  State<VideoCollectionScreen> createState() => _VideoCollectionScreenState();
}

class _VideoCollectionScreenState extends State<VideoCollectionScreen> {
  // Follows the collection if it's renamed from this page.
  late String _name = widget.name;

  // Seasons / parts / Specials / Extras that are folded up (by heading), for this visit.
  final Set<String> _collapsed = {};
  final ScrollController _scroll = ScrollController();
  // The header's height (picture, details, buttons), measured after it's drawn, so a
  // contents chip can work out where its season starts.
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;

  /// Height of one video's row, and of a season's heading.
  static const rowExtent = 98.0;
  static const headingExtent = 52.0;
  static const contentsExtent = 56.0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _toggle(String heading) => setState(() => _collapsed.contains(heading) ? _collapsed.remove(heading) : _collapsed.add(heading));

  /// Opens [heading] (if folded) and scrolls so it sits just under the contents bar.
  void _jumpTo(List<(String?, List<VideoItem>)> groups, String heading) {
    setState(() => _collapsed.remove(heading));
    var offset = _headerHeight;
    for (final (h, list) in groups) {
      if (h == heading) break;
      if (h != null) offset += headingExtent;
      if (h == null || !_collapsed.contains(h)) offset += list.length * rowExtent;
    }
    // After the rebuild, so the unfolded season's rows count towards the end of the list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final to = offset.clamp(0.0, _scroll.position.maxScrollExtent);
      _scroll.animateTo(to, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    });
  }

  Future<void> _edit(VideoCollection c) async {
    final renamed = await showEditCollection(context, c);
    if (renamed != null && mounted) setState(() => _name = renamed);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final c = model.collectionNamed(_name);
    if (c == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('This collection isn\'t in your videos any more.')));
    }
    final accent = Theme.of(context).colorScheme.primary;
    final fav = model.isFavourite(c);
    final next = model.nextUp(c);
    final watched = model.watchedCount(c);
    final allWatched = watched == c.main.length && c.main.isNotEmpty;
    final nextStarted = next != null && (model.placeOf(next.id)?.inProgress ?? false);
    final extras = c.videos.length - c.main.length;
    final facts = [
      if (c.category != null) c.category!,
      if (c.year != null) '${c.year}',
      if (c.genre != null) c.genre!,
    ].join(' · ');
    final counts = [
      '${c.main.length} ${c.main.length == 1 ? 'video' : 'videos'}',
      if (extras > 0) '$extras extra${extras == 1 ? '' : 's'}',
      if (c.totalDuration > Duration.zero) collectionLength(c.totalDuration),
      if (c.main.length > 1) '$watched watched',
    ].join(' · ');

    final header = LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 700;
      final shape = model.collectionShapeOf(c);
      // Tall and square pictures are narrower, so they aren't huge.
      final width = shape == PictureShape.wide ? 320.0 : 220.0;
      final picture = ClipRRect(
        borderRadius: AppShape.circular(8),
        child: SizedBox(
          width: wide ? width : (shape == PictureShape.wide ? box.maxWidth : math.min(box.maxWidth, 260.0)),
          child: AspectRatio(
            aspectRatio: shape.aspect,
            child: _PlayablePoster(collection: c),
          ),
        ),
      );
      final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        if (facts.isNotEmpty) Text(facts, style: TextStyle(color: AppColors.textDim)),
        Text(counts, style: TextStyle(color: AppColors.textDim)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (next != null)
            FilledButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: Text(nextStarted
                  ? 'Continue ${next.episodeLabel ?? ''}'.trim()
                  : (watched == 0 ? 'Play' : 'Play ${next.episodeLabel ?? next.title}')),
              onPressed: () => context.read<AppNav>().openVideo(next),
            ),
          IconButton(
            tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
            icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? accent : null),
            onPressed: () => model.setFavourite(c, !fav),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit collection'),
            onPressed: () => _edit(c),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined),
            label: const Text('Change poster'),
            onPressed: () => showCollectionPosterOptions(context, c),
          ),
          OutlinedButton.icon(
            icon: Icon(allWatched ? Icons.remove_done : Icons.done_all),
            label: Text(allWatched ? 'Mark all as not watched' : 'Mark all as watched'),
            onPressed: () => model.setWatched([for (final v in c.main) v.id], !allWatched),
          ),
        ]),
        if (c.description != null) ...[
          const SizedBox(height: 12),
          SelectableText(c.description!),
        ],
      ]);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [picture, const SizedBox(width: 20), Expanded(child: info)])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [picture, const SizedBox(height: 12), info]),
      );
    });

    final groups = c.groups;
    final headed = [for (final (h, list) in groups) if (h != null) (h, list)];
    // Measure the header once it's drawn (the contents chips need to know where seasons start).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = _headerKey.currentContext?.findRenderObject();
      if (box is RenderBox && box.hasSize) _headerHeight = box.size.height;
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
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
        ],
      ),
      body: CustomScrollView(controller: _scroll, slivers: [
        SliverToBoxAdapter(child: KeyedSubtree(key: _headerKey, child: header)),
        // Contents: a chip per season / part / Specials / Extras that jumps there. Stays at the
        // top while scrolling.
        if (headed.length > 1)
          SliverPersistentHeader(
            pinned: true,
            delegate: _ContentsBar(
              extent: contentsExtent,
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: Row(children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      children: [
                        for (final (heading, list) in headed)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              key: ValueKey('contents-$heading'),
                              avatar: list.any((v) => v.id == next?.id)
                                  ? Icon(Icons.play_arrow, size: 16, color: accent)
                                  : (list.every((v) => model.placeOf(v.id)?.watched ?? false)
                                      ? Icon(Icons.check, size: 16, color: accent)
                                      : null),
                              label: Text('$heading (${list.length})'),
                              onPressed: () => _jumpTo(groups, heading),
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('fold-all'),
                    onPressed: () => setState(() {
                      if (_collapsed.length == headed.length) {
                        _collapsed.clear();
                      } else {
                        _collapsed.addAll([for (final (h, _) in headed) h]);
                      }
                    }),
                    child: Text(_collapsed.length == headed.length ? 'Open all' : 'Fold all'),
                  ),
                  const SizedBox(width: 8),
                ]),
              ),
            ),
          ),
        for (final (heading, list) in groups) ...[
          if (heading != null)
            SliverToBoxAdapter(
              child: _GroupHeading(
                heading: heading,
                count: list.length,
                watched: list.where((v) => model.placeOf(v.id)?.watched ?? false).length,
                folded: _collapsed.contains(heading),
                hasNext: list.any((v) => v.id == next?.id),
                onTap: () => _toggle(heading),
              ),
            ),
          if (heading == null || !_collapsed.contains(heading))
            SliverFixedExtentList.builder(
              itemExtent: rowExtent,
              itemCount: list.length,
              itemBuilder: (_, i) => EpisodeRow(video: list[i], isNext: list[i].id == next?.id),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}

/// The pinned contents bar on a collection's page.
class _ContentsBar extends SliverPersistentHeaderDelegate {
  final double extent;
  final Widget child;
  _ContentsBar({required this.extent, required this.child});

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => SizedBox.expand(child: child);

  @override
  bool shouldRebuild(_ContentsBar old) => true;
}

/// A season's heading: tap to fold it up or open it again.
class _GroupHeading extends StatelessWidget {
  final String heading;
  final int count, watched;
  final bool folded, hasNext;
  final VoidCallback onTap;
  const _GroupHeading(
      {required this.heading,
      required this.count,
      required this.watched,
      required this.folded,
      required this.hasNext,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: _VideoCollectionScreenState.headingExtent,
      child: InkWell(
        key: ValueKey('heading-$heading'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            AnimatedRotation(
              turns: folded ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(Icons.expand_more),
            ),
            const SizedBox(width: 6),
            Text('$heading  ($count)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (hasNext) ...[
              const SizedBox(width: 8),
              Icon(Icons.play_arrow, size: 18, color: accent),
            ],
            const Spacer(),
            Text(
              watched == 0 ? '' : (watched == count ? 'All watched' : '$watched of $count watched'),
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ]),
        ),
      ),
    );
  }
}

/// One video in a collection's list: picture, "S1 E4 · Title", length and progress.
class EpisodeRow extends StatelessWidget {
  final VideoItem video;
  final bool isNext;
  const EpisodeRow({super.key, required this.video, this.isNext = false});

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final place = context.select<VideoLibraryModel, VideoPlace?>((m) => m.placeOf(video.id));
    final accent = Theme.of(context).colorScheme.primary;
    final label = video.episodeLabel;
    final progress = place?.progress(video.duration) ?? 0;
    void menu(Offset at) => showVideoMenu(context, video, at: at);
    return GestureDetector(
      onSecondaryTapUp: (d) => menu(d.globalPosition),
      child: InkWell(
        onTap: () => context.read<AppNav>().openVideo(video),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          menu(box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Container(
          color: isNext ? accent.withValues(alpha: 0.08) : null,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 150,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: AppShape.circular(6),
                  child: Stack(fit: StackFit.expand, children: [
                    _Picture(file: model.thumbFile(video), icon: Icons.movie_outlined),
                    if (progress > 0 && !(place?.watched ?? false))
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(value: progress, minHeight: 3, color: accent, backgroundColor: Colors.black45),
                      ),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    if (label != null) TextSpan(text: '$label  ', style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
                    TextSpan(text: video.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  [
                    if (video.duration > Duration.zero) videoLength(video.duration),
                    if (isNext) (place?.inProgress ?? false) ? 'Carry on from here' : 'Up next',
                  ].join(' · '),
                  style: TextStyle(color: AppColors.textDim, fontSize: 12),
                ),
              ]),
            ),
            if (place?.watched ?? false)
              Tooltip(message: 'Watched', child: Icon(Icons.check_circle, color: accent, size: 20)),
            Builder(
              builder: (context) => IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () {
                  final box = context.findRenderObject() as RenderBox;
                  menu(box.localToGlobal(box.size.center(Offset.zero)));
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Edit collection for one or several (select mode on the Collections tab). For several, only
/// what's typed or picked is changed: category, year, genre and poster shape (a name or a
/// description for several at once wouldn't make sense).
Future<void> showEditCollections(BuildContext context, List<VideoCollection> list) async {
  if (list.isEmpty) return;
  if (list.length == 1) {
    await showEditCollection(context, list.single);
    return;
  }
  await showDialog<void>(context: context, builder: (_) => _EditSeveralCollections(collections: list));
}

class _EditSeveralCollections extends StatefulWidget {
  final List<VideoCollection> collections;
  const _EditSeveralCollections({required this.collections});

  @override
  State<_EditSeveralCollections> createState() => _EditSeveralCollectionsState();
}

class _EditSeveralCollectionsState extends State<_EditSeveralCollections> {
  late final List<VideoCollection> _list = widget.collections;
  late final _category = TextEditingController(text: _common((c) => c.category) ?? '');
  late final _year = TextEditingController(text: _common((c) => c.year?.toString()) ?? '');
  late final _genre = TextEditingController(text: _common((c) => c.genre) ?? '');
  late final VideoLibraryModel _model = context.read<VideoLibraryModel>();
  late final Set<PictureShape?> _startShapes = {for (final c in _list) _model.ownCollectionShapeOf(c)};
  late PictureShape? _shape = _startShapes.length == 1 ? _startShapes.single : null;
  late bool _shapeMixed = _startShapes.length > 1;
  bool _shapeChanged = false;
  String? _yearError;
  bool _saving = false;

  String? _common(String? Function(VideoCollection) get) {
    final values = {for (final c in _list) get(c)};
    return values.length == 1 ? values.single : null;
  }

  String? _hint(String? Function(VideoCollection) get) => _common(get) == null ? '--:--' : null;

  @override
  void dispose() {
    for (final t in [_category, _year, _genre]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final y = _year.text.trim();
    final year = y.isEmpty ? null : int.tryParse(y);
    if (y.isNotEmpty && (year == null || year < 1800 || year > 2200)) {
      setState(() => _yearError = 'A year like 2019');
      return;
    }
    setState(() => _saving = true);
    String? typed(TextEditingController t, String? Function(VideoCollection) get) {
      final v = t.text.trim();
      return v.isEmpty || v == _common(get) ? null : v;
    }

    final category = typed(_category, (c) => c.category);
    final genre = typed(_genre, (c) => c.genre);
    final newYear = year != null && '$year' != _common((c) => c.year?.toString()) ? year : null;
    for (final c in _list) {
      if (_shapeChanged) await _model.setCollectionShape(c, _shape);
      if (category != null || genre != null || newYear != null) {
        await _model.editCollection(c, category: category, genre: genre, year: newYear);
      }
    }
    if (!mounted) return;
    saveNfoAfterEdit(context, [for (final c in _list) ...c.videos]);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = {for (final x in _model.collections) if (x.category != null) x.category!}.toList()..sort();
    return AlertDialog(
      title: Text('Edit ${_list.length} collections'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_list.map((c) => c.name).join(', '),
                maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collections-category'),
              controller: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: _hint((c) => c.category) ?? 'TV, Anime, Films…',
                suffixIcon: categories.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a category',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (x) => setState(() => _category.text = x),
                        itemBuilder: (_) => [for (final x in categories) PopupMenuItem(value: x, child: Text(x))],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('collections-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _yearError = null),
                  decoration: InputDecoration(labelText: 'Year', hintText: _hint((c) => c.year?.toString()), errorText: _yearError),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('collections-genre'),
                  controller: _genre,
                  decoration: InputDecoration(labelText: 'Genre', hintText: _hint((c) => c.genre)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            PictureShapePicker(
              title: 'Poster shape (Look)${_shapeMixed ? ': these differ' : ''}',
              value: _shape,
              usual: _model.library.collectionPictureShape,
              mixed: _shapeMixed,
              onChanged: (s) => setState(() {
                _shape = s;
                _shapeMixed = false;
                _shapeChanged = true;
              }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Only what you type or pick is changed; the rest is left as it is. Changes are saved on every '
                  'video in these collections.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            const SaveNfoCheckbox(),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

/// Edit collection. Returns the new name if it was renamed, or null.
Future<String?> showEditCollection(BuildContext context, VideoCollection c) =>
    showDialog<String>(context: context, builder: (_) => _EditCollection(collection: c));

class _EditCollection extends StatefulWidget {
  final VideoCollection collection;
  const _EditCollection({required this.collection});

  @override
  State<_EditCollection> createState() => _EditCollectionState();
}

class _EditCollectionState extends State<_EditCollection> {
  late final VideoCollection c = widget.collection;
  late final _name = TextEditingController(text: c.name);
  late final _category = TextEditingController(text: c.category ?? '');
  late final _year = TextEditingController(text: c.year?.toString() ?? '');
  late final _genre = TextEditingController(text: c.genre ?? '');
  late final _description = TextEditingController(text: c.description ?? '');
  String? _yearError;
  bool _saving = false;
  // Look: the collection's own picture shape, or the usual one (null).
  late PictureShape? _shape = context.read<VideoLibraryModel>().ownCollectionShapeOf(c);

  @override
  void dispose() {
    for (final t in [_name, _category, _year, _genre, _description]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final y = _year.text.trim();
    final year = y.isEmpty ? null : int.tryParse(y);
    if (y.isNotEmpty && (year == null || year < 1800 || year > 2200)) {
      setState(() => _yearError = 'A year like 2019');
      return;
    }
    setState(() => _saving = true);
    final model = context.read<VideoLibraryModel>();
    final name = _name.text.trim();
    final category = _category.text.trim();
    final genre = _genre.text.trim();
    // Before a rename, which carries the shape across.
    if (_shape != model.ownCollectionShapeOf(c)) await model.setCollectionShape(c, _shape);
    await model.editCollection(
      c,
      name: name.isNotEmpty && name != c.name ? name : null,
      category: category.isNotEmpty && category != c.category ? category : null,
      clearCategory: category.isEmpty && c.category != null,
      year: year != null && year != c.year ? year : null,
      clearYear: year == null && c.year != null,
      genre: genre.isNotEmpty && genre != c.genre ? genre : null,
      clearGenre: genre.isEmpty && c.genre != null,
      description: _description.text.trim() != (c.description ?? '') ? _description.text : null,
    );
    if (!mounted) return;
    saveNfoAfterEdit(context, c.videos);
    Navigator.of(context).pop(name.isNotEmpty && name != c.name ? name : null);
  }

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final categories = {for (final x in model.collections) if (x.category != null) x.category!}.toList()..sort();
    return AlertDialog(
      title: const Text('Edit collection'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Changes are saved on all ${c.videos.length} videos in this collection.',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', helperText: 'Another collection\'s name joins the two'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-category'),
              controller: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                hintText: 'TV, Anime, Films…',
                suffixIcon: categories.isEmpty
                    ? null
                    : PopupMenuButton<String>(
                        tooltip: 'Choose a category',
                        icon: const Icon(Icons.arrow_drop_down),
                        onSelected: (x) => setState(() => _category.text = x),
                        itemBuilder: (_) => [for (final x in categories) PopupMenuItem(value: x, child: Text(x))],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 120,
                child: TextField(
                  key: const ValueKey('collection-year'),
                  controller: _year,
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() => _yearError = null),
                  decoration: InputDecoration(labelText: 'Year', errorText: _yearError),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const ValueKey('collection-genre'),
                  controller: _genre,
                  decoration: const InputDecoration(labelText: 'Genre'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('collection-description'),
              controller: _description,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            PictureShapePicker(
              title: 'Poster shape (Look)',
              value: _shape,
              usual: model.library.collectionPictureShape,
              onChanged: (s) => setState(() => _shape = s),
            ),
            const SizedBox(height: 8),
            const SaveNfoCheckbox(),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
