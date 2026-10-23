// The TV's Home screen (0.2.0, step 2 of the TV interface; mockup "Home"): rows of big tiles
// that scroll sideways.
//  * Carry on: audiobooks and videos you're part-way through (wide cards with how far you
//    are). OK carries on playing; holding OK also offers its page.
//  * Recently played: the albums, playlists and artists you last played music from (Home's
//    "Jump back in" elsewhere). OK opens it; holding OK offers Play and Shuffle.
//  * Your playlists: Shuffle all, Liked Songs and your playlists.
//  * Then, when there are any: recently added albums, audiobooks and video collections.
// Rows with nothing in them aren't shown. With nothing anywhere it offers to add folders.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/play_history.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/jump_back_in.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

class TvHomeScreen extends StatelessWidget {
  const TvHomeScreen({super.key});

  static const tile = 124.0;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final pl = context.watch<PlaylistsModel>();
    final listening = context.watch<ListeningModel>();
    final history = Provider.of<PlayHistory?>(context);
    final videos = Provider.of<VideoLibraryModel?>(context);
    final nav = context.read<AppNav>();
    final player = context.read<PlayerModel>();
    final hasVideos = videos != null && videos.videos.isNotEmpty;

    Widget page(Widget body) => TvPageHints(
          tab: 0,
          hints: TvHints.browsing,
          child: Material(color: AppColors.bg, child: body),
        );

    if (lib.tracks.isEmpty && lib.books.isEmpty && !hasVideos) {
      final busy = lib.busy || (videos?.busy ?? false);
      return page(TvEmpty(
        icon: Icons.library_music_outlined,
        title: busy ? 'Looking through your folders…' : 'Nothing here yet',
        message: busy ? null : 'Choose the folders your music, audiobooks and videos are in (a USB drive works), or connect a server.',
        action: busy
            ? null
            : Row(mainAxisSize: MainAxisSize.min, children: [
                TvButton(
                  label: 'Add music',
                  icon: Icons.folder_open,
                  primary: true,
                  onPressed: () => nav.openSettings('library', setting: 'music-folders'),
                ),
                if (videos != null) ...[
                  const SizedBox(width: 12),
                  TvButton(
                    label: 'Add videos',
                    icon: Icons.video_library_outlined,
                    onPressed: () => nav.openSettings('library', setting: 'library-video-folders'),
                  ),
                ],
              ]),
      ));
    }

    final jumps = jumpsFrom(lib: lib, listening: listening, playlists: pl, history: history, videos: videos, max: 24);
    final carryOn = [for (final j in jumps) if (j is! MusicJump) j];
    final played = [for (final j in jumps) if (j is MusicJump) j];
    final recentAlbums = lib.albumsByNewest.take(15).toList();
    final recentBooks = ([...lib.books]..sort((a, b) => b.addedMs.compareTo(a.addedMs))).take(15).toList();
    final recentCollections = videos == null
        ? const []
        : ([...videos.collections]..sort((a, b) => b.addedMs.compareTo(a.addedMs))).take(15).toList();
    final bookAspect = tvBookAspect(context);

    final rows = <Widget>[
      if (carryOn.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-carry-on'),
          title: 'Carry on',
          gap: 16,
          children: [for (final j in carryOn) _CarryOnCard(jump: j)],
        ),
      if (played.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-recent'),
          title: 'Recently played',
          children: [for (final j in played) _playedTile(context, j)],
        ),
      if (lib.tracks.isNotEmpty || pl.playlists.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-playlists'),
          title: 'Your playlists',
          children: [
            if (lib.tracks.isNotEmpty)
              TvTile(
                key: const ValueKey('tv-shuffle-all'),
                width: tile,
                picture: TvColourPicture(colour: AppColors.surfaceHigh, icon: Icons.shuffle),
                title: 'Shuffle all',
                subtitle: '${lib.tracks.length} songs',
                onPressed: () => player.shufflePlay(lib.tracks, label: 'All songs'),
              ),
            if (pl.liked.isNotEmpty) tvLikedTile(context, width: tile),
            for (final p in pl.playlists) tvPlaylistTile(context, p, width: tile),
          ],
        ),
      if (recentAlbums.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-new-albums'),
          title: 'Recently added music',
          children: [for (final a in recentAlbums) tvAlbumTile(context, a, width: tile)],
        ),
      if (recentBooks.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-new-books'),
          title: 'Recently added audiobooks',
          children: [for (final b in recentBooks) tvBookTile(context, b, width: math.min(tile, tile * bookAspect * 1.2), aspectRatio: bookAspect)],
        ),
      if (recentCollections.isNotEmpty)
        TvShelf(
          key: const ValueKey('tv-home-new-videos'),
          title: 'Recently added videos',
          children: [
            for (final c in recentCollections)
              tvCollectionTile(context, c, width: 180, aspectRatio: lib.settings.video.collectionPictureShape.aspect >= 1 ? 16 / 9 : null),
          ],
        ),
    ];

