// The Videos tab (0.1.40): every video in the video folders, in three sub-tabs, like the Library
// tab's Playlists / Artists / Albums / Songs:
//  * Collections: each collection (a series, a film, a folder of home videos; they work like
//    albums) as a card with its poster; tap for its page (video_collection_screen.dart). Search,
//    a filter sheet (category, genre, decade) and sorts (by category with headings, name,
//    recently added / watched, most videos, year).
//  * All videos: every video as a thumbnail, with chips for All / Continue watching / Not watched /
//    Watched, a Continue watching row, search, a filter sheet (category, collection, genre,
//    decade, length, picture, file type) and sorts. Select mode edits or marks several at once.
//  * Favourites: the favourite collections.
// Above them (0.2.9, the user: "TV Shows, Anime and Films are all collatable tabs to help with
// sorting between them"): a row of type tabs, All · Anime · TV Shows · Films (and any other type
// the libraries name), as on the TV (state/video_types.dart). The type chosen narrows all three.
// Tapping a video opens its player page (video_player_screen.dart). Right-click / press and
// hold / ⋮ gives the video's or collection's menu. Everything comes from VideoLibraryModel.
// Refactor phase 6 (9 Oct 2026): the video card and its menu (widgets/video_card.dart) and the
// group heading menu (widgets/video_group_menu.dart) moved out unchanged; they're exported from here.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_group.dart';
import '../../models/video_item.dart';
import '../../state/music_filters.dart';
import '../../state/range_select.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../../state/video_types.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show EmptyState;
import '../widgets/escape_cancels.dart';
import '../widgets/fold_heading.dart';
import '../widgets/filter_sheet.dart' show FilterBar, showFilterSheet, reverseGroupsIf;
import 'video_collection_screen.dart';
import 'video_group_screen.dart' show GroupCard, groupCardHeight;
import 'video_group_actions.dart' show showAddToGroup;
import '../../state/video_groups.dart' show isFilm;
import 'video_pictures.dart';

import '../widgets/video_card.dart';
export '../widgets/video_card.dart' show videoCardHeight, sliverCardRows, videoLength, VideoCard, showVideoMenu;
import '../widgets/video_group_menu.dart';
export '../widgets/video_group_menu.dart' show showVideoGroupMenu;

import '../widgets/video_selection_bar.dart';
export '../widgets/video_selection_bar.dart' show VideoSelectionBar;

class VideosScreen extends StatefulWidget {
  const VideosScreen({super.key});

  /// For tests: the type tabs back to All.
  @visibleForTesting
  static void forgetType() => _VideosScreenState.forgetType();

  @override
  State<VideosScreen> createState() => _VideosScreenState();
}

/// What a type tab says: "TV Shows" for TV (the user's word for them); the others as they are.
String videoTypeLabel(String type) => type == 'TV' ? 'TV Shows' : type;

IconData _typeIcon(String? type) => switch (type) {
      null => Icons.video_library_outlined,
      'Anime' => Icons.auto_awesome_outlined,
      'TV' => Icons.tv_outlined,
      'Films' => Icons.movie_outlined,
      _ => Icons.folder_outlined,
    };

class _VideosScreenState extends State<VideosScreen> {
  /// The type tab chosen (null: All). Kept while HomeTunes is open, like the TV's.
  static String? _chosenType;

  /// For tests: back to All.
  @visibleForTesting
  static void forgetType() => _chosenType = null;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final nav = context.read<AppNav>();

