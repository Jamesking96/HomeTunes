// The TV's tiles and rows for each kind of thing (0.2.0, step 2 of the TV interface): albums,
// artists, songs, playlists, audiobooks, series, video collections and videos. Home and the
// library screens all use these, so an album looks and behaves the same everywhere.
//
// OK opens the thing (its page; the pages get their TV versions in step 3) or, for a song,
// plays it. Holding OK opens the options panel with what can be done with it; step 4 moves
// every menu there in full, these are the everyday ones.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/video_item.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/book_card.dart' show BookCover, bookCoverRatio;
import '../widgets/playlist_art.dart';
import '../widgets/series_card.dart' show SeriesCover, seriesProgress;
import 'tv_browse.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

String _count(int n, String one) => '$n $one${n == 1 ? '' : 's'}';

/// A picture from a file (a video thumbnail or poster), or a dark box with [icon].
Widget tvFilePicture(String? file, IconData icon) {
  final none = ColoredBox(color: const Color(0xFF1A1C21), child: Center(child: Icon(icon, size: 32, color: AppColors.textDim)));
  if (file == null) return none;
  return Image.file(File(file), fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => none);
}

// ---- Albums ----

TvTile tvAlbumTile(BuildContext context, Album a, {FocusNode? node, double width = 124}) {
  final nav = context.read<AppNav>();
  return TvTile(
    key: ValueKey('tv-album:${a.key}'),
    focusNode: node,
    width: width,
    picture: ArtworkFill(track: a.artTrack, radius: 0),
    title: a.title,
    subtitle: a.artist,
    onPressed: () => nav.openAlbum(a),
    onHold: () => showAlbumOptions(context, a),
  );
}

Future<void> showAlbumOptions(BuildContext context, Album a) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final nav = context.read<AppNav>();
  final fav = pl.isFavouriteAlbum(a);
  return showTvOptions(
    context,
    title: a.title,
    subtitle: a.artist,
    picture: Artwork(track: a.artTrack, size: 56, radius: 8),
    options: [
      TvOption('Play', Icons.play_arrow, () => player.playTracks(a.tracks, label: 'Album · ${a.title}')),
      TvOption('Shuffle', Icons.shuffle, () => player.shufflePlay(a.tracks, label: 'Album · ${a.title}')),
      TvOption('Open the album', Icons.album_outlined, () => nav.openAlbum(a)),
      TvOption('Go to the artist', Icons.person_outline, () => nav.openArtist(a.artist)),
      TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
          () => pl.setFavouriteAlbums([a], !fav)),
    ],
  );
}

// ---- Artists ----

TvTile tvArtistTile(BuildContext context, Artist a, {FocusNode? node, double width = 124}) {
  final nav = context.read<AppNav>();
  final player = context.read<PlayerModel>();
  return TvTile(
    key: ValueKey('tv-artist:${a.name}'),
    focusNode: node,
    width: width,
    pictureRadius: width,
    picture: LayoutBuilder(builder: (context, c) => Artwork(artist: a, size: c.maxWidth, radius: 0, placeholder: Icons.person)),
    title: a.name,
    subtitle: '${_count(a.albums.length, 'album')} · ${_count(a.tracks.length, 'song')}',
    onPressed: () => nav.openArtist(a.name),
    onHold: () => showTvOptions(
      context,
      title: a.name,
      subtitle: '${_count(a.albums.length, 'album')} · ${_count(a.tracks.length, 'song')}',
      options: [
        TvOption('Play', Icons.play_arrow, () => player.playTracks(a.tracks, label: 'Artist · ${a.name}')),
        TvOption('Shuffle', Icons.shuffle, () => player.shufflePlay(a.tracks, label: 'Artist · ${a.name}')),
        TvOption('Open the artist', Icons.person_outline, () => nav.openArtist(a.name)),
      ],
    ),
  );
}

// ---- Songs ----

/// One song in a list. OK plays [list] from this song.
TvRow tvSongRow(BuildContext context, Track t,
    {required List<Track> list, required int index, required String label, FocusNode? node, bool showAlbum = true, List<TvOption> extra = const [], bool highlight = false}) {
  final player = context.read<PlayerModel>();
  return TvRow(
    key: ValueKey('tv-song:${t.id}'),
    focusNode: node,
    height: 52,
    leading: Artwork(track: t, size: 40, radius: 6),
    title: t.title,
    subtitle: showAlbum ? '${t.artist} · ${t.album}' : t.artist,
    trailing: Text(t.hasDuration ? formatDuration(t.duration) : ''),
    highlight: highlight,
    onPressed: () => player.playTracks(list, start: index, label: label),
    onHold: () => showSongOptions(context, t, extra: extra),
  );
}

