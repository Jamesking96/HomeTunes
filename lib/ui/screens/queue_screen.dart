// The queue: the song playing now, then everything waiting to play next.
//
// Since 0.1.26 it opens as a drawer that slides in from the right over whatever you're looking
// at (the user asked for this on 29 Sep), on the PC and the phone alike, instead of a page of
// its own. Tap outside it, swipe it back to the right, press Esc or use its close button to put
// it away. [openQueueDrawer] shows it; [QueuePanel] is the drawer itself.
//
// It's a thin view over PlayerModel's PlayQueue. Dragging a song's handle reorders it
// (moveUpcoming), swiping it left removes it (removeUpcoming) and tapping it jumps there
// (jumpTo). The player then re-syncs what the audio engine has preloaded for gapless playback.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/player_model.dart';
import '../theme.dart';
import '../widgets/artwork.dart';

/// Slides the queue drawer in from the right, over everything (the player bar and Now Playing
/// included). It takes up to 420 px, or most of a phone's width.
Future<void> openQueueDrawer(BuildContext context) => showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Close the queue',
      barrierColor: Colors.black38,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => const Align(alignment: Alignment.centerRight, child: QueuePanel()),
      transitionBuilder: (context, anim, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    );

/// The queue drawer: a panel down the right-hand side.
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});

  /// How wide the drawer is: at most 420 px, and never more than 88% of the window.
  static double widthFor(double screenWidth) => screenWidth * 0.88 < 420 ? screenWidth * 0.88 : 420;

  @override
  Widget build(BuildContext context) {
    final width = widthFor(MediaQuery.sizeOf(context).width);
    void close() => Navigator.of(context).maybePop();
    return GestureDetector(
      // A quick swipe to the right puts the drawer away.
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) > 300) close();
      },
      child: Material(
        key: const ValueKey('queue-drawer'),
        color: AppColors.surface,
        elevation: 12,
        borderRadius: BorderRadius.horizontal(left: AppShape.radius(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: double.infinity,
          child: SafeArea(
            left: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                child: Row(children: [
                  const Expanded(child: Text('Queue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                  IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: close),
                ]),
              ),
              const Expanded(child: QueueList()),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Now playing + up next, with drag to reorder and swipe to remove.
class QueueList extends StatelessWidget {
  const QueueList({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    // "up" is the list after the current song; "base" is the queue position of its first entry,
    // used to turn a row number back into a real queue position.
    final cur = p.current;
    // Nothing loaded at all: just show a friendly message.
    if (cur == null) {
      return Center(child: Text('The queue is empty', style: TextStyle(color: AppColors.textDim)));
    }
    final up = p.queue.upcoming;
    final base = p.queue.position + 1;
    return CustomScrollView(slivers: [
      // 1. The song playing now, in the accent colour.
      const SliverToBoxAdapter(child: _Heading('Now playing')),
      SliverToBoxAdapter(
        child: ListTile(
          leading: Artwork(track: cur, size: 44),
          title: Text(cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
          subtitle: Text(cur.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
      // 2. The heading says where the upcoming songs came from (e.g. "Album · …").
      SliverToBoxAdapter(
        child: _Heading(
          up.isEmpty ? 'Nothing up next' : 'Next from: ${p.queue.contextLabel ?? 'your queue'}',
        ),
      ),
      // 3. The upcoming songs: drag the handle to reorder, swipe left to remove, tap to jump.
      SliverReorderableList(
        itemCount: up.length,
        onReorderItem: p.moveUpcoming,
        itemBuilder: (context, i) {
          final t = up[i];
          return Dismissible(
            // The key includes the position, so the same song queued twice still gets unique keys.
            key: ValueKey('${t.id}@${base + i}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: Colors.red.shade900,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              child: const Icon(Icons.delete_outline),
            ),
            onDismissed: (_) => p.removeUpcoming(i),
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                leading: Artwork(track: t, size: 44),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => p.jumpTo(base + i),
                trailing: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_handle)),
              ),
            ),
          );
        },
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
    ]);
  }
}

/// A small bold section heading used in the queue.
class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}