    return page(SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin, TvStyle.topMargin, 0, 64),
      clipBehavior: Clip.none,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Home', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: Colors.white)),
        const SizedBox(height: 14),
        for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 8), child: r),
      ]),
    ));
  }

  /// A tile for music played lately: an album, a playlist, Liked Songs or an artist.
  Widget _playedTile(BuildContext context, MusicJump j) {
    final player = context.read<PlayerModel>();
    final item = j.item;
    final album = j.album;
    switch (item.kind) {
      case PlayedKind.album when album != null:
        return tvAlbumTile(context, album, width: tile);
      case PlayedKind.liked:
        return tvLikedTile(context, width: tile);
      case PlayedKind.playlist:
        final p = context.read<PlaylistsModel>().playlists.where((x) => x.name == item.key).firstOrNull;
        if (p != null) return tvPlaylistTile(context, p, width: tile);
      case PlayedKind.artist:
        final a = context.read<LibraryModel>().artists.where((x) => x.name == item.key).firstOrNull;
        if (a != null) return tvArtistTile(context, a, width: tile);
      default:
    }
    // Anything else: a plain tile that plays its songs.
    return TvTile(
      width: tile,
      picture: ArtworkFill(track: j.tracks.first, radius: 0),
      title: item.title,
      onPressed: () => player.playTracks(j.tracks, label: item.title),
      onHold: () => showTvOptions(context, title: item.title, options: [
        TvOption('Play', Icons.play_arrow, () => player.playTracks(j.tracks, label: item.title)),
        TvOption('Shuffle', Icons.shuffle, () => player.shufflePlay(j.tracks, label: item.title)),
      ]),
    );
  }
}

/// A wide "Carry on" card: the picture, the title, what it is and how much is left, and a bar
/// showing how far through you are. OK carries on.
class _CarryOnCard extends StatelessWidget {
  const _CarryOnCard({required this.jump});
  final Jump jump;

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNav>();
    final player = context.read<PlayerModel>();
    late final String title, detail;
    late final double progress;
    late final Widget picture;
    late final VoidCallback carryOn, open;
    late final String openLabel;
    late final Object id;
    switch (jump) {
      case VideoJump(:final video, progress: final p):
        final videos = context.read<VideoLibraryModel>();
        final left = video.duration * (1 - p.clamp(0.0, 1.0));
        title = video.collection == video.title ? video.title : '${video.collection}${video.episodeLabel == null ? '' : ' · ${video.episodeLabel}'}';
        detail = ['Video', if (video.collection != video.title) video.title, if (video.duration > Duration.zero) '${_left(left)} left'].join(' · ');
        progress = p;
        picture = SizedBox(width: 142, height: 80, child: tvFilePicture(videos.thumbFile(video), Icons.movie_outlined));
        carryOn = () => nav.openVideo(video);
        open = () => nav.openVideoCollection(video.collection);
        openLabel = 'Go to the collection';
        id = 'video:${video.id}';
      case BookJump(:final book, progress: final p):
        final left = context.read<ListeningModel>().timeLeft(book);
        title = book.title;
        detail = ['Audiobook', book.author, if (left > Duration.zero) '${_left(left)} left'].join(' · ');
        progress = p;
        picture = SizedBox(width: 80, height: 80, child: ArtworkFill(track: book.artTrack, radius: 0, placeholder: Icons.menu_book));
        carryOn = () => player.playBook(book);
        open = () => nav.openBook(book);
        openLabel = 'Open the book';
        id = 'book:${book.id}';
      case MusicJump():
        return const SizedBox.shrink();
    }
    return TvPressable(
      key: ValueKey('tv-carry-on:$id'),
      semanticLabel: '$title, $detail',
      onPressed: carryOn,
      onHold: () => showTvOptions(context, title: title, subtitle: detail, options: [
        TvOption('Carry on', Icons.play_arrow, carryOn),
        TvOption(openLabel, Icons.open_in_new, open),
      ]),
      builder: (context, focused) => TvFocusFrame(
        focused: focused,
        radius: 14,
        child: AnimatedContainer(
          duration: TvStyle.animation,
          width: 320,
          height: 104,
          color: focused ? AppColors.surfaceHigh : AppColors.surface,
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(10), child: picture),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 4),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: AppColors.textDim)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 4,
                    color: AppColors.accent,
                    backgroundColor: const Color(0xFF4A4E57),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// "2 h 14 m" or "18 min".
  static String _left(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h > 0 ? '$h h $m m' : '${math.max(1, m)} min';
  }
}

