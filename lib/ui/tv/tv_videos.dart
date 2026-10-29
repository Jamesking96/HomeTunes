// The TV's Videos screen (0.2.0, step 2 of the TV interface): tabs for Collections, All videos,
// Continue watching and Favourites, as grids of posters and pictures with the A–Z strip. A
// collection opens its page; a video starts playing.
//
// 0.2.5 (the user, 29 Oct: "a new category at the top of the TV's Video tab that splits the shows
// up based on the type they are", and "more sort & filter options … to see things like Anime, TV
// or Films without looking through the whole list"):
//  * a row of type buttons under the tabs: All · Anime · TV · Films (and any other type the
//    libraries name; state/video_types.dart). Resting on one shows it, as the tabs do, and it
//    applies in whichever tab is showing;
//  * Filter, at the end of that row: watched state, genre, and on this device / streamed /
//    downloaded, with Clear filters;
//  * Sort adds Most episodes (collections) and Not watched first, and Reverse the order.
// What's picked stays while HomeTunes is open (the page is kept when another place is chosen).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/library_index.dart' show sortKey;
import '../../state/library_model.dart';
import '../../state/video_library_model.dart';
import '../../state/video_types.dart';
import '../nav.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_music.dart' show tvEmptyLibraryHints, tvLibraryHints;
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
  recentlyWatched('Recently watched'),
  mostEpisodes('Most episodes'),
  notWatchedFirst('Not watched first');

  const TvVideoSort(this.label);
  final String label;

  /// Whether this sort applies to videos one by one (Most episodes is for collections).
  bool get forVideos => this != mostEpisodes;
}

class TvVideosScreen extends StatefulWidget {
  const TvVideosScreen({super.key});

  @override
  State<TvVideosScreen> createState() => _TvVideosScreenState();
}

class _TvVideosScreenState extends State<TvVideosScreen> {
  var _tab = TvVideoTab.collections;
  var _sort = TvVideoSort.title;
  var _reverse = false;
  var _choice = const VideoChoice();

  WatchState _stateOf(VideoLibraryModel v, VideoCollection c) => collectionWatchState(
        watchedCount: v.watchedCount(c),
        main: c.main.length,
        started: c.main.any((x) => v.placeOf(x.id)?.inProgress ?? false),
      );

  List<T> _reversed<T>(List<T> list) => _reverse ? list.reversed.toList() : list;

  List<VideoCollection> _sortedCollections(VideoLibraryModel v, List<VideoCollection> list) => _reversed(switch (_sort) {
        TvVideoSort.title => list, // the model keeps them A–Z
        TvVideoSort.recentlyAdded => [...list]..sort((a, b) => b.addedMs.compareTo(a.addedMs)),
        TvVideoSort.recentlyWatched => [...list]..sort((a, b) => v.lastWatchedMs(b).compareTo(v.lastWatchedMs(a))),
        TvVideoSort.mostEpisodes => byMostEpisodes(list),
        TvVideoSort.notWatchedFirst => byNotWatchedFirst<VideoCollection>(list, (c) => _stateOf(v, c), (c) => c.name),
      });

