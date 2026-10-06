// Special seasons (0.1.66, the user's request: "allow for the marking of seasons to be special
// with their own titles the user can customise and apply").
//
// * Right-click (or press and hold) a season's heading on a collection's page › Mark as
//   special… : pick a title from the list (Settings › Videos › Special season titles) or type a
//   new one (it's added to the list). The season is then listed under that title with a
//   "Special" badge, after the normal seasons, and Up next / playing on don't run into it.
// * The same menu on a special season › Not special any more.
// The marks are kept by VideoLibraryModel (videos.json, specialSeasons); the list of titles by
// LibraryModel (settings.json, specialSeasonTitles).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/library_model.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';
import '../widgets/track_tile.dart' show askForName;

/// Asks for a special title for season [season] (or [season].[sub]) of [c] and marks it.
Future<void> showSpecialSeasonDialog(BuildContext context, VideoCollection c, int season, [int? sub]) async {
  final videos = context.read<VideoLibraryModel>();
  final lib = context.read<LibraryModel>();
  final title = await showDialog<String>(
    context: context,
    builder: (_) => _SpecialSeasonDialog(
      season: seasonText(season, sub),
      titles: lib.specialSeasonTitles,
      current: videos.specialTitleOf(c, season, sub),
    ),
  );
  final t = title?.trim();
  if (t == null || t.isEmpty) return;
  final isNew = !lib.specialSeasonTitles.any((x) => x.toLowerCase() == t.toLowerCase());
  await Future.wait([
    videos.setSpecialSeason(c, season, t, sub: sub),
    // A new title is kept in the list, so it's offered next time.
    if (isNew) lib.addSpecialSeasonTitle(t),
  ]);
}

/// Makes every season in a special group normal again.
Future<void> unmarkSpecialGroup(BuildContext context, VideoCollection c, List<VideoItem> list) async {
  final videos = context.read<VideoLibraryModel>();
  final seasons = {
    for (final v in list)
      if (v.season != null) (v.season!, v.subSeason),
  };
  for (final (season, sub) in seasons) {
    await videos.setSpecialSeason(c, season, null, sub: sub);
  }
}

class _SpecialSeasonDialog extends StatefulWidget {
  /// "3", or "1.2".
  final String season;
  final List<String> titles;
  final String? current;
  const _SpecialSeasonDialog({required this.season, required this.titles, required this.current});

  @override
  State<_SpecialSeasonDialog> createState() => _SpecialSeasonDialogState();
}

class _SpecialSeasonDialogState extends State<_SpecialSeasonDialog> {
  late final controller = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final picked = controller.text.trim().toLowerCase();
    return AlertDialog(
      title: Text('Mark season ${widget.season} as special'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'It\'s listed under this title after the normal seasons, and playing on from the last '
            'episode won\'t run into it.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (widget.titles.isNotEmpty)
            Wrap(spacing: 8, runSpacing: 4, children: [
              for (final t in widget.titles)
                ChoiceChip(
                  key: ValueKey('special-title:$t'),
                  label: Text(t),
                  selected: picked == t.toLowerCase(),
                  onSelected: (_) => setState(() => controller.text = t),
                ),
            ]),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('special-title-field'),
            controller: controller,
            decoration: const InputDecoration(labelText: 'Title', hintText: 'Pick one above or type a new one'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) Navigator.pop(context, v);
            },
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('special-title-save'),
          onPressed: controller.text.trim().isEmpty ? null : () => Navigator.pop(context, controller.text),
          child: const Text('Mark as special'),
        ),
      ],
    );
  }
}

/// The small "Special" badge beside a special season's heading.
class SpecialBadge extends StatelessWidget {
  const SpecialBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      key: const ValueKey('special-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: accent),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_awesome, size: 12, color: accent),
        const SizedBox(width: 3),
        Text('Special', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
      ]),
    );
  }
}

/// Settings › Videos › Special season titles: the list offered by Mark as special…; remove one
/// with its ✕, add with Add, Reset brings back the starting list.
class SpecialSeasonTitlesSection extends StatelessWidget {
  const SpecialSeasonTitlesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final titles = lib.specialSeasonTitles;
    final isDefault = titles.length == LibraryModel.defaultSpecialSeasonTitles.length &&
        [for (var i = 0; i < titles.length; i++) titles[i] == LibraryModel.defaultSpecialSeasonTitles[i]]
            .every((x) => x);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, 2),
        child: Text('Special season titles', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(
          'Offered when you right-click a season\'s heading and choose Mark as special… (e.g. OVA, Movies). '
          'Special seasons are listed after the normal ones and Up next skips them.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 4, children: [
          for (final t in titles)
            InputChip(
              key: ValueKey('special-title-chip:$t'),
              label: Text(t),
              onDeleted: () => lib.setSpecialSeasonTitles([for (final x in titles) if (x != t) x]),
            ),
          ActionChip(
            key: const ValueKey('special-title-add'),
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Add'),
            onPressed: () async {
              final name = await askForName(context, title: 'Special season title');
              if (name != null) await lib.addSpecialSeasonTitle(name);
            },
          ),
          if (!isDefault)
            TextButton(
              onPressed: () => lib.setSpecialSeasonTitles(List.of(LibraryModel.defaultSpecialSeasonTitles)),
              child: const Text('Reset'),
            ),
        ]),
      ),
    ]);
  }
}
