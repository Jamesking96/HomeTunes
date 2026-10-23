// The TV's Videos screen (0.2.0, step 2 of the TV interface): tabs for Collections, All videos,
// Continue watching and Favourites, as grids of posters and pictures with the A–Z strip. A
// collection opens its page (its TV version comes in step 3); a video starts playing.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/library_index.dart' show sortKey;
import '../../state/library_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_music.dart' show tvLibraryHints;
import 'tv_options.dart';

enum TvVideoTab {
  collections('Collections'),
  all('All videos'),
  continueWatching('Continue watching'),
  favourites('Favourites');

  const TvVideoTab(this.label);
  final String label;
}

enum TvVideoSort {
  title('A–Z'),
  recentlyAdded('Recently added'),
  recentlyWatched('Recently watched');

  const TvVideoSort(this.label);
  final String label;
}

class TvVideosScreen extends StatefulWidget {
  const TvVideosScreen({super.key});

  @override
  State<TvVideosScreen> createState() => _TvVideosScreenState();
}

class _TvVideosScreenState extends State<TvVideosScreen> {
  var _tab = TvVideoTab.collections;
  var _sort = TvVideoSort.title;

  List<VideoCollection> _sortedCollections(VideoLibraryModel v, List<VideoCollection> list) => switch (_sort) {
        TvVideoSort.title => list, // the model keeps them A–Z
        TvVideoSort.recentlyAdded => [...list]..sort((a, b) => b.addedMs.compareTo(a.addedMs)),
        TvVideoSort.recentlyWatched => [...list]..sort((a, b) => v.lastWatchedMs(b).compareTo(v.lastWatchedMs(a))),
      };

  List<VideoItem> _sortedVideos(VideoLibraryModel v) => switch (_sort) {
        TvVideoSort.title => [...v.videos]..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title))),
        TvVideoSort.recentlyAdded => [...v.videos]..sort((a, b) => (b.addedMs ?? 0).compareTo(a.addedMs ?? 0)),
        TvVideoSort.recentlyWatched => [...v.videos]
          ..sort((a, b) => (v.placeOf(b.id)?.updatedMs ?? 0).compareTo(v.placeOf(a.id)?.updatedMs ?? 0)),
      };

  @override
  Widget build(BuildContext context) {
    final videos = context.watch<VideoLibraryModel>();
    final lib = context.read<LibraryModel>();
    final nav = context.read<AppNav>();
    if (nav.takeView(AppNav.favouriteVideosView)) _tab = TvVideoTab.favourites;
    final collectionAspect = lib.settings.video.collectionPictureShape.aspect;
    final videoAspect = lib.settings.video.videoPictureShape.aspect;

    Widget collections(List<VideoCollection> list, String key) => TvAzGrid<VideoCollection>(
          key: ValueKey('$key-${_sort.name}'),
          items: _sortedCollections(videos, list),
          tileWidth: collectionAspect < 1 ? 132 : 180,
          aspectRatio: collectionAspect,
          letterOf: _sort == TvVideoSort.title ? (c) => tvLetterOf(c.name) : null,
          itemBuilder: (context, c, i, node, w) => tvCollectionTile(context, c, node: node, width: w, aspectRatio: collectionAspect),
        );

    final Widget body;
    if (videos.videos.isEmpty) {
      body = TvEmpty(
        icon: Icons.video_library_outlined,
        title: videos.busy ? 'Looking through your folders…' : 'No videos yet',
        message: videos.busy ? null : 'Choose the folders your videos are in, in Settings › Folders & scanning.',
        action: videos.busy
            ? null
            : TvButton(
                label: 'Add video folders',
                icon: Icons.folder_open,
                primary: true,
                onPressed: () => nav.openSettings('library', setting: 'library-video-folders')),
      );
    } else {
      body = switch (_tab) {
        TvVideoTab.collections => collections(videos.collections, 'collections'),
        TvVideoTab.favourites => videos.favouriteCollections.isEmpty
            ? const TvEmpty(
                icon: Icons.favorite_border,
                title: 'No favourites yet',
                message: 'Hold OK on a collection and choose Add to favourites.')
            : collections(videos.favouriteCollections, 'favourites'),
        TvVideoTab.all => TvAzGrid<VideoItem>(
            key: ValueKey('videos-${_sort.name}'),
            items: _sortedVideos(videos),
            tileWidth: videoAspect < 1 ? 132 : 180,
            aspectRatio: videoAspect,
            letterOf: _sort == TvVideoSort.title ? (v) => tvLetterOf(v.title) : null,
            itemBuilder: (context, v, i, node, w) => tvVideoTile(context, v, node: node, width: w, aspectRatio: videoAspect),
          ),
        TvVideoTab.continueWatching => videos.continueWatching.isEmpty
            ? const TvEmpty(icon: Icons.play_circle_outline, title: 'Nothing part-watched', message: 'Videos you stop part-way through show here.')
            : TvAzGrid<VideoItem>(
                key: const ValueKey('continue'),
                items: videos.continueWatching,
                tileWidth: 180,
                itemBuilder: (context, v, i, node, w) => tvVideoTile(context, v, node: node, width: w),
              ),
      };
    }

    return TvPageHints(
      tab: AppNav.videosTab,
      hints: tvLibraryHints,
      child: TvPage(
        title: 'Videos',
        tabs: TvTabBar(
          labels: [for (final t in TvVideoTab.values) t.label],
          selected: _tab.index,
          onSelect: (i) => setState(() => _tab = TvVideoTab.values[i]),
        ),
        actions: [
          if (_tab != TvVideoTab.continueWatching && videos.videos.isNotEmpty)
            TvButton(
              key: const ValueKey('tv-sort'),
              label: 'Sort: ${_sort.label}',
              icon: Icons.sort,
              onPressed: () => showTvOptions(context, title: 'Sort videos', options: [
                for (final s in TvVideoSort.values)
                  TvOption(s.label, s == _sort ? Icons.check : Icons.sort, () => setState(() => _sort = s)),
              ]),
            ),
        ],
        body: body,
      ),
    );
  }
}
