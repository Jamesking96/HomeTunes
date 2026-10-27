// The small mark on a card or row that says where it comes from (0.2.2, step 2 of the Servers &
// Downloads plan): a cloud for something streamed from a server, a cloud with a tick for one
// downloaded onto this device, nothing for your own files. Albums, books and collections can be
// a mix; they show the cloud when anything in them is streamed (and not downloaded).
// The Source filter in every tab's "Show only" sheet uses the same words (state/source_filter.dart).
import 'package:flutter/material.dart';

import '../../state/source_filter.dart';
import '../theme.dart';

/// The mark for something made of [sources] (an album's songs, a collection's videos): null when
/// it's all on this device; downloaded when every server part has a copy here; else streamed.
MediaSource? markFor(Set<MediaSource> sources) {
  final remote = sources.where((s) => s != MediaSource.local).toSet();
  if (remote.isEmpty) return null;
  return remote.contains(MediaSource.streamed) ? MediaSource.streamed : MediaSource.downloaded;
}

IconData sourceIcon(MediaSource s) => switch (s) {
      MediaSource.local => Icons.folder_outlined,
      MediaSource.streamed => Icons.cloud_outlined,
      MediaSource.downloaded => Icons.cloud_done_outlined,
    };

String sourceTooltip(MediaSource s, {bool some = false}) => switch (s) {
      MediaSource.local => 'On this device',
      MediaSource.streamed => some ? 'Some of it streams from a server' : 'Streams from a server',
      MediaSource.downloaded => some ? 'Some of it is downloaded from a server' : 'Downloaded from a server',
    };

/// A round dark mark over a picture (cards).
class SourceBadge extends StatelessWidget {
  final MediaSource source;

  /// Only part of it comes from there (a mixed album or collection), for the tooltip.
  final bool some;
  const SourceBadge(this.source, {super.key, this.some = false});

  /// The badge for something made of [sources], or nothing.
  static Widget? forSources(Set<MediaSource> sources, {Key? key}) {
    final m = markFor(sources);
    if (m == null) return null;
    return SourceBadge(m, key: key, some: sources.contains(MediaSource.local));
  }

  @override
  Widget build(BuildContext context) => Tooltip(
        message: sourceTooltip(source, some: some),
        child: Container(
          key: ValueKey('source-mark-${source.name}'),
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
          child: Icon(sourceIcon(source), size: 14, color: Colors.white, semanticLabel: sourceTooltip(source, some: some)),
        ),
      );
}

/// The small grey mark at the start of a song row's second line.
class SourceInline extends StatelessWidget {
  final MediaSource source;
  const SourceInline(this.source, {super.key});

  @override
  Widget build(BuildContext context) => source == MediaSource.local
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Tooltip(
            message: sourceTooltip(source),
            child: Icon(sourceIcon(source), key: ValueKey('source-mark-${source.name}'), size: 13, color: AppColors.textDim),
          ),
        );
}
