import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nav.dart';
import '../theme.dart';
import '../../state/player_model.dart';
import '../widgets/artwork.dart';
import '../widgets/bookmark_widgets.dart';
import '../widgets/listening_controls.dart';
import '../widgets/lyrics_view.dart';
import '../widgets/player_controls.dart';
import '../widgets/track_tile.dart';

/// Full-screen player. For songs, the lyrics can be shown in place of the
/// cover (phones) or beside it (wide windows).
class NowPlayingScreen extends StatefulWidget {
  /// Open with the lyrics showing (otherwise as they were last time).
  final bool? showLyrics;
  const NowPlayingScreen({super.key, this.showLyrics});

  /// Whether lyrics were showing when Now Playing was last closed.
  static bool lyricsWereOpen = false;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  late bool _lyrics = widget.showLyrics ?? NowPlayingScreen.lyricsWereOpen;

  void _toggleLyrics() {
    setState(() => _lyrics = !_lyrics);
    NowPlayingScreen.lyricsWereOpen = _lyrics;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    final t = p.current;
    final book = p.book;
    if (t == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: Text('Nothing playing')));
    }
    final size = MediaQuery.sizeOf(context);
    final artSize = (size.shortestSide - 64).clamp(160.0, 460.0);
    final accent = Theme.of(context).colorScheme.primary;
    final lyrics = _lyrics && book == null;
    final wide = size.width >= 900;
    final lyricsPanel = LyricsView(key: ValueKey(t.id), track: t);

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
          child: Row(children: [
            Expanded(child: Column(children: [
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
                if (book != null)
                  IconButton(
                    tooltip: 'Go to book',
                    icon: const Icon(Icons.menu_book_outlined),
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.read<AppNav>().openBook(book);
                    },
                  )
                else
                  TrackMenuButton(track: t, closeRouteFirst: true),
              ]),
              Expanded(
                child: lyrics && !wide
                    ? lyricsPanel
                    : Center(
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
                          if (book != null)
                            const _ChapterTitle()
                          else
                            Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                          InkWell(
                            onTap: () {
                              Navigator.of(context).pop();
                              if (book != null) {
                                context.read<AppNav>().openBook(book);
                              } else {
                                context.read<AppNav>().openArtist(t.albumArtist);
                              }
                            },
                            child: Text(book != null ? '${book.title} · ${book.author}' : t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, color: AppColors.textDim)),
                          ),
                        ]),
                      ),
                      if (book == null)
                        const LikeButton()
                      else
                        IconButton(
                          tooltip: 'Bookmark this spot',
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: () => addBookmarkNow(context),
                        ),
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
                      if (book != null) ...[
                        const SpeedButton(),
                        IconButton(
                          tooltip: 'Chapters',
                          icon: const Icon(Icons.format_list_bulleted),
                          onPressed: () => showChaptersSheet(context),
                        ),
                        IconButton(
                          tooltip: 'Bookmarks',
                          icon: const Icon(Icons.bookmarks_outlined),
                          onPressed: () => showBookmarksSheet(context),
                        ),
                      ],
                      if (book != null && p.hasWaitingMusic)
                        TextButton.icon(
                          icon: const Icon(Icons.library_music_outlined, size: 18),
                          label: const Text('Back to music'),
                          onPressed: p.resumeMusic,
                        ),
                      if (book == null)
                        IconButton(
                          tooltip: lyrics ? 'Hide lyrics' : 'Lyrics',
                          icon: Icon(Icons.lyrics_outlined, color: lyrics ? accent : null),
                          onPressed: _toggleLyrics,
                        ),
                      // A book's "queue" is its files; the chapter list covers that.
                      if (book == null)
                        IconButton(
                          tooltip: 'Queue',
                          icon: const Icon(Icons.queue_music),
                          onPressed: () => openQueue(context),
                        ),
                    ]),
                  ),
                ]),
              ),
            ])),
            if (lyrics && wide)
              Container(
                width: (size.width * 0.42).clamp(360.0, 620.0),
                margin: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: lyricsPanel,
              ),
          ]),
        ),
      ),
    );
  }
}

/// The chapter being listened to, kept up to date as the book plays.
class _ChapterTitle extends StatelessWidget {
  const _ChapterTitle();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerModel>();
    return StreamBuilder<Duration>(
      stream: p.positionStream,
      builder: (context, _) {
        final title = p.currentChapter?.title ?? p.current?.title ?? '';
        return Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800));
      },
    );
  }
}