  List<VideoItem> _sortedVideos(VideoLibraryModel v, List<VideoItem> list) => _reversed(switch (_sort) {
        TvVideoSort.title || TvVideoSort.mostEpisodes => [...list]..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title))),
        TvVideoSort.recentlyAdded => [...list]..sort((a, b) => (b.addedMs ?? 0).compareTo(a.addedMs ?? 0)),
        TvVideoSort.recentlyWatched => [...list]
          ..sort((a, b) => (v.placeOf(b.id)?.updatedMs ?? 0).compareTo(v.placeOf(a.id)?.updatedMs ?? 0)),
        TvVideoSort.notWatchedFirst => byNotWatchedFirst<VideoItem>(list, (x) => videoWatchState(v.placeOf(x.id)), (x) => x.title),
      });

  /// The A–Z strip only makes sense in A–Z order.
  bool get _azStrip => _sort == TvVideoSort.title && !_reverse;

  /// The sort as the button says it.
  String get _sortLabel => _sort == TvVideoSort.title && _reverse ? 'Z–A' : '${_sort.label}${_reverse ? ', reversed' : ''}';

  Future<void> _chooseSort(BuildContext context) => showTvOptions(context, title: 'Sort videos', options: [
        for (final s in TvVideoSort.values)
          if (_tab != TvVideoTab.all || s.forVideos)
            TvOption(s.label, s == _sort ? Icons.check : Icons.sort, () => setState(() => _sort = s)),
        TvOption(_reverse ? 'Reverse the order: on' : 'Reverse the order: off', _reverse ? Icons.check : Icons.swap_vert,
            subtitle: 'The same sort, the other way round', () => setState(() => _reverse = !_reverse)),
      ]);

  /// The Filter panel: each choice opens its own list; Clear filters once any is set.
  Future<void> _chooseFilters(BuildContext context, List<String> genres) {
    String any<T>(T? x, String Function(T) label) => x == null ? 'Any' : label(x);
    return showTvOptions(context, title: 'Filter videos', subtitle: _choice.type == null ? null : 'Within ${_choice.type}', options: [
      TvOption('Watched: ${any(_choice.watch, (w) => w.label)}', Icons.done_all, opensMore: true, () {
        showTvOptions(context, title: 'Watched', options: [
          TvOption('Any', _choice.watch == null ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(clear: {'watch'}))),
          for (final w in WatchState.values)
            TvOption(w.label, _choice.watch == w ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(watch: w))),
        ]);
      }),
      TvOption('Genre: ${any(_choice.genre, (g) => g)}', Icons.theater_comedy_outlined, opensMore: true, () {
        showTvOptions(context, title: 'Genre', options: [
          TvOption('Any', _choice.genre == null ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(clear: {'genre'}))),
          for (final g in genres)
            TvOption(g, _choice.genre == g ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(genre: g))),
        ]);
      }),
      TvOption('Source: ${any(_choice.source, (s) => s.label)}', Icons.cloud_outlined, opensMore: true, () {
        showTvOptions(context, title: 'Source', options: [
          TvOption('Any', _choice.source == null ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(clear: {'source'}))),
          for (final s in SourceChoice.values)
            TvOption(s.label, _choice.source == s ? Icons.check : Icons.remove, () => setState(() => _choice = _choice.copyWith(source: s))),
        ]);
      }),
      if (_choice.filters > 0)
        TvOption('Clear filters', Icons.filter_alt_off_outlined, () => setState(() => _choice = _choice.withoutFilters)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final videos = context.watch<VideoLibraryModel>();
    final lib = context.read<LibraryModel>();
    final nav = context.read<AppNav>();
    if (nav.takeView(AppNav.favouriteVideosView)) _tab = TvVideoTab.favourites;
    if (_tab == TvVideoTab.all && !_sort.forVideos) _sort = TvVideoSort.title;
    final collectionAspect = lib.settings.video.collectionPictureShape.aspect;
    final videoAspect = lib.settings.video.videoPictureShape.aspect;

    // The types there are (a type that's gone, after a resync or an edit, falls back to All).
    final types = orderTypes([for (final c in videos.collections) collectionType(c)]);
    if (_choice.type != null && !types.contains(_choice.type)) _choice = _choice.copyWith(clear: {'type'});
    final key = '${_choice.type}-${_choice.watch?.name}-${_choice.genre}-${_choice.source?.name}-${_sort.name}-$_reverse';

    List<VideoCollection> chosen(List<VideoCollection> list) => chooseCollections(list, _choice, stateOf: (c) => _stateOf(videos, c));
    List<VideoItem> chosenVideos(List<VideoItem> list) => chooseVideos(list, _choice, placeOf: videos.placeOf);
    // The genres the Filter offers: those among what the type shows.
    final genres = _tab == TvVideoTab.all || _tab == TvVideoTab.continueWatching
        ? genresOf(videos: chooseVideos(videos.videos, VideoChoice(type: _choice.type), placeOf: videos.placeOf))
        : genresOf(collections: chooseCollections(videos.collections, VideoChoice(type: _choice.type), stateOf: (c) => _stateOf(videos, c)));

    Widget nothing() => TvEmpty(
          icon: Icons.filter_alt_off_outlined,
          title: 'Nothing matches',
          message: _choice.filters > 0 ? 'No ${_choice.type ?? 'videos'} match the filters chosen.' : 'There\'s nothing of this type here.',
          action: _choice.filters > 0
              ? TvButton(
                  label: 'Clear filters',
                  icon: Icons.filter_alt_off_outlined,
                  onPressed: () => setState(() => _choice = _choice.withoutFilters),
                )
              : null,
        );

    Widget collections(List<VideoCollection> list, String name) {
      final shown = chosen(list);
      if (shown.isEmpty) return nothing();
      return TvAzGrid<VideoCollection>(
        key: ValueKey('$name-$key'),
        items: _sortedCollections(videos, shown),
        tileWidth: collectionAspect < 1 ? 132 : 180,
        aspectRatio: collectionAspect,
        letterOf: _azStrip ? (c) => tvLetterOf(c.name) : null,
        itemBuilder: (context, c, i, node, w) => tvCollectionTile(context, c, node: node, width: w, aspectRatio: collectionAspect),
      );
    }

    final Widget body;
    if (videos.videos.isEmpty) {
      body = TvEmpty(
        icon: Icons.video_library_outlined,
        title: videos.busy ? 'Looking through your folders…' : 'No videos yet',
        message: videos.busy ? null : 'Choose the folders your videos are in, on a USB drive or the TV itself, or connect a server.',
        action: videos.busy
            ? null
            : TvButton(
                label: 'Add video folders',
                icon: Icons.folder_open,
                primary: true,
                onPressed: () => nav.openSettings('library', setting: 'library-video-folders')),
      );
    } else {
      final grid = switch (_tab) {
        TvVideoTab.collections => collections(videos.collections, 'collections'),
        TvVideoTab.favourites => videos.favouriteCollections.isEmpty
            ? const TvEmpty(
                icon: Icons.favorite_border,
                title: 'No favourites yet',
                message: 'Hold OK on a collection and choose Add to favourites.')
            : collections(videos.favouriteCollections, 'favourites'),
        TvVideoTab.all => () {
            final shown = chosenVideos(videos.videos);
            if (shown.isEmpty) return nothing();
            return TvAzGrid<VideoItem>(
              key: ValueKey('videos-$key'),
              items: _sortedVideos(videos, shown),
              tileWidth: videoAspect < 1 ? 132 : 180,
              aspectRatio: videoAspect,
              letterOf: _azStrip ? (v) => tvLetterOf(v.title) : null,
              itemBuilder: (context, v, i, node, w) => tvVideoTile(context, v, node: node, width: w, aspectRatio: videoAspect),
            );
          }(),
        TvVideoTab.continueWatching => videos.continueWatching.isEmpty
            ? const TvEmpty(icon: Icons.play_circle_outline, title: 'Nothing part-watched', message: 'Videos you stop part-way through show here.')
            : () {
                final shown = chosenVideos(videos.continueWatching);
                if (shown.isEmpty) return nothing();
                return TvAzGrid<VideoItem>(
                  key: ValueKey('continue-$key'),
                  items: shown,
                  tileWidth: 180,
                  itemBuilder: (context, v, i, node, w) => tvVideoTile(context, v, node: node, width: w),
                );
              }(),
      };
      // The type buttons and Filter, over the grid.
      final labels = ['All', ...types];
      body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 40,
          child: Row(children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: TvTabBar(
                  key: const ValueKey('tv-video-types'),
                  labels: labels,
                  selected: _choice.type == null ? 0 : labels.indexOf(_choice.type!),
                  onSelect: (i) => setState(() => _choice = i == 0 ? _choice.copyWith(clear: {'type'}) : _choice.copyWith(type: labels[i])),
                ),
              ),
            ),
            TvButton(
              key: const ValueKey('tv-video-filter'),
              label: _choice.filters == 0 ? 'Filter' : 'Filter (${_choice.filters})',
              icon: Icons.filter_list,
              primary: _choice.filters > 0,
              onPressed: () => _chooseFilters(context, genres),
            ),
            const SizedBox(width: 10),
          ]),
        ),
        const SizedBox(height: 8),
        Expanded(child: grid),
      ]);
    }

    return TvPageHints(
      tab: AppNav.videosTab,
      hints: videos.videos.isEmpty && !videos.busy ? tvEmptyLibraryHints : tvLibraryHints,
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
              label: 'Sort: $_sortLabel',
              icon: Icons.sort,
              onPressed: () => _chooseSort(context),
            ),
        ],
        body: body,
      ),
    );
  }
}
