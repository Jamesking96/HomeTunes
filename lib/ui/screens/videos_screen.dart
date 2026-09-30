// The Videos tab (0.1.32): every video in the video folders, in three sub-tabs, like the Library
// tab's Playlists / Artists / Albums / Songs:
//  * Collections: each collection (a series, a film, a folder of home videos; they work like
//    albums) as a card with its poster; tap for its page (video_collection_screen.dart). Search,
//    a filter sheet (category, genre, decade) and sorts (by category with headings, name,
//    recently added / watched, most videos, year).
//  * All videos: every video as a thumbnail, with chips for All / Continue watching / Not watched /
//    Watched, a Continue watching row, search, a filter sheet (category, collection, genre,
//    decade, length, picture, file type) and sorts. Select mode edits or marks several at once.
//  * Favourites: the favourite collections.
// Tapping a video opens its player page (video_player_screen.dart). Right-click / press and
// hold / ⋮ gives the video's or collection's menu. Everything comes from VideoLibraryModel.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/music_filters.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show EmptyState;
import '../widgets/music_filter_sheet.dart' show MusicFilterBar, showMusicFilterSheet;
import 'edit_video.dart';
import 'video_collection_screen.dart';
import 'video_pictures.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

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

    return DefaultTabController(
      length: 3,
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
            tabs: [Tab(text: 'Collections'), Tab(text: 'All videos'), Tab(text: 'Favourites')],
          ),
        ),
        body: Column(children: [
          if (model.busy) const LinearProgressIndicator(minHeight: 2),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(model.error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
            ),
          const Expanded(
            child: TabBarView(children: [
              _CollectionGrid(favourites: false),
              _AllVideosTab(),
              _CollectionGrid(favourites: true),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The Collections tab, and (with [favourites]) the Favourites tab.
class _CollectionGrid extends StatefulWidget {
  final bool favourites;
  const _CollectionGrid({required this.favourites});

  @override
  State<_CollectionGrid> createState() => _CollectionGridState();
}

class _CollectionGridState extends State<_CollectionGrid> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _query = '';
  MusicFilters _only = MusicFilters.none;
  CollectionSort _sort = CollectionSort.category;

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
    final all = widget.favourites ? model.favouriteCollections : model.collections;
    if (widget.favourites && all.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border,
        title: 'No favourite collections yet',
        message: 'Tap the heart on a collection\'s page, or right-click a collection and choose Add to favourites.',
      );
    }
    final shown = searchCollections(
        [for (final c in all) if (_only.matches(c, collectionFilterFields)) c], _query);
    final groups = sortCollections(shown, _sort, lastWatched: model.lastWatchedMs);
    return Column(children: [
      MusicFilterBar<CollectionSort>(
        controller: _search,
        hint: 'Filter by name, category, genre or year',
        onChanged: (v) => setState(() => _query = v),
        filtersActive: !_only.isEmpty,
        onFilter: () async {
          final picked = await showMusicFilterSheet<VideoCollection>(context,
              items: all, fields: collectionFilterFields, current: _only, showLabel: 'Show collections');
          if (picked != null && mounted) setState(() => _only = picked);
        },
        sort: _sort,
        sorts: CollectionSort.values,
        sortLabel: collectionSortLabel,
        onSort: (s) => setState(() => _sort = s),
      ),
      _FilterChips(filters: _only, onChanged: (f) => setState(() => _only = f)),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final cols = (c.maxWidth / 250).floor().clamp(1, 8);
          final itemWidth = (c.maxWidth - 16) / cols;
          return CustomScrollView(slivers: [
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No collections match.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
                ),
              ),
            for (final (heading, list) in groups) ...[
              if (heading != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(heading, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: sliverCardRows<VideoCollection>(
                  items: list,
                  cols: cols,
                  height: (x) => collectionCardHeight(itemWidth, model.collectionShapeOf(x)),
                  card: (x) => CollectionCard(collection: x),
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
  final MusicFilters filters;
  final ValueChanged<MusicFilters> onChanged;
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
            TextButton(onPressed: () => onChanged(MusicFilters.none), child: const Text('Clear filters')),
        ],
      ),
    );
  }
}

/// The All videos tab.
class _AllVideosTab extends StatefulWidget {
  const _AllVideosTab();

  @override
  State<_AllVideosTab> createState() => _AllVideosTabState();
}

class _AllVideosTabState extends State<_AllVideosTab> with AutomaticKeepAliveClientMixin {
  VideoShow _show = VideoShow.all;
  VideoSort _sort = VideoSort.collection;
  final _search = TextEditingController();
  String _query = '';

  /// One category / collection / genre / decade / length / picture / file type to show.
  MusicFilters _only = MusicFilters.none;

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
    final picked = await showMusicFilterSheet<VideoItem>(
      context,
      items: videos,
      fields: videoFilterFields,
      current: _only,
      showLabel: 'Show videos',
    );
    if (picked != null && mounted) setState(() => _only = picked);
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final model = context.watch<VideoLibraryModel>();
    final places = model.places;
    // Filters and search first; the chip counts are for what's left.
    final narrowed = searchVideos(filterVideos(model.videos, _only), _query);
    final counts = {
      for (final s in VideoShow.values) s: narrowed.where((v) => videoShown(s, places[v.id])).length,
    };
    final shown = [for (final v in narrowed) if (videoShown(_show, places[v.id])) v];
    final groups = sortVideos(shown, _show == VideoShow.continueWatching ? VideoSort.recentlyWatched : _sort,
        places: places);
    final shownIds = [for (final (_, g) in groups) for (final v in g) v.id];
    final continuing =
        _show == VideoShow.all && _query.trim().isEmpty && _only.isEmpty ? model.continueWatching : const <VideoItem>[];
    final selecting = _selected.isNotEmpty;
    final accent = Theme.of(context).colorScheme.primary;

    return Column(children: [
      if (selecting)
        Material(
          color: accent.withValues(alpha: 0.18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(children: [
              IconButton(tooltip: 'Clear selection', icon: const Icon(Icons.close), onPressed: () => setState(_selected.clear)),
              Expanded(child: Text('${_selected.length} selected', style: const TextStyle(fontWeight: FontWeight.w600))),
              TextButton(onPressed: () => setState(() => _selected.addAll(shownIds)), child: const Text('Select all')),
              IconButton(
                tooltip: 'Edit details',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showEditVideos(context, [for (final id in _selected) model.byId(id)].whereType<VideoItem>().toList()),
              ),
              IconButton(
                tooltip: 'Mark as watched',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () async {
                  await model.setWatched(_selected, true);
                  setState(_selected.clear);
                },
              ),
              IconButton(
                tooltip: 'Mark as not watched',
                icon: const Icon(Icons.remove_done),
                onPressed: () async {
                  await model.setWatched(_selected, false);
                  setState(_selected.clear);
                },
              ),
            ]),
          ),
        )
      else
        MusicFilterBar<VideoSort>(
          controller: _search,
          hint: 'Filter by title, collection, genre or year',
          onChanged: (v) => setState(() => _query = v),
          filtersActive: !_only.isEmpty,
          onFilter: () => _chooseFilters(model.videos),
          sort: _sort,
          sorts: VideoSort.values,
          sortLabel: videoSortLabel,
          onSort: (s) => setState(() => _sort = s),
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
                          onPressed: () => _chooseFilters(model.videos),
                          onDeleted: () => setState(() => _only = _only.withValue(e.key, null)),
                        ),
                      ),
                    if (_only.picked.length > 1)
                      TextButton(onPressed: () => setState(() => _only = MusicFilters.none), child: const Text('Clear filters')),
                  ],
                ),
              ),
            ),
            // Continue watching: a row across the top of "All".
            if (continuing.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Continue watching', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
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
                            onSelect: () => _toggle(v.id),
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
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ),
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
                    onSelect: () => _toggle(v.id),
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

/// How tall a video card is at [width]: its picture (16:9 unless [shape] says otherwise) plus
/// two lines of text.
double videoCardHeight(double width, [PictureShape shape = PictureShape.wide]) => (width - 16) / shape.aspect + 16 + 64;

/// Cards in rows of [cols], each row as tall as its tallest card (videos and collections can
/// each have their own picture shape, so a plain grid's equal cells won't do).
Widget sliverCardRows<T>({
  required List<T> items,
  required int cols,
  required double Function(T) height,
  required Widget Function(T) card,
}) =>
    SliverList.builder(
      itemCount: (items.length / cols).ceil(),
      itemBuilder: (_, r) {
        final row = items.skip(r * cols).take(cols).toList();
        return SizedBox(
          height: row.map(height).reduce(math.max),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final x in row) Expanded(child: card(x)),
            for (var i = row.length; i < cols; i++) const Expanded(child: SizedBox()),
          ]),
        );
      },
    );

