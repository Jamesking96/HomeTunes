import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav.dart';
import '../theme.dart';
import '../../state/player_model.dart';
import '../widgets/artwork.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_tile.dart';

/// Full-screen player.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing playing')));
    }
    final size = MediaQuery.sizeOf(context);
    final artSize = (size.shortestSide - 64).clamp(160.0, 460.0);
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [accent.withValues(alpha: 0.35), AppColors.bg, AppColors.bg],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // Top bar
            Row(children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down, size: 32),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Column(children: [
                  const Text('PLAYING FROM', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: AppColors.textDim)),
                  Text(p.queue.contextLabel ?? 'Your library',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                ]),
              ),
              TrackMenuButton(track: t, closeRouteFirst: true),
            ]),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Artwork(track: t, size: artSize, radius: 8),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                        InkWell(
                          onTap: () {
                            Navigator.of(context).pop();
                            context.read<AppNav>().openArtist(t.albumArtist);
                          },
                          child: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, color: AppColors.textDim)),
                        ),
                      ]),
                    ),
                    const LikeButton(),
                  ]),
                ),
                const SizedBox(height: 8),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SeekBar()),
                const SizedBox(height: 4),
                const TransportControls(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(children: [
                    if (!t.isLocal)
                      const Tooltip(
                        message: 'Streaming from your server',
                        child: Icon(Icons.cloud_outlined, color: AppColors.textDim, size: 20),
                      ),
                    if (p.lastError != null)
                      Expanded(
                        child: Text(p.lastError!,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      )
                    else
                      const Spacer(),
                    IconButton(
                      tooltip: 'Queue',
                      icon: const Icon(Icons.queue_music),
                      onPressed: () => openQueue(context),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
