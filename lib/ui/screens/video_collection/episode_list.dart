// A collection's episodes: the rows (EpisodeRow), the season / group headings, and select mode
// (_EpisodeSelection, shared by the page and the contents panel). Part of
// video_collection_screen.dart (refactor phase 6, 9 Oct 2026: moved here unchanged).
part of '../video_collection_screen.dart';

/// Ticking videos in a collection's list (its page and its in-place contents): right-click ›
/// Select starts it, each season's heading gets a box for the whole season, and a
/// [VideoSelectionBar] offers Edit details (one or several), Select all and watched / not watched.
mixin _EpisodeSelection<T extends StatefulWidget> on State<T> {
  final Set<String> selectedVideos = {};

  bool get selectingVideos => selectedVideos.isNotEmpty;

  final _range = RangePicker();

  /// Ticks or unticks one video; with Shift held, ticks everything between the last one clicked
  /// and this one, in the list's order ([order] is only worked out at tap time).
  void toggleVideo(String id, List<String> Function() order) =>
      setState(() => _range.pick(selectedVideos, id, order()));

  /// true when all of [list] is ticked, false when none, null when some.
  bool? seasonTicked(List<VideoItem> list) {
    final n = list.where((v) => selectedVideos.contains(v.id)).length;
    return n == 0 ? false : (n == list.length ? true : null);
  }

  void tickSeason(List<VideoItem> list) => setState(() {
        if (seasonTicked(list) == true) {
          selectedVideos.removeAll([for (final v in list) v.id]);
        } else {
          selectedVideos.addAll([for (final v in list) v.id]);
        }
      });

  /// A season heading's right-click menu: Select all in the season (starts select mode with the
  /// season ticked), unselect it, watched / not watched, Season title… and fold / open.
  void headingMenu(Offset at, VideoCollection c, String heading, List<VideoItem> list,
      {required bool folded, required VoidCallback onFold}) {
    final s = seasonOfGroup(heading, list);
    final special = VideoLibraryModel.isSpecialGroup(list);
    showVideoGroupMenu(
      context,
      at: at,
      heading: heading,
      list: list,
      selected: selectedVideos,
      onSelectAll: () => setState(() => selectedVideos.addAll([for (final v in list) v.id])),
      onUnselect: () => setState(() => selectedVideos.removeAll([for (final v in list) v.id])),
      onRename: s == null ? null : () => showSeasonTitleDialog(context, c, s.season, s.sub),
      // Special seasons (0.1.66): mark a numbered season, or make a special one normal again.
      special: special,
      onSpecial: special
          ? () => unmarkSpecialGroup(context, c, list)
          : (s == null ? null : () => showSpecialSeasonDialog(context, c, s.season, s.sub)),
      folded: folded,
      onFold: onFold,
    );
  }

  Widget episodeRow(VideoItem v, VideoItem? next, List<String> Function() order) => EpisodeRow(
        video: v,
        isNext: v.id == next?.id,
        selecting: selectingVideos,
        selected: selectedVideos.contains(v.id),
        onSelect: () => toggleVideo(v.id, order),
      );

  Widget selectionBar(VideoCollection c) => VideoSelectionBar(
        selected: selectedVideos,
        onClear: () => setState(selectedVideos.clear),
        onSelectAll: () => setState(() => selectedVideos.addAll([for (final v in c.videos) v.id])),
      );
}

/// The season a group heading stands for ("Season 2" → 2, "Season 1.2" → 1 and sub 2); null for
/// Specials, named parts, Episodes and Extras (they have no season title).
({int season, int? sub})? seasonOfGroup(String heading, List<VideoItem> list) {
  final v = list.firstOrNull;
  final s = v?.season;
  return v != null && s != null && s > 0 && heading == 'Season ${v.seasonLabel}' ? (season: s, sub: v.subSeason) : null;
}

/// A season's heading: tap to fold it up or open it again.
class _GroupHeading extends StatelessWidget {
  final String heading;

  /// What's shown: the heading with the season's title, if it has one.
  final String? label;
  final int count, watched;
  final bool folded, hasNext;
  final VoidCallback onTap;

  /// Names the season (seasons with a number only).
  final VoidCallback? onRename;

  /// In select mode: a box that ticks or unticks the whole season (true = all ticked,
  /// null = some). [onTick] null hides it.
  final bool? ticked;
  final VoidCallback? onTick;

  /// Right-click (or press and hold): the season's menu, at the pointer.
  final void Function(Offset at)? onMenu;

