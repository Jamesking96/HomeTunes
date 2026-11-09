// Film collections, step 2 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): a group of the
// user's films ("Pokémon", "James Bond") as a card on the Collections tab, and its own page.
// Each film keeps its own card, page, place and watched mark; the group only lists them
// (VideoLibraryModel.groups, models/video_group.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_group.dart';
import '../../models/video_item.dart';
import '../../state/remote_videos.dart' show remoteServerOf;
import '../../state/video_groups.dart' show isFilm;
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show EmptyState;
import 'video_collection_screen.dart' show CollectionCard, collectionCardHeight;
import 'video_group_actions.dart';
import 'video_pictures.dart' show PosterPicture;
import 'videos_screen.dart' show sliverCardRows;

/// "3 films · 1998–2000".
String groupDetails(List<VideoCollection> films) {
  final years = [for (final f in films) ?f.year]..sort();
  return [
    films.length == 1 ? '1 film' : '${films.length} films',
    if (years.isNotEmpty) years.first == years.last ? '${years.first}' : '${years.first}–${years.last}',
  ].join(' · ');
}

/// Up to four of its films' posters, side by side (one fills the whole picture).
class GroupPicture extends StatelessWidget {
  const GroupPicture({super.key, required this.films, this.group});
  final List<VideoCollection> films;

  /// Its own picture, when one was chosen (step 3), is shown instead.
  final VideoGroup? group;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final own = group == null ? null : model.groupPosterFile(group!);
    if (own != null) return PosterPicture(file: own);
    final shown = films.take(4).toList();
    if (shown.isEmpty) {
      return ColoredBox(
        color: AppColors.surfaceHigh,
        child: Center(child: Icon(Icons.video_library_outlined, size: 40, color: AppColors.textDim)),
      );
    }
    Widget poster(VideoCollection c) => PosterPicture(file: model.coverFile(c));
    if (shown.length < 4) {
      // One to three: side by side.
      return Row(children: [
        for (final c in shown) Expanded(child: poster(c)),
      ]);
    }
    return Column(children: [
      Expanded(child: Row(children: [Expanded(child: poster(shown[0])), Expanded(child: poster(shown[1]))])),
      Expanded(child: Row(children: [Expanded(child: poster(shown[2])), Expanded(child: poster(shown[3]))])),
    ]);
  }
}

/// How tall a group card is at [width] (the same as a collection card, so they line up).
double groupCardHeight(double width) => collectionCardHeight(width);

/// Whether [g] is shared with the other devices (9 Nov 2026; docs/ai-context/
/// 09_COLLECTION_SHARING_PLAN.md): "Shared through Den", "Waiting to share with Den" (or what's
/// wrong), or "Only on this device" when none of its films are on a server. Null with sharing off.
({String text, bool shared, bool problem})? groupShareLine(VideoLibraryModel model, VideoGroup g) {
  if (!model.shareGroups) return null;
  final through = model.sharedThrough(g);
  if (through.isNotEmpty) return (text: 'Shared through ${through.join(' and ')}', shared: true, problem: false);
  if (g.links.isNotEmpty) return (text: 'Shared with your other devices', shared: true, problem: false);
  final servers = <String>{
    for (final c in model.filmsIn(g))
      if (isFilm(c)) ?remoteServerOf(c.main.single.id),
  };
  if (servers.isEmpty) return (text: 'Only on this device: none of its films are on a server', shared: false, problem: false);
  for (final s in servers) {
    final problem = model.sharing[s]?.problem;
    if (problem != null) return (text: problem, shared: false, problem: true);
  }
  final name = [for (final s in servers) ?model.sharing[s]?.server].firstOrNull;
  return (text: name == null ? 'Waiting to share with your other devices' : 'Waiting to share with $name', shared: false, problem: false);
}