/// [extra] adds options for where the song is (Remove from this playlist).
Future<void> showSongOptions(BuildContext context, Track t, {List<TvOption> extra = const []}) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final liked = pl.isLiked(t);
  final album = lib.albumByKey(t.albumKey);
  return showTvOptions(
    context,
    title: t.title,
    subtitle: '${t.artist} · ${t.album}',
    picture: Artwork(track: t, size: 56, radius: 8),
    options: [
      TvOption('Play next', Icons.playlist_play, () => player.playNext(t)),
      TvOption('Add to the queue', Icons.queue_music, () => player.addToQueue(t)),
      if (album != null) TvOption('Go to the album', Icons.album_outlined, () => nav.openAlbum(album)),
      TvOption('Go to the artist', Icons.person_outline, () => nav.openArtist(t.albumArtist.isEmpty ? t.artist : t.albumArtist)),
      TvOption(liked ? 'Remove from Liked Songs' : 'Add to Liked Songs', liked ? Icons.favorite : Icons.favorite_border, () => pl.toggleLike(t)),
      ...extra,
    ],
  );
}

// ---- Playlists ----

TvTile tvLikedTile(BuildContext context, {FocusNode? node, double width = 124}) {
  final pl = context.read<PlaylistsModel>();
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final player = context.read<PlayerModel>();
  List<Track> songs() => [for (final id in pl.liked) ?lib.byId(id)];
  return TvTile(
    key: const ValueKey('tv-liked'),
    focusNode: node,
    width: width,
    picture: TvColourPicture(colour: AppColors.accent, icon: Icons.favorite),
    title: 'Liked Songs',
    subtitle: _count(pl.liked.length, 'song'),
    onPressed: nav.openLiked,
    onHold: () => showTvOptions(context, title: 'Liked Songs', subtitle: _count(pl.liked.length, 'song'), options: [
      TvOption('Play', Icons.play_arrow, () => player.playTracks(songs(), label: 'Liked Songs')),
      TvOption('Shuffle', Icons.shuffle, () => player.shufflePlay(songs(), label: 'Liked Songs')),
      TvOption('Open Liked Songs', Icons.favorite_border, nav.openLiked),
    ]),
  );
}

TvTile tvPlaylistTile(BuildContext context, Playlist p, {FocusNode? node, double width = 124}) {
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final player = context.read<PlayerModel>();
  List<Track> songs() => [for (final id in p.trackIds) ?lib.byId(id)];
  return TvTile(
    key: ValueKey('tv-playlist:${p.id}'),
    focusNode: node,
    width: width,
    picture: PlaylistArt(playlist: p, radius: 0),
    title: p.name,
    subtitle: _count(p.trackIds.length, 'song'),
    onPressed: () => nav.openPlaylist(p),
    onHold: () => showTvOptions(context, title: p.name, subtitle: _count(p.trackIds.length, 'song'), options: [
      TvOption('Play', Icons.play_arrow, () => player.playTracks(songs(), label: 'Playlist · ${p.name}')),
      TvOption('Shuffle', Icons.shuffle, () => player.shufflePlay(songs(), label: 'Playlist · ${p.name}')),
      TvOption('Open the playlist', Icons.queue_music, () => nav.openPlaylist(p)),
    ]),
  );
}

// ---- Audiobooks ----

/// The cover shape of books (Settings › Audiobooks: square or tall), as width / height. A
/// screen reads it in its own build (it redraws when the setting changes) and hands it to the
/// tiles, which may be built inside a lazy grid.
double tvBookAspect(BuildContext context) => 1 / bookCoverRatio(context);

TvTile tvBookTile(BuildContext context, Book b, {FocusNode? node, double width = 124, required double aspectRatio}) {
  final nav = context.read<AppNav>();
  final listening = context.read<ListeningModel>();
  final state = listening.stateOf(b);
  final detail = switch (state) {
    BookState.inProgress => '${(listening.fractionDone(b) * 100).round()}% · ${b.author}',
    BookState.finished => 'Finished · ${b.author}',
    BookState.notStarted => b.author,
  };
  return TvTile(
    key: ValueKey('tv-book:${b.id}'),
    focusNode: node,
    width: width,
    aspectRatio: aspectRatio,
    picture: LayoutBuilder(builder: (context, c) => BookCover(book: b, width: c.maxWidth, radius: 0)),
    title: b.title,
    subtitle: detail,
    onPressed: () => nav.openBook(b),
    onHold: () => showBookOptions(context, b),
  );
}