/// "1:05:12" / "4:31".
String videoLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// One video in the grid: thumbnail with its length and progress, title, collection · year.
class VideoCard extends StatelessWidget {
  final VideoItem video;
  final bool selected;
  final bool selecting;
  final VoidCallback onSelect;
  const VideoCard({super.key, required this.video, required this.selected, required this.selecting, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final place = context.select<VideoLibraryModel, VideoPlace?>((m) => m.placeOf(video.id));
    final accent = Theme.of(context).colorScheme.primary;
    final thumb = model.thumbFile(video);
    final progress = place?.progress(video.duration) ?? 0;
    final subtitle = [video.collection, video.episodeLabel ?? (video.year != null ? '${video.year}' : null)].whereType<String>().join(' \u00b7 ');

    return Padding(
      padding: const EdgeInsets.all(8),
      child: GestureDetector(
        onSecondaryTapUp: (d) => showVideoMenu(context, video, at: d.globalPosition, onSelect: onSelect),
        onLongPress: onSelect,
        child: InkWell(
          borderRadius: AppShape.circular(8),
          onTap: selecting ? onSelect : () => context.read<AppNav>().openVideo(video),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: model.shapeOf(video).aspect,
              child: ClipRRect(
                borderRadius: AppShape.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  Container(
                    color: AppColors.surface,
                    child: thumb != null
                        ? Image.file(File(thumb), fit: BoxFit.cover, cacheWidth: 480, errorBuilder: (_, _, _) => const _NoPicture())
                        : const _NoPicture(),
                  ),
                  if (video.duration > Duration.zero)
                    Positioned(
                      right: 6,
                      bottom: progress > 0 ? 10 : 6,
                      child: _Badge(videoLength(video.duration)),
                    ),
                  if (place?.watched ?? false)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Tooltip(message: 'Watched', child: Icon(Icons.check_circle, color: accent, size: 22)),
                    ),
                  if (progress > 0 && !(place?.watched ?? false))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(value: progress, minHeight: 4, color: accent, backgroundColor: Colors.black45),
                    ),
                  if (selecting)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: selected ? accent : Colors.white70),
                    ),
                  if (selected) Container(color: accent.withValues(alpha: 0.25)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                ]),
              ),
              if (!selecting)
                Builder(
                  builder: (context) => IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'More',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () {
                      final box = context.findRenderObject() as RenderBox;
                      showVideoMenu(context, video, at: box.localToGlobal(box.size.center(Offset.zero)), onSelect: onSelect);
                    },
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _NoPicture extends StatelessWidget {
  const _NoPicture();
  @override
  Widget build(BuildContext context) =>
      Center(child: Icon(Icons.movie_outlined, size: 40, color: AppColors.textDim));
}

class _Badge extends StatelessWidget {
  final String text;
  const _Badge(this.text);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

/// A video's menu (⋮, right-click, or from its player page).
Future<void> showVideoMenu(BuildContext context, VideoItem video, {required Offset at, VoidCallback? onSelect}) async {
  final model = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final watched = model.placeOf(video.id)?.watched ?? false;
  final started = model.placeOf(video.id)?.inProgress ?? false;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final choice = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      const PopupMenuItem(value: 'play', child: ListTile(leading: Icon(Icons.play_arrow), title: Text('Play'))),
      if (started)
        const PopupMenuItem(value: 'restart', child: ListTile(leading: Icon(Icons.replay), title: Text('Play from the start'))),
      const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit details…'))),
      const PopupMenuItem(value: 'picture', child: ListTile(leading: Icon(Icons.image_outlined), title: Text('Change picture…'))),
      PopupMenuItem(
        value: 'collection',
        child: ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: const Text('Go to collection'),
          subtitle: Text(video.collection, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      PopupMenuItem(
        value: 'watched',
        child: ListTile(
          leading: Icon(watched ? Icons.remove_done : Icons.check_circle_outline),
          title: Text(watched ? 'Mark as not watched' : 'Mark as watched'),
        ),
      ),
      if (Platform.isWindows)
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Show in folder'))),
      if (onSelect != null)
        const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.check_box_outlined), title: Text('Select'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'play':
      nav.openVideo(video);
    case 'restart':
      await model.setWatched([video.id], false);
      nav.openVideo(video);
    case 'edit':
      await showEditVideos(context, [video]);
    case 'picture':
      await showVideoPictureOptions(context, video);
    case 'collection':
      nav.openVideoCollection(video.collection);
    case 'watched':
      await model.setWatched([video.id], !watched);
    case 'folder':
      final file = model.playableFile(video);
      if (file != null) await Process.run('explorer', ['/select,', p.normalize(file)]);
    case 'select':
      onSelect?.call();
  }
}