/// A group on the Collections tab.
class GroupCard extends StatelessWidget {
  const GroupCard({super.key, required this.group});
  final VideoGroup group;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final films = model.filmsIn(group);
    final watched = model.watchedInGroup(group);
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(8),
      // Right-click / press and hold: its menu (step 3).
      child: GestureDetector(
        onSecondaryTapUp: (d) => showGroupMenu(context, group, at: d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          showGroupMenu(context, group, at: box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: InkWell(
        key: ValueKey('group-card:${group.id}'),
        borderRadius: AppShape.circular(8),
        onTap: () => context.read<AppNav>().openVideoGroup(group.id),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: PictureShape.wide.aspect,
            child: ClipRRect(
              borderRadius: AppShape.circular(8),
              child: Stack(fit: StackFit.expand, children: [
                GroupPicture(films: films, group: group),
                // A collection of films: a small stack mark in the corner.
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: AppShape.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      // Shared with the other devices (9 Nov 2026): a small cloud.
                      if (groupShareLine(model, group)?.shared ?? false) ...[
                        const Icon(Icons.cloud_done_outlined, key: ValueKey('group-shared'), size: 14, color: Colors.white),
                        const SizedBox(width: 6),
                      ],
                      const Icon(Icons.collections_bookmark_outlined, size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('${films.length}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                ),
                if (films.isNotEmpty && watched > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                        value: watched / films.length, minHeight: 4, color: accent, backgroundColor: Colors.black45),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(group.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(['Collection', groupDetails(films)].join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          if (films.length > 1)
            Text(watched == films.length ? 'All watched' : '$watched of ${films.length} watched',
                maxLines: 1, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ]),
      ),
      ),
    );
  }
}

/// A group's page: its picture, name and description, Continue / Play (the next film not yet
/// watched), then its films as cards.
class VideoGroupScreen extends StatelessWidget {
  const VideoGroupScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final nav = context.read<AppNav>();
    final g = model.groups.byId(groupId);
    if (g == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.video_library_outlined, title: 'This collection has been deleted'),
      );
    }
    final films = model.filmsIn(g);
    final next = model.nextInGroup(g);
    final nextVideo = next == null ? null : model.nextUp(next);
    final started = nextVideo != null && (model.placeOf(nextVideo.id)?.inProgress ?? false);
    final watched = model.watchedInGroup(g);
    final missing = g.keys.length - films.length;
    return Scaffold(
      appBar: AppBar(actions: [
        // Step 3: change it.
        IconButton(
          key: const ValueKey('group-edit'),
          tooltip: 'Edit collection',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => showEditGroup(context, g),
        ),
        IconButton(
          tooltip: 'Change picture',
          icon: const Icon(Icons.image_outlined),
          onPressed: () => showGroupPosterOptions(context, g),
        ),
        Builder(
          builder: (context) => IconButton(
            key: const ValueKey('group-more'),
            tooltip: 'More',
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              final box = context.findRenderObject() as RenderBox;
              showGroupMenu(context, g, at: box.localToGlobal(box.size.bottomLeft(Offset.zero)), onPage: true);
            },
          ),
        ),
      ]),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 640;
        final cols = (box.maxWidth / 250).floor().clamp(1, 8);
        final itemWidth = (box.maxWidth - 16) / cols;
        final picture = SizedBox(
          width: wide ? 320 : box.maxWidth - 32,
          child: AspectRatio(
            aspectRatio: PictureShape.wide.aspect,
            child: ClipRRect(borderRadius: AppShape.circular(8), child: GroupPicture(films: films, group: g)),
          ),
        );
        final about = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('COLLECTION', style: TextStyle(color: AppColors.textDim, fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Text(g.name, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              [
                groupDetails(films),
                if (films.isNotEmpty) watched == films.length ? 'all watched' : '$watched watched',
                if (missing > 0) '$missing not here now',
              ].join(' · '),
              style: TextStyle(color: AppColors.textDim)),
          if (groupShareLine(model, g) case final share?) ...[
            const SizedBox(height: 4),
            Row(key: const ValueKey('group-share-line'), crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                  share.problem
                      ? Icons.cloud_off_outlined
                      : (share.shared ? Icons.cloud_done_outlined : Icons.cloud_queue_outlined),
                  size: 16,
                  color: share.problem ? Theme.of(context).colorScheme.error : AppColors.textDim),
              const SizedBox(width: 6),
              Flexible(child: Text(share.text, style: TextStyle(color: AppColors.textDim, fontSize: 13))),
            ]),
          ],
          if (g.description != null) ...[
            const SizedBox(height: 10),
            Text(g.description!),
          ],
          const SizedBox(height: 14),
          if (next != null && nextVideo != null)
            FilledButton.icon(
              key: const ValueKey('group-play'),
              icon: const Icon(Icons.play_arrow),
              label: Text('${started ? 'Continue' : 'Play'}: ${next.name}', overflow: TextOverflow.ellipsis),
              onPressed: () => nav.openVideo(nextVideo),
            ),
        ]);
        return CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverToBoxAdapter(
              child: wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      picture,
                      const SizedBox(width: 24),
                      Expanded(child: about),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [picture, const SizedBox(height: 16), about]),
            ),
          ),
          if (films.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.movie_outlined,
                title: 'No films here yet',
                message: 'Right-click a film (or press and hold) and choose Add to collection.',
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: sliverCardRows<VideoCollection>(
              items: films,
              cols: cols,
              height: (x) => collectionCardHeight(itemWidth, model.collectionShapeOf(x)),
              card: (x) => CollectionCard(key: ValueKey('group-film:${x.key}'), collection: x),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]);
      }),
    );
  }
}