    if (model.videos.isEmpty) {
      final noFolders = model.library.videoFolders.isEmpty;
      return Scaffold(
        appBar: AppBar(title: const Text('Videos', style: TextStyle(fontWeight: FontWeight.w800))),
        body: EmptyState(
          icon: Icons.video_library_outlined,
          title: model.busy ? 'Looking for videos…' : (noFolders ? 'No videos yet' : 'No videos found'),
          message: model.error ??
              (noFolders
                  ? 'Add the folders your videos are in under Settings › Folders & scanning. '
                      'MP4, MKV, WebM, AVI, MOV and most other video files show up here.'
                  : 'None of your video folders has any video files in it yet.'),
          action: model.busy
              ? null
              : FilledButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(noFolders ? 'Add a video folder' : 'Video folders'),
                  onPressed: () => nav.openSettings('library', setting: 'library-video-folders'),
                ),
        ),
      );
    }

    // The types there are; one that's gone (after a resync or an edit) falls back to All.
    final types = orderTypes([for (final c in model.collections) collectionType(c)]);
    if (_chosenType != null && !types.contains(_chosenType)) _chosenType = null;
    final type = _chosenType;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Videos', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Rescan video folders',
              icon: const Icon(Icons.refresh),
              onPressed: model.busy ? null : model.scan,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // Film collections (8 Nov 2026): Collections holds the user's groups of films and
            // the shows and films not in one; All videos is every show and film (what
            // Collections was); Every video is the episode-by-episode grid, in its own tab.
            tabs: [Tab(text: 'Collections'), Tab(text: 'All videos'), Tab(text: 'Every video'), Tab(text: 'Favourites')],
          ),
        ),
        body: Column(children: [
          const _FavouritesRequest(),
          if (types.length > 1)
            _TypeTabs(types: types, chosen: type, onChosen: (t) => setState(() => _chosenType = t)),
          if (model.busy) const LinearProgressIndicator(minHeight: 2),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(model.error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
          Expanded(
            child: TabBarView(children: [
              _CollectionGrid(favourites: false, withGroups: true, type: type, typeTabs: types.length > 1),
              _CollectionGrid(favourites: false, type: type, typeTabs: types.length > 1),
              _AllVideosTab(type: type),
              _CollectionGrid(favourites: true, type: type, typeTabs: types.length > 1),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The type tabs (0.2.9): All, then each type there is. Their own tab row, under Collections /
/// All videos / Favourites, so either can be changed without the other.
class _TypeTabs extends StatelessWidget {
  final List<String> types;
  final String? chosen;
  final ValueChanged<String?> onChosen;
  const _TypeTabs({required this.types, required this.chosen, required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final all = <String?>[null, ...types];
    // Keyed by the types, so a type coming or going starts the row afresh.
    return DefaultTabController(
      key: ValueKey('video-types:${types.join('|')}'),
      length: all.length,
      initialIndex: math.max(0, all.indexOf(chosen)),
      child: Builder(builder: (context) {
        return Align(
          alignment: Alignment.centerLeft,
          child: TabBar.secondary(
            key: const ValueKey('video-type-tabs'),
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (i) => onChosen(all[i]),
            tabs: [
              for (final t in all)
                Tab(
                  key: ValueKey('video-type:${t ?? 'All'}'),
                  height: 40,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_typeIcon(t), size: 18),
                    const SizedBox(width: 6),
                    Text(t == null ? 'All' : videoTypeLabel(t)),
                  ]),
                ),
            ],
          ),
        );
      }),
    );
  }
}

/// The sidebar's Favourite videos (1 Oct): switches to the Favourites tab when asked. Draws nothing.
class _FavouritesRequest extends StatelessWidget {
  const _FavouritesRequest();

  @override
  Widget build(BuildContext context) {
    context.select<AppNav, String?>((n) => n.viewRequest);
    if (context.read<AppNav>().takeView(AppNav.favouriteVideosView)) {
      final tabs = DefaultTabController.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) => tabs.animateTo(3));
    }
    return const SizedBox.shrink();
  }
}

/// The Collections tab, and (with [favourites]) the Favourites tab.
class _CollectionGrid extends StatefulWidget {
  final bool favourites;

  /// The Collections tab (8 Nov 2026): the user's groups of films first, then the shows and films
  /// not in one. Without it (All videos): every show and film.
  final bool withGroups;

  /// The type tab chosen (null: All).
  final String? type;

  /// Whether the type tabs are showing (there's more than one type).
  final bool typeTabs;
  const _CollectionGrid({required this.favourites, this.withGroups = false, this.type, this.typeTabs = false});

  @override
  State<_CollectionGrid> createState() => _CollectionGridState();
}

class _CollectionGridState extends State<_CollectionGrid> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _query = '';
  Filters _only = Filters.none;
  CollectionSort _sort = CollectionSort.category;

  /// The other way round from the sort's usual direction (0.1.69).
  bool _reversed = false;

  /// The collection whose contents are open under its row (by key), like an album on an artist
  /// page.
  String? _open;

  /// Ticked collections (select mode is on while this isn't empty), by key.
  final Set<String> _selected = {};

  void _toggleOpen(VideoCollection c) => setState(() => _open = _open == c.key ? null : c.key);
  // Ticks or unticks a collection; Shift + click ticks everything from the last one clicked, in
  // the order shown ([order], 0.1.47).
  final _range = RangePicker();
  void _toggleSelected(VideoCollection c, List<String> order) => setState(() => _range.pick(_selected, c.key, order));

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = context.watch<VideoLibraryModel>();
    final every = widget.favourites
        ? model.favouriteCollections
        : (widget.withGroups ? model.ungrouped : model.collections);
    if (widget.favourites && every.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border,
        title: 'No favourite collections yet',
        message: 'Tap the heart on a collection\'s page, or right-click a collection and choose Add to favourites.',
      );
    }
    // Just the type chosen above (0.2.9).
    final type = widget.type;
    final all = type == null ? every : [for (final c in every) if (collectionType(c) == type) c];
    final shown = searchCollections(
        [for (final c in all) if (_only.matches(c, collectionFilterFields)) c], _query);
    // The user's groups of films (Collections tab): shown when the group's name matches what's
    // typed, or any of its films passes the type, filters and search.
    final groupsShown = [
      if (widget.withGroups)
        for (final g in model.groups.all)
          if (() {
            final films = [
              for (final f in model.filmsIn(g))
                if ((type == null || collectionType(f) == type) && _only.matches(f, collectionFilterFields)) f
            ];
            if (films.isEmpty) return type == null && _only.isEmpty && g.keys.isEmpty && _query.trim().isEmpty;
            final q = _query.trim().toLowerCase();
            return q.isEmpty || g.name.toLowerCase().contains(q) || searchCollections(films, _query).isNotEmpty;
          }())
            g,
    ];
    // With the type tabs showing, the Category sort's headings (TV, Anime, Films) would only
    // repeat them (4 Nov 2026, the user: "show all videos in order without the dividers of
    // typing"): it's left out of the menu, and All lists every collection in one run, A–Z.
    final sorts = [for (final s in CollectionSort.values) if (!widget.typeTabs || s != CollectionSort.category) s];
    final sort = sorts.contains(_sort) ? _sort : CollectionSort.name;
    final groups = reverseGroupsIf(_reversed, sortCollections(shown, sort, lastWatched: model.lastWatchedMs));
    // The order they're shown in, for Shift + click.
    final order = [for (final (_, list) in groups) for (final c in list) c.key];
    final picked = [for (final c in all) if (_selected.contains(c.key)) c];
    final selecting = picked.isNotEmpty;
    final accent = Theme.of(context).colorScheme.primary;
    // Which tab's headings these are, for remembering what's folded (9 Nov 2026).
    final fold = widget.favourites ? 'videos.favourites' : (widget.withGroups ? 'videos.collections' : 'videos.all');
    return Column(children: [
      if (selecting)
        // Esc cancels the selection, like the ✕ (0.1.48).
        EscapeCancels(onCancel: () => setState(_selected.clear), child: Material(
          color: accent.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(children: [
              IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              Expanded(child: Text('${picked.length} selected', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(
                  onPressed: () => setState(() => _selected.addAll([for (final c in shown) c.key])),
                  child: const Text('Select all')),
              IconButton(
                tooltip: picked.length == 1 ? 'Edit collection' : 'Edit ${picked.length} collections',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showEditCollections(context, picked),
              ),
              // Film collections (step 3): the films picked into one.
              if (picked.any(isFilm))
                IconButton(
                  key: const ValueKey('select-add-to-group'),
                  tooltip: 'Add to collection',
                  icon: const Icon(Icons.library_add_outlined),
                  onPressed: () async {
                    await showAddToGroup(context, picked);
                    if (mounted) setState(_selected.clear);
                  },
                ),
              if (picked.length == 1)
                IconButton(
                  tooltip: 'Change poster',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => showCollectionPosterOptions(context, picked.single),
                ),
              Builder(builder: (context) {
                final allFav = picked.every(model.isFavourite);
                return IconButton(
                  tooltip: allFav ? 'Remove from favourites' : 'Add to favourites',
                  icon: Icon(allFav ? Icons.favorite : Icons.favorite_border),
                  onPressed: () async {
                    for (final c in picked) {
                      await model.setFavourite(c, !allFav);
                    }
                  },
                );
              }),
              IconButton(
                tooltip: 'Mark all as watched',
                icon: const Icon(Icons.done_all),
                onPressed: () async {
                  await model.setWatched([for (final c in picked) for (final v in c.main) v.id], true);
                  setState(_selected.clear);
                },
              ),
              IconButton(
                tooltip: 'Mark all as not watched',
                icon: const Icon(Icons.remove_done),
                onPressed: () async {
                  await model.setWatched([for (final c in picked) for (final v in c.main) v.id], false);
                  setState(_selected.clear);
                },
              ),
            ]),
          ),
        ))
      else
      FilterBar<CollectionSort>(
        controller: _search,
        hint: 'Filter by name, category, genre or year',
        onChanged: (v) => setState(() => _query = v),
        filtersActive: !_only.isEmpty,
        onFilter: () async {
          final picked = await showFilterSheet<VideoCollection>(context,
              items: all, fields: collectionFilterFields, current: _only, showLabel: 'Show collections');
          if (picked != null && mounted) setState(() => _only = picked);
        },
        sort: sort,
        sorts: sorts,
        sortLabel: collectionSortLabel,
        onSort: (s) => setState(() {
          _sort = s;
          _reversed = false;
        }),
        sortWords: collectionSortWords,
        reversed: _reversed,
        onReversed: (r) => setState(() => _reversed = r),
      ),
      _FilterChips(filters: _only, onChanged: (f) => setState(() => _only = f)),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 250).floor().clamp(1, 8);
          final itemWidth = (c.maxWidth - 16) / cols;
          return CustomScrollView(slivers: [
            // The user's groups of films first (8 Nov 2026), then everything not in one.
            if (groupsShown.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: FoldHeading(
                  foldKey: '$fold:Film collections',
                  text: 'Film collections',
                  count: groupsShown.length,
                  onToggle: () => setState(() {}),
                ),
              ),
              if (!FoldedHeadings.isFolded('$fold:Film collections'))
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: sliverCardRows<VideoGroup>(
                  items: groupsShown,
                  cols: cols,
                  height: (_) => groupCardHeight(itemWidth),
                  card: (g) => GroupCard(key: ValueKey('group:${g.id}'), group: g),
                ),
              ),
              if (shown.isNotEmpty && groups.every((x) => x.$1 == null))
                SliverToBoxAdapter(
                  child: FoldHeading(
                    foldKey: '$fold:Shows and films',
                    text: 'Shows and films',
                    count: shown.length,
                    onToggle: () => setState(() {}),
                  ),
                ),
            ],
            if (shown.isEmpty && groupsShown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                      _query.trim().isEmpty && _only.isEmpty && type != null
                          ? (widget.favourites ? 'No favourite ${videoTypeLabel(type)} yet.' : 'No ${videoTypeLabel(type)} here.')
                          : 'No collections match.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textDim)),
                ),
              ),
            for (final (heading, list) in groups) ...[
              if (heading != null)
                SliverToBoxAdapter(
                  child: FoldHeading(
                    foldKey: '$fold:$heading',
                    text: heading,
                    count: list.length,
                    onToggle: () => setState(() {}),
                  ),
                ),
              if (heading != null
                  ? !FoldedHeadings.isFolded('$fold:$heading')
                  : groupsShown.isEmpty || !FoldedHeadings.isFolded('$fold:Shows and films'))
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: sliverCardRows<VideoCollection>(
                  items: list,
                  cols: cols,
                  height: (x) => collectionCardHeight(itemWidth, model.collectionShapeOf(x)),
                  card: (x) => CollectionCard(
                    key: ValueKey('collection-card:${x.key}'),
                    collection: x,
                    // A tap opens its contents under the row (right-click › Open collection page
                    // for the full page).
                    onTap: () => _toggleOpen(x),
                    highlighted: x.key == _open,
                    selecting: selecting,
                    selected: _selected.contains(x.key),
                    onSelect: () => _toggleSelected(x, order),
                  ),
                  after: (row) {
                    final open = row.where((x) => x.key == _open).firstOrNull;
                    return open == null
                        ? null
                        : CollectionContentsPanel(
                            key: ValueKey('panel:${open.key}'),
                            collection: open,
                            onClose: () => setState(() => _open = null),
                          );
                  },
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]);
        }),
      ),
    ]);
  }
}

