// The TV's video collection page (0.2.0, step 3 of the TV interface): the poster, name, category /
// year / genre, how many videos and how many are watched, Play / Continue (the next one to watch),
// the heart, and the description; then, when it has seasons, a tab per season (Season 1, Specials,
// Extras…), and its videos as big rows with their picture and how far you got. OK plays a video;
// holding OK gives Play and Mark as watched. In TV mode AppNav opens this instead of the usual page.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../screens/video_collection_screen.dart' show collectionLength;
import '../theme.dart';
import 'tv_browse.dart';
import 'tv_detail.dart';
import 'tv_items.dart';
import 'tv_widgets.dart';

class TvCollectionPage extends StatefulWidget {
  const TvCollectionPage({super.key, required this.name});
  final String name;

  @override
  State<TvCollectionPage> createState() => _TvCollectionPageState();
}

class _TvCollectionPageState extends State<TvCollectionPage> {
  /// The season tab showing (null: the one with the next video to watch).
  int? _group;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final nav = context.read<AppNav>();
    final c = model.collectionNamed(widget.name);
    if (c == null) return const TvMissingPage(icon: Icons.video_library_outlined, title: 'This collection isn\'t in your videos any more');
    final fav = model.isFavourite(c);
    final next = model.nextUp(c);
    final watched = model.watchedCount(c);
    final nextStarted = next != null && (model.placeOf(next.id)?.inProgress ?? false);
    final extras = c.videos.length - c.main.length;
    final shape = model.collectionShapeOf(c);

    final groups = c.groups;
    final labels = [for (final (h, list) in groups) h == null ? 'Videos' : model.groupLabel(c, h, list)];
    final withNext = next == null ? 0 : groups.indexWhere((g) => g.$2.any((v) => v.id == next.id));
    final group = (_group ?? (withNext < 0 ? 0 : withNext)).clamp(0, groups.isEmpty ? 0 : groups.length - 1);
    final videos = groups.isEmpty ? const <VideoItem>[] : groups[group].$2;

    final play = next == null
        ? null
        : TvButton(
            key: const ValueKey('tv-page-play'),
            label: nextStarted
                ? 'Continue ${next.episodeLabel ?? ''}'.trim()
                : (watched == 0 ? 'Play' : 'Play ${next.episodeLabel ?? next.title}'),
            icon: Icons.play_arrow,
            primary: true,
            onPressed: () => nav.openVideo(next),
          );

    return TvDetailPage<VideoItem>(
      itemHeight: 66,
      header: TvDetailHeader(
        picture: tvFilePicture(model.coverFile(c), Icons.video_library_outlined),
        pictureWidth: shape == PictureShape.wide ? 240 : 130,
        aspectRatio: shape.aspect,
        kind: c.category ?? 'Collection',
        title: c.name,
        lines: [
          [if (c.year != null) '${c.year}', ?c.genre].join(' · '),
          [
            '${c.main.length} video${c.main.length == 1 ? '' : 's'}',
            if (extras > 0) '$extras extra${extras == 1 ? '' : 's'}',
            if (c.totalDuration > Duration.zero) collectionLength(c.totalDuration),
            if (c.main.length > 1) '$watched watched',
          ].join(' · '),
        ],
        buttons: [
          ?play,
          TvIconButton(
            icon: fav ? Icons.favorite : Icons.favorite_border,
            label: fav ? 'Remove from favourites' : 'Add to favourites',
            on: fav,
            onPressed: () => model.setFavourite(c, !fav),
          ),
          TvIconButton(
            icon: Icons.more_horiz,
            label: 'More options',
            // With seasons, the one showing can be downloaded or kept offline on its own (0.2.3).
            onPressed: () => showCollectionOptions(context, c,
                onPage: true,
                season: groups.length > 1 && groups[group].$1 != null
                    ? (heading: groups[group].$1!, label: labels[group], videos: videos)
                    : null),
          ),
        ],
        below: c.description == null ? null : TvDescription(c.description!, lines: 2),
        after: groups.length > 1
            ? TvTabBar(labels: labels, selected: group, onSelect: (i) => setState(() => _group = i))
            : null,
      ),
      items: videos,
      itemBuilder: (context, v, i, node) => _EpisodeRow(video: v, node: node, isNext: v.id == next?.id),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  const _EpisodeRow({required this.video, required this.node, required this.isNext});
  final VideoItem video;
  final FocusNode node;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final nav = context.read<AppNav>();
    final place = context.select<VideoLibraryModel, VideoPlace?>((m) => m.placeOf(video.id));
    final watched = place?.watched ?? false;
    final started = place?.inProgress ?? false;
    final label = video.episodeLabel;
    final length = video.duration > Duration.zero ? videoLengthOf(video.duration) : null;
    return TvRow(
      key: ValueKey('tv-episode:${video.id}'),
      focusNode: node,
      height: 66,
      highlight: isNext,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 96,
          height: 54,
          child: Stack(fit: StackFit.expand, children: [
            tvFilePicture(model.thumbFile(video), Icons.movie_outlined),
            if (started)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: place!.progress(video.duration).clamp(0.0, 1.0),
                  minHeight: 3,
                  color: AppColors.accent,
                  backgroundColor: Colors.black54,
                ),
              ),
          ]),
        ),
      ),
      title: label == null ? video.title : '$label · ${video.title}',
      subtitle: [
        ?length,
        if (watched) 'Watched' else if (started) '${(place!.progress(video.duration) * 100).round()}% watched',
      ].join(' · '),
      trailing: watched ? Icon(Icons.check_circle, size: 20, color: AppColors.textDim) : null,
      focusedHint: 'Hold OK for options',
      onPressed: () => nav.openVideo(video),
      onHold: () => showVideoOptions(context, video),
    );
  }
}

/// "42:10" or "1:02:10".
String videoLengthOf(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
