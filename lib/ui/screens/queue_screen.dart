// The Queue page: the song playing now, then everything waiting to play next.
//
// It's a thin view over PlayerModel's PlayQueue. Dragging a song's handle reorders it
// (moveUpcoming), swiping it left removes it (removeUpcoming) and tapping it jumps there
// (jumpTo). The player then re-syncs what the audio engine has preloaded for gapless playback.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/player_model.dart';
import '../theme.dart';
import '../widgets/artwork.dart';

/// Now playing + up next, with drag to reorder and swipe to remove.
class QueueScreen extends StatelessWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    // "up" is the list after the current song; "base" is the queue position of its first entry,
    // used to turn a row number back into a real queue position.
    final cur = p.current;
    final up = p.queue.upcoming;
    final base = p.queue.position + 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      // Nothing loaded at all: just show a friendly message.
      body: cur == null
          ? Center(child: Text('The queue is empty', style: TextStyle(color: AppColors.textDim)))
          : CustomScrollView(slivers: [
              // 1. The song playing now, in the accent colour.
              const SliverToBoxAdapter(child: _Heading('Now playing')),
              SliverToBoxAdapter(
                child: ListTile(
                  leading: Artwork(track: cur, size: 44),
                  title: Text(cur.title,
                      style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                  subtitle: Text(cur.artist),
                ),
              ),
              // 2. The heading says where the upcoming songs came from (e.g. "Album · …").
              SliverToBoxAdapter(
                child: _Heading(
                  up.isEmpty ? 'Nothing up next' : 'Next from: ${p.queue.contextLabel ?? 'your queue'}',
                ),
              ),
              // 3. The upcoming songs: drag the handle to reorder, swipe left to remove,
              // tap to jump.
              SliverReorderableList(
                itemCount: up.length,
                onReorderItem: p.moveUpcoming,
                itemBuilder: (context, i) {
                  final t = up[i];
                  return Dismissible(
                    // The key includes the position, so the same song queued twice still gets
                    // unique keys.
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
            ]),
    );
  }
}

/// A small bold section heading used on this page.
class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      );
}