/// The filters in use, as chips: tap × to remove one.
class _FilterChips extends StatelessWidget {
  final Filters filters;
  final ValueChanged<Filters> onChanged;
  const _FilterChips({required this.filters, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox(height: 4);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final e in filters.picked.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                key: ValueKey('video-filter:${e.key}'),
                avatar: const Icon(Icons.filter_list, size: 16),
                label: Text('${e.key}: ${e.value}'),
                onDeleted: () => onChanged(filters.withValue(e.key, null)),
              ),
            ),
          if (filters.picked.length > 1)
            TextButton(onPressed: () => onChanged(Filters.none), child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

/// The All videos tab.
class _AllVideosTab extends StatefulWidget {
  /// The type tab chosen (null: All).
  final String? type;
  const _AllVideosTab({this.type});

  @override
  State<_AllVideosTab> createState() => _AllVideosTabState();
}

class _AllVideosTabState extends State<_AllVideosTab> with AutomaticKeepAliveClientMixin {
  VideoShow _show = VideoShow.all;
  VideoSort _sort = VideoSort.collection;

  /// The other way round from the sort's usual direction (0.1.69).
  bool _reversed = false;
  final _search = TextEditingController();
  String _query = '';

  /// One category / collection / genre / decade / length / picture / file type to show.
  Filters _only = Filters.none;

  /// Ticked videos (select mode is on while this isn't empty).
  final Set<String> _selected = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _chooseFilters(List<VideoItem> videos) async {
    final picked = await showFilterSheet<VideoItem>(
      context,
      items: videos,
      fields: videoFilterFields,
      current: _only,
      showLabel: 'Show videos',
    );
    if (picked != null && mounted) setState(() => _only = picked);
  }

  // Ticks or unticks a video; Shift + click ticks everything from the last one clicked, in the
  // order shown ([order], 0.1.47).
  final _range = RangePicker();
  void _toggle(String id, List<String> order) => setState(() => _range.pick(_selected, id, order));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = context.watch<VideoLibraryModel>();
    final places = model.places;
    // The type chosen above (0.2.9), then filters and search; the chip counts are for what's left.
    final type = widget.type;
    bool ofType(VideoItem v) => type == null || videoType(v.category) == type;
    final videos = type == null ? model.videos : [for (final v in model.videos) if (ofType(v)) v];
    final narrowed = searchVideos(filterVideos(videos, _only), _query);
    final counts = {
      for (final s in VideoShow.values) s: narrowed.where((v) => videoShown(s, places[v.id])).length,
    };
    final shown = [for (final v in narrowed) if (videoShown(_show, places[v.id])) v];
    final continuingOnly = _show == VideoShow.continueWatching;
    // (Ascending / Descending, 0.1.69: for the chosen sort; Continue watching is always newest
    // first.)
    final groups = reverseGroupsIf(
        _reversed && !continuingOnly,
        sortVideos(shown, continuingOnly ? VideoSort.recentlyWatched : _sort, places: places,
            groupLabel: (name, heading, list) {
          // Season headings with their titles, the user's own included ("Silo · Season 1 – Offline News").
          final c = model.collectionNamed(name);
          return c == null ? heading : model.groupLabel(c, heading, list);
        }));
    final shownIds = [for (final (_, g) in groups) for (final v in g) v.id];
    final continuing =
        _show == VideoShow.all && _query.trim().isEmpty && _only.isEmpty
            ? [for (final v in model.continueWatching) if (ofType(v)) v]
            : const <VideoItem>[];
    final selecting = _selected.isNotEmpty;

    return Column(children: [
      if (selecting)
        VideoSelectionBar(
          selected: _selected,
          onClear: () => setState(_selected.clear),
          onSelectAll: () => setState(() => _selected.addAll(shownIds)),
        )
      else
        FilterBar<VideoSort>(
          controller: _search,
          hint: 'Filter by title, collection, genre or year',
          onChanged: (v) => setState(() => _query = v),
          filtersActive: !_only.isEmpty,
          onFilter: () => _chooseFilters(videos),
          sort: _sort,
          sorts: VideoSort.values,
          sortLabel: videoSortLabel,
          onSort: (s) => setState(() {
            _sort = s;
            _reversed = false;
          }),
          sortWords: videoSortWords,
          reversed: _reversed,
          onReversed: (r) => setState(() => _reversed = r),
        ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 250).floor().clamp(1, 8);
          final itemWidth = (c.maxWidth - 16) / cols;
          return CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  children: [
                    for (final s in VideoShow.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${videoShowLabel(s)} (${counts[s]})'),
                          selected: _show == s,
                          onSelected: (_) => setState(() => _show = s),
                        ),
                      ),
                    // Filters in use: tap to change them, × to remove one.
                    for (final e in _only.picked.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          key: ValueKey('video-filter:${e.key}'),
                          avatar: const Icon(Icons.filter_list, size: 16),
                          label: Text('${e.key}: ${e.value}'),
                          onPressed: () => _chooseFilters(videos),
                          onDeleted: () => setState(() => _only = _only.withValue(e.key, null)),
                        ),
                      ),
                    if (_only.picked.length > 1)
                      TextButton(onPressed: () => setState(() => _only = Filters.none), child: const Text('Clear filters')),
                  ],
                ),
              ),
            ),
            // Continue watching: a row across the top of "All".
            if (continuing.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: FoldHeading(
                  foldKey: 'videos.every:Continue watching',
                  text: 'Continue watching',
                  count: continuing.length,
                  padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                  onToggle: () => setState(() {}),
                ),
              ),
              if (!FoldedHeadings.isFolded('videos.every:Continue watching'))
              SliverToBoxAdapter(
                child: SizedBox(
                  height: continuing.map((v) => videoCardHeight(260, model.shapeOf(v))).reduce(math.max),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final v in continuing)
                        SizedBox(
                          width: 260,
                          child: VideoCard(
                            video: v,
                            selected: _selected.contains(v.id),
                            selecting: selecting,
                            onSelect: () => _toggle(v.id, [for (final x in continuing) x.id]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No videos match.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                ),
              ),
            for (final (header, list) in groups) ...[
              if (header != null)
                SliverToBoxAdapter(
                  child: Builder(builder: (context) {
                    // Right-click (or press and hold) › Select all in this season / group.
                    void menu(Offset at) => showVideoGroupMenu(
                          context,
                          at: at,
                          heading: header,
                          list: list,
                          selected: _selected,
                          onSelectAll: () => setState(() => _selected.addAll([for (final v in list) v.id])),
                          onUnselect: () => setState(() => _selected.removeAll([for (final v in list) v.id])),
                        );
                    return KeyedSubtree(
                      key: ValueKey('group-heading:$header'),
                      child: FoldHeading(
                        foldKey: 'videos.every:$header',
                        text: header,
                        count: list.length,
                        onToggle: () => setState(() {}),
                        onSecondaryTapUp: (d) => menu(d.globalPosition),
                        onLongPressStart: (d) => menu(d.globalPosition),
                      ),
                    );
                  }),
                ),
              if (header == null || !FoldedHeadings.isFolded('videos.every:$header'))
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: sliverCardRows<VideoItem>(
                  items: list,
                  cols: cols,
                  height: (v) => videoCardHeight(itemWidth, model.shapeOf(v)),
                  card: (v) => VideoCard(
                    video: v,
                    selected: _selected.contains(v.id),
                    selecting: selecting,
                    onSelect: () => _toggle(v.id, shownIds),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]);
        }),
      ),
    ]);
  }
}
