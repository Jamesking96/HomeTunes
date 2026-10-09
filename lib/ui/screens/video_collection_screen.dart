// Videos (0.1.40): collections, which work like albums.
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
// Refactor phase 6 (9 Oct 2026): split into video_collection/ (the card, the contents panel and the
// episode list are parts of this file; Edit collection and the season title dialog are their own
// files, exported from here). Nothing in them changed.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/range_select.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show HoverPlayCover;
import '../widgets/quick_links.dart';
import 'video_details_screen.dart' show openCollectionDetails;
import 'special_seasons.dart';
import 'video_pictures.dart';
import 'videos_screen.dart' show VideoSelectionBar, showVideoGroupMenu, showVideoMenu, videoLength;
import '../widgets/selectable_title.dart';

import 'video_collection/season_title_dialog.dart';
export 'video_collection/season_title_dialog.dart' show showSeasonTitleDialog;
import 'video_collection/edit_collection.dart';
export 'video_collection/edit_collection.dart' show showEditCollections, showEditCollection;
part 'video_collection/collection_card.dart';
part 'video_collection/contents_panel.dart';
part 'video_collection/episode_list.dart';

/// A collection's page.
class VideoCollectionScreen extends StatefulWidget {
  final String name;
  const VideoCollectionScreen({super.key, required this.name});

  @override
  State<VideoCollectionScreen> createState() => _VideoCollectionScreenState();
}

class _VideoCollectionScreenState extends State<VideoCollectionScreen> with _EpisodeSelection {
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
        SelectableTitle(c.name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
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
          // Like an album page's ⓘ (0.1.44).
          IconButton(
            key: const ValueKey('collection-details'),
            tooltip: 'Details: where it comes from',
            icon: const Icon(Icons.info_outline),
            onPressed: () => openCollectionDetails(context, c),
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
          // A quick link in the sidebar (0.1.64).
          QuickLinkButton(link: QuickLink(QuickLinkKind.collection, c.name, c.name)),
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
      // Ticked videos (right-click › Select): the selection bar sits above the list.
      body: Column(
        children: [
          if (selectingVideos) selectionBar(c),
          Expanded(
            child: CustomScrollView(controller: _scroll, slivers: [
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
                              label: Text('${model.groupLabel(c, heading, list)} (${list.length})'),
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
                label: model.groupLabel(c, heading, list),
                special: VideoLibraryModel.isSpecialGroup(list),
                onRename: switch (seasonOfGroup(heading, list)) {
                  null => null,
                  final s => () => showSeasonTitleDialog(context, c, s.season, s.sub),
                },
                ticked: seasonTicked(list),
                onTick: selectingVideos ? () => tickSeason(list) : null,
                onMenu: (at) => headingMenu(at, c, heading, list,
                    folded: _collapsed.contains(heading), onFold: () => _toggle(heading)),
              ),
            ),
          if (heading == null || !_collapsed.contains(heading))
            SliverFixedExtentList.builder(
              itemExtent: rowExtent,
              itemCount: list.length,
              itemBuilder: (_, i) =>
                  episodeRow(list[i], next, () => [for (final (_, l) in groups) for (final x in l) x.id]),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
          ),
        ],
      ),
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