Future<void> showBookOptions(BuildContext context, Book b) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final nav = context.read<AppNav>();
  final state = context.read<ListeningModel>().stateOf(b);
  final fav = pl.isFavouriteBook(b);
  final series = b.series;
  return showTvOptions(
    context,
    title: b.title,
    subtitle: b.author,
    options: [
      TvOption(state == BookState.inProgress ? 'Carry on listening' : 'Play', Icons.play_arrow, () => player.playBook(b)),
      if (state != BookState.notStarted) TvOption('Play from the start', Icons.replay, () => player.playBook(b, fromStart: true)),
      TvOption('Open the book', Icons.menu_book_outlined, () => nav.openBook(b)),
      if (series != null && series.trim().isNotEmpty) TvOption('Go to the series', Icons.collections_bookmark_outlined, () => nav.openSeries(series)),
      TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
          () => pl.setFavouriteBooks([b], !fav)),
    ],
  );
}

TvTile tvSeriesTile(BuildContext context, BookSeries s, {FocusNode? node, double width = 124, required double aspectRatio}) {
  final nav = context.read<AppNav>();
  final pl = context.read<PlaylistsModel>();
  final player = context.read<PlayerModel>();
  final progress = seriesProgress(s, context.read<ListeningModel>());
  final fav = pl.isFavouriteSeries(s.name);
  final detail = '${_count(s.books.length, 'book')}${progress.finished > 0 ? ' · ${progress.finished} finished' : ''}';
  return TvTile(
    key: ValueKey('tv-series:${s.name}'),
    focusNode: node,
    width: width,
    aspectRatio: aspectRatio,
    picture: LayoutBuilder(builder: (context, c) => SeriesCover(series: s, width: c.maxWidth, radius: 0)),
    title: s.name,
    subtitle: detail,
    onPressed: () => nav.openSeries(s.name),
    onHold: () => showTvOptions(context, title: s.name, subtitle: detail, options: [
      TvOption(progress.allFinished ? 'Play the first book' : 'Play ${progress.next.title}', Icons.play_arrow,
          () => player.playBook(progress.next)),
      TvOption('Open the series', Icons.collections_bookmark_outlined, () => nav.openSeries(s.name)),
      TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
          () => pl.setFavouriteSeries([s.name], !fav)),
    ]),
  );
}

// ---- Videos ----

TvTile tvCollectionTile(BuildContext context, VideoCollection c, {FocusNode? node, double width = 150, double? aspectRatio}) {
  final nav = context.read<AppNav>();
  final videos = context.read<VideoLibraryModel>();
  final fav = videos.isFavourite(c);
  final n = c.videos.length;
  final detail = [?c.category, if (n > 1) _count(n, 'video')].join(' · ');
  return TvTile(
    key: ValueKey('tv-collection:${c.name}'),
    focusNode: node,
    width: width,
    aspectRatio: aspectRatio ?? videos.collectionShapeOf(c).aspect,
    picture: tvFilePicture(videos.coverFile(c), Icons.video_library_outlined),
    title: c.name,
    subtitle: detail.isEmpty ? null : detail,
    onPressed: () => nav.openVideoCollection(c.name),
    onHold: () {
      final next = videos.nextUp(c);
      showTvOptions(context, title: c.name, subtitle: detail.isEmpty ? null : detail, options: [
        if (next != null) TvOption('Play ${next.title}', Icons.play_arrow, () => nav.openVideo(next)),
        TvOption('Open the collection', Icons.video_library_outlined, () => nav.openVideoCollection(c.name)),
        TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
            () => videos.setFavourite(c, !fav)),
      ]);
    },
  );
}

TvTile tvVideoTile(BuildContext context, VideoItem v, {FocusNode? node, double width = 180, double? aspectRatio}) {
  final nav = context.read<AppNav>();
  final videos = context.read<VideoLibraryModel>();
  final place = videos.placeOf(v.id);
  final detail = [
    if (v.collection != v.title) v.collection,
    ?v.episodeLabel,
    if (place?.inProgress ?? false) '${(place!.progress(v.duration) * 100).round()}%' else if (place?.watched ?? false) 'Watched',
  ].join(' · ');
  return TvTile(
    key: ValueKey('tv-video:${v.id}'),
    focusNode: node,
    width: width,
    aspectRatio: aspectRatio ?? 16 / 9,
    picture: tvFilePicture(videos.thumbFile(v), Icons.movie_outlined),
    title: v.title,
    subtitle: detail.isEmpty ? null : detail,
    onPressed: () => nav.openVideo(v),
    onHold: () => showTvOptions(context, title: v.title, subtitle: detail.isEmpty ? null : detail, options: [
      TvOption((place?.inProgress ?? false) ? 'Carry on watching' : 'Play', Icons.play_arrow, () => nav.openVideo(v)),
      TvOption('Go to the collection', Icons.video_library_outlined, () => nav.openVideoCollection(v.collection)),
    ]),
  );
}
