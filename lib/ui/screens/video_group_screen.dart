// Film collections, step 2 (plan: docs/ai-context/07_FILM_COLLECTIONS_PLAN.md): a group of the
// user's films ("Pokémon", "James Bond") as a card on the Collections tab, and its own page.
// Each film keeps its own card, page, place and watched mark; the group only lists them
// (VideoLibraryModel.groups, models/video_group.dart).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_group.dart';
import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/cards.dart' show EmptyState;
import 'video_collection_screen.dart' show CollectionCard, collectionCardHeight;
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
  const GroupPicture({super.key, required this.films});
  final List<VideoCollection> films;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
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
                GroupPicture(films: films),
                // A collection of films: a small stack mark in the corner.
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: AppShape.circular(6)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
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
      appBar: AppBar(),
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 640;
        final cols = (box.maxWidth / 250).floor().clamp(1, 8);
        final itemWidth = (box.maxWidth - 16) / cols;
        final picture = SizedBox(
          width: wide ? 320 : box.maxWidth - 32,
          child: AspectRatio(
            aspectRatio: PictureShape.wide.aspect,
            child: ClipRRect(borderRadius: AppShape.circular(8), child: GroupPicture(films: films)),
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
