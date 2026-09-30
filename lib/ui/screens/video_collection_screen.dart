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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/save_nfo.dart';
import 'videos_screen.dart' show showVideoMenu, videoLength;

/// "12 h 5 min", "45 min".
String collectionLength(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// How tall a collection card is at [width]: a 16:9 picture plus two lines of text.
double collectionCardHeight(double width) => (width - 16) * 9 / 16 + 16 + 70;

/// A picture from disk, or a placeholder.
class _Picture extends StatelessWidget {
  final String? file;
  final IconData icon;
  final Alignment alignment;
  const _Picture({required this.file, this.icon = Icons.video_library_outlined, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surface,
        child: file != null
            ? Image.file(File(file!), fit: BoxFit.cover, alignment: alignment, cacheWidth: 640,
                errorBuilder: (_, _, _) => Center(child: Icon(icon, size: 40, color: AppColors.textDim)))
            : Center(child: Icon(icon, size: 40, color: AppColors.textDim)),
      );
}

/// One collection in a grid.
class CollectionCard extends StatelessWidget {
  final VideoCollection collection;
  const CollectionCard({super.key, required this.collection});

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
        onSecondaryTapUp: (d) => showCollectionMenu(context, c, at: d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          showCollectionMenu(context, c, at: box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: InkWell(
          borderRadius: AppShape.circular(8),
          onTap: () => context.read<AppNav>().openVideoCollection(c.name),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: AppShape.circular(8),
                child: Stack(fit: StackFit.expand, children: [
                  // Posters are tall: show their top part, where the title usually is.
                  _Picture(file: model.coverFile(c), alignment: c.cover != null ? const Alignment(0, -0.6) : Alignment.center),
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

/// A collection's menu (right-click / press and hold on its card, ⋮ on its page).
Future<void> showCollectionMenu(BuildContext context, VideoCollection c, {required Offset at}) async {
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
      const PopupMenuItem(value: 'open', child: ListTile(leading: Icon(Icons.video_library_outlined), title: Text('Open'))),
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
      PopupMenuItem(
        value: 'watched',
        child: ListTile(
          leading: Icon(allWatched ? Icons.remove_done : Icons.done_all),
          title: Text(allWatched ? 'Mark all as not watched' : 'Mark all as watched'),
        ),
      ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'open':
      nav.openVideoCollection(c.name);
    case 'play':
      if (next != null) nav.openVideo(next);
    case 'fav':
      await model.setFavourite(c, !fav);
    case 'edit':
      await showEditCollection(context, c);
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
      final picture = ClipRRect(
        borderRadius: AppShape.circular(8),
        child: SizedBox(
          width: wide ? 320 : box.maxWidth,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _Picture(file: model.coverFile(c), alignment: c.cover != null ? const Alignment(0, -0.6) : Alignment.center),
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
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: header),
        for (final (heading, list) in c.groups) ...[
          if (heading != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text('$heading  (${list.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
          SliverList.builder(
            itemCount: list.length,
            itemBuilder: (_, i) => EpisodeRow(video: list[i], isNext: list[i].id == next?.id),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
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
