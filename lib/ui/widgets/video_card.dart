// A video as a card (VideoCard: its picture, title, length, how far in, watched) and its menu
// (showVideoMenu), plus the card grid's sizes. Used by the Videos tab, Home and a collection's
// page. Split out of screens/videos_screen.dart in refactor phase 6 (9 Oct 2026), unchanged.
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import '../../models/video_item.dart';
import '../../state/range_select.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'quick_links.dart';
import '../screens/edit_video.dart';
import '../screens/video_details_screen.dart' show openVideoDetails;
import '../screens/video_pictures.dart';
import 'selectable_title.dart';

/// How tall a video card is at [width]: its picture (16:9 unless [shape] says otherwise) plus
/// two lines of text.
double videoCardHeight(double width, [PictureShape shape = PictureShape.wide]) => (width - 16) / shape.aspect + 16 + 64;

/// Cards in rows of [cols], each row as tall as its tallest card (videos and collections can
/// each have their own picture shape, so a plain grid's equal cells won't do).
/// [after] can put something under a row (an open collection's contents, like an album's songs
/// on an artist page).
Widget sliverCardRows<T>({
  required List<T> items,
  required int cols,
  required double Function(T) height,
  required Widget Function(T) card,
  Widget? Function(List<T> row)? after,
}) =>
    SliverList.builder(
      itemCount: (items.length / cols).ceil(),
      itemBuilder: (_, r) {
        final row = items.skip(r * cols).take(cols).toList();
        final cards = SizedBox(
          height: row.map(height).reduce(math.max),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final x in row) Expanded(child: card(x)),
            for (var i = row.length; i < cols; i++) const Expanded(child: SizedBox()),
          ]),
        );
        final below = after?.call(row);
        return below == null ? cards : Column(mainAxisSize: MainAxisSize.min, children: [cards, below]);
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
  /// Ticks or unticks it; null where selecting isn't offered (Search).
  final VoidCallback? onSelect;
  const VideoCard({super.key, required this.video, this.selected = false, this.selecting = false, this.onSelect});

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
          // Selecting: a tap ticks / unticks (Shift + click: a range, 0.1.47); Shift + click when
          // nothing is ticked starts selecting.
          onTap: () {
            if (onSelect != null && (selecting || shiftHeld)) {
              onSelect!();
            } else {
              context.read<AppNav>().openVideo(video);
            }
          },
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
  final link = QuickLink(QuickLinkKind.video, video.id, video.title);
  final linked = model.library.isQuickLink(link.kind, link.id);
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
      // A quick link in the sidebar (0.1.64).
      PopupMenuItem(
          value: 'link',
          child: ListTile(leading: Icon(quickLinkMenuIcon(linked)), title: Text(quickLinkMenuText(linked)))),
      copyTitleMenuItem('copy'),
      // Where it comes from, and what's inside the file (0.1.44).
      const PopupMenuItem(value: 'details', child: ListTile(leading: Icon(Icons.info_outline), title: Text('Details…'))),
      if (Platform.isWindows)
        const PopupMenuItem(value: 'folder', child: ListTile(leading: Icon(Icons.folder_open), title: Text('Show in folder'))),
      if (onSelect != null)
        const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.check_box_outlined), title: Text('Select'))),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case 'copy':
      await copyTitle(context, video.title);
    case 'details':
      await openVideoDetails(context, video);
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
    case 'link':
      await model.library.toggleQuickLink(link);
    case 'folder':
      final file = model.playableFile(video);
      if (file != null) await Process.run('explorer', ['/select,', p.normalize(file)]);
    case 'select':
      onSelect?.call();
  }
}
