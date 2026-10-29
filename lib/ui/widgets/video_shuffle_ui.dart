// Shuffle for video collections (0.2.6; state/video_shuffle.dart has how it works): starting a
// shuffle, and on PC and phone the "Seasons in the shuffle" box. The TV has its own panels
// (tv/tv_menus.dart's tvShuffleOptions).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../../state/video_shuffle.dart';
import '../nav.dart';

/// Plays [c] shuffled: season [heading] alone, else the seasons in its shuffle. When there's
/// nothing to shuffle (every season taken out) [onEmpty] is told, else a snack bar says so.
/// Returns whether it started.
bool playShuffled(BuildContext context, VideoCollection c, {String? heading, void Function(String message)? onEmpty}) {
  final model = context.read<VideoLibraryModel>();
  final shuffle = model.shuffleOf(c, heading: heading);
  final first = shuffle == null ? null : model.byId(shuffle.first);
  if (shuffle == null || first == null) {
    const message = 'Nothing to shuffle: every season is out of the shuffle. Put some back in with "Seasons in the shuffle".';
    if (onEmpty != null) {
      onEmpty(message);
    } else {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text(message)));
    }
    return false;
  }
  context.read<AppNav>().openVideo(first, shuffle: shuffle);
  return true;
}

/// Whether [c] has more than one heading, so seasons can be put in or taken out of its shuffle.
bool hasShuffleSeasons(VideoCollection c) => c.groups.length > 1;

/// "Seasons in the shuffle": a tick per season / part / Specials / Extras, kept for the
/// collection; Shuffle now starts one with them.
Future<void> showShuffleSeasons(BuildContext context, VideoCollection c) => showDialog<void>(
      context: context,
      builder: (_) => _ShuffleSeasonsDialog(name: c.name, onShuffle: (c) => playShuffled(context, c)),
    );

class _ShuffleSeasonsDialog extends StatelessWidget {
  const _ShuffleSeasonsDialog({required this.name, required this.onShuffle});
  final String name;
  final void Function(VideoCollection c) onShuffle;

  @override
  Widget build(BuildContext context) {
    final model = context.watch<VideoLibraryModel>();
    final c = model.collectionNamed(name);
    if (c == null) return const AlertDialog(content: Text('This collection isn\'t in your videos any more.'));
    final groups = model.shuffleGroups(c);
    final count = groups.where((g) => g.included).fold<int>(0, (n, g) => n + g.videos.length);
    final usual = groups.every((g) => g.included == shuffledByDefault(g.heading, g.videos));
    return AlertDialog(
      title: const Text('Seasons in the shuffle'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Shuffle on ${c.name}\'s page plays these, in a random order. Kept for this collection; '
              'Shuffle on a season\'s heading plays just that season.'),
          const SizedBox(height: 8),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final g in groups)
                if (g.heading != null)
                  CheckboxListTile(
                    key: ValueKey('shuffle-season:${g.heading}'),
                    value: g.included,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(g.label),
                    subtitle: Text('${g.videos.length} video${g.videos.length == 1 ? '' : 's'}'),
                    onChanged: (on) => model.setInShuffle(c, g.heading!, on ?? false),
                  ),
            ]),
          ),
          const SizedBox(height: 4),
          Text(count == 0 ? 'Nothing is in the shuffle.' : '$count video${count == 1 ? '' : 's'} in the shuffle',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        if (!usual) TextButton(onPressed: () => model.resetShuffle(c), child: const Text('Back to the usual')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton.icon(
          key: const ValueKey('shuffle-now'),
          icon: const Icon(Icons.shuffle),
          label: const Text('Shuffle now'),
          onPressed: count == 0
              ? null
              : () {
                  Navigator.of(context).pop();
                  onShuffle(c);
                },
        ),
      ],
    );
  }
}
