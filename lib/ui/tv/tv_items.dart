// The TV's tiles and rows for each kind of thing (0.2.0, step 2 of the TV interface): albums,
// artists, songs, playlists, audiobooks, series, video collections and videos. Home and the
// library screens all use these, so an album looks and behaves the same everywhere.
//
// OK opens the thing (its page) or, for a song, plays it. Holding OK opens its options panel
// (tv_menus.dart, step 4).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/video_item.dart';
import '../../state/book_index.dart';
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
import 'tv_menus.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

export 'tv_menus.dart';

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


// ---- Artists ----

TvTile tvArtistTile(BuildContext context, Artist a, {FocusNode? node, double width = 124}) {
  final nav = context.read<AppNav>();
  return TvTile(
    key: ValueKey('tv-artist:${a.name}'),
    focusNode: node,
    width: width,
    pictureRadius: width,
    picture: LayoutBuilder(builder: (context, c) => Artwork(artist: a, size: c.maxWidth, radius: 0, placeholder: Icons.person)),
    title: a.name,
    subtitle: '${_count(a.albums.length, 'album')} · ${_count(a.tracks.length, 'song')}',
    onPressed: () => nav.openArtist(a.name),
    onHold: () => showArtistOptions(context, a),
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

// ---- Playlists ----

TvTile tvLikedTile(BuildContext context, {FocusNode? node, double width = 124}) {
  final pl = context.read<PlaylistsModel>();
  final nav = context.read<AppNav>();
  return TvTile(
    key: const ValueKey('tv-liked'),
    focusNode: node,
    width: width,
    picture: TvColourPicture(colour: AppColors.accent, icon: Icons.favorite),
    title: 'Liked Songs',
    subtitle: _count(pl.liked.length, 'song'),
    onPressed: nav.openLiked,
    onHold: () => showPlaylistOptions(context, null),
  );
}

TvTile tvPlaylistTile(BuildContext context, Playlist p, {FocusNode? node, double width = 124}) {
  final nav = context.read<AppNav>();
  return TvTile(
    key: ValueKey('tv-playlist:${p.id}'),
    focusNode: node,
    width: width,
    picture: PlaylistArt(playlist: p, radius: 0),
    title: p.name,
    subtitle: _count(p.trackIds.length, 'song'),
    onPressed: () => nav.openPlaylist(p),
    onHold: () => showPlaylistOptions(context, p),
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


TvTile tvSeriesTile(BuildContext context, BookSeries s, {FocusNode? node, double width = 124, required double aspectRatio}) {
  final nav = context.read<AppNav>();
  final progress = seriesProgress(s, context.read<ListeningModel>());
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
    onHold: () => showSeriesOptions(context, s),
  );
}

// ---- Videos ----

TvTile tvCollectionTile(BuildContext context, VideoCollection c, {FocusNode? node, double width = 150, double? aspectRatio}) {
  final nav = context.read<AppNav>();
  final videos = context.read<VideoLibraryModel>();
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
    onHold: () => showCollectionOptions(context, c),
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
    onHold: () => showVideoOptions(context, v),
  );
}