  /// A season the user marked special (0.1.66): shows the "Special" badge.
  final bool special;
  const _GroupHeading(
      {required this.heading,
      this.special = false,
      required this.count,
      required this.watched,
      required this.folded,
      required this.hasNext,
      required this.onTap,
      this.label,
      this.onRename,
      this.ticked = false,
      this.onTick,
      this.onMenu});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    Offset? pressedAt;
    return SizedBox(
      height: _VideoCollectionScreenState.headingExtent,
      child: GestureDetector(
        onSecondaryTapUp: onMenu == null ? null : (d) => onMenu!(d.globalPosition),
        child: InkWell(
          key: ValueKey('heading-$heading'),
          onTap: onTap,
          onTapDown: (d) => pressedAt = d.globalPosition,
          onLongPress: onMenu == null ? null : () => onMenu!(pressedAt ?? Offset.zero),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              AnimatedRotation(
                turns: folded ? -0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: const Icon(Icons.expand_more),
              ),
              const SizedBox(width: 6),
              if (onTick != null)
                Checkbox(
                  key: ValueKey('season-tick:$heading'),
                  tristate: true,
                  value: ticked,
                  onChanged: (_) => onTick!(),
                ),
              Flexible(
                child: Text('${label ?? heading}  ($count)',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              if (special) ...[
                const SizedBox(width: 8),
                const SpecialBadge(),
              ],
              if (hasNext) ...[
                const SizedBox(width: 8),
                Icon(Icons.play_arrow, size: 18, color: accent),
              ],
              if (onRename != null)
                IconButton(
                  key: ValueKey('season-title:$heading'),
                  tooltip: 'Season title',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.textDim),
                  onPressed: onRename,
                ),
              const Spacer(),
              Text(
                watched == 0 ? '' : (watched == count ? 'All watched' : '$watched of $count watched'),
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// One video in a collection's list: picture, "S1 E4 · Title", length and progress.
/// Right-click (or long-press) › Select starts select mode: then a tap ticks or unticks the row.
class EpisodeRow extends StatelessWidget {
  final VideoItem video;
  final bool isNext;

  /// Select mode is on (some video in this list is ticked), and whether this one is.
  final bool selecting, selected;

  /// Ticks or unticks this video; null where selecting isn't offered.
  final VoidCallback? onSelect;
  const EpisodeRow({
    super.key,
    required this.video,
    this.isNext = false,
    this.selecting = false,
    this.selected = false,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final model = context.read<VideoLibraryModel>();
    final place = context.select<VideoLibraryModel, VideoPlace?>((m) => m.placeOf(video.id));
    final accent = Theme.of(context).colorScheme.primary;
    final label = video.episodeLabel;
    final progress = place?.progress(video.duration) ?? 0;
    void menu(Offset at) => showVideoMenu(context, video, at: at, onSelect: onSelect);
    final ticking = selecting && onSelect != null;
    return GestureDetector(
      onSecondaryTapUp: (d) => menu(d.globalPosition),
      child: InkWell(
        key: ValueKey('episode-row:${video.id}'),
        onTap: () {
          // Checked at tap time: Shift + click ticks a range even before select mode is on.
          if (onSelect != null && (selecting || shiftHeld)) {
            onSelect!();
          } else {
            context.read<AppNav>().openVideo(video);
          }
        },
        onLongPress: ticking
            ? onSelect
            : () {
                final box = context.findRenderObject() as RenderBox;
                menu(box.localToGlobal(box.size.center(Offset.zero)));
              },
        child: Container(
          color: selected ? accent.withValues(alpha: 0.18) : (isNext ? accent.withValues(alpha: 0.08) : null),
          padding: EdgeInsets.fromLTRB(ticking ? 4 : 16, 6, 16, 6),
          child: Row(children: [
            if (ticking)
              Checkbox(
                key: ValueKey('episode-tick:${video.id}'),
                value: selected,
                onChanged: (_) => onSelect!(),
              ),
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

/// A picture from disk, or a placeholder.
class _Picture extends StatelessWidget {
  final String? file;
  final IconData icon;
  const _Picture({required this.file, this.icon = Icons.video_library_outlined});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.surface,
        child: file != null
            ? Image.file(File(file!), fit: BoxFit.cover, cacheWidth: 640,
                errorBuilder: (_, _, _) => Center(child: Icon(icon, size: 40, color: AppColors.textDim)))
            : Center(child: Icon(icon, size: 40, color: AppColors.textDim)),
      );
}
