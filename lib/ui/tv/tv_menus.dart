// Every menu on the TV, in the options panel (0.2.0, step 4 of the TV interface). Holding OK on
// a song, album, artist, playlist, audiobook, series, video or collection opens its panel, and a
// page's More button opens the same one (without "Open…", as it's already open). What the menus
// elsewhere offer is here, laid out for the remote:
//  * a choice that leads to another choice opens a second panel (Add to a playlist ›, Change
//    picture ›, Delete ›, which asks first);
//  * things that need typing or a form (Edit details, Rename, New playlist, Edit series) use the
//    TV keyboard (step 7: tv_keyboard.dart; the forms' text boxes open it); Copy title, Select and
//    Show in folder are left out (no clipboard, select mode or file window on a TV).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/download.dart' show KeepKind;
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../models/track_edit.dart';
import '../../models/video_item.dart';
import '../../state/book_index.dart';
import '../../state/downloads_model.dart' show DownloadItem, DownloadsModel;
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../screens/book_lookup_dialog.dart' show showBookCoverSearch;
import '../screens/cover_search_dialog.dart' show showCoverSearch;
import '../screens/details_screen.dart' show openDetails;
import '../screens/edit_book.dart' show showEditBook;
import '../screens/edit_details.dart' show showEditDetails;
import '../screens/edit_series.dart' show showEditSeries;
import '../screens/edit_video.dart' show showEditVideos;
import '../screens/video_collection/edit_collection.dart' show showEditCollection;
import '../screens/lyrics_dialogs.dart' show showLyricsDialog, findLyricsOnline;
import '../screens/video_details_screen.dart' show openVideoDetails, openCollectionDetails;
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/book_card.dart' show BookCover;
import '../widgets/playlist_art.dart';
import '../widgets/series_card.dart' show seriesProgress, playSeries, markSeriesFinished;
import 'tv_downloads.dart' show tvDownloadOptions;
import 'tv_keyboard.dart' show showTvTextInput;
import 'tv_options.dart';

String _songs(int n) => '$n song${n == 1 ? '' : 's'}';

/// A short note at the bottom of the screen ("Added to Road trip").
///
/// [aboveControls]: raised over the video player's controls (0.2.5: "Carrying on from…" covered
/// the player's buttons).
void tvNotice(BuildContext context, String text, {bool aboveControls = false}) => ScaffoldMessenger.maybeOf(context)
  ?..hideCurrentSnackBar()
  ..showSnackBar(tvSnackBar(text, bottom: aboveControls ? 140 : 24));

/// A notice in the TV's dark style, floating near the bottom: Material's own is a pale bar, bright
/// on a dark TV screen, with a close button the remote can't reach (0.2.5).
SnackBar tvSnackBar(String text, {Key? key, Duration duration = const Duration(seconds: 3), double bottom = 24}) => SnackBar(
      key: key,
      duration: duration,
      behavior: SnackBarBehavior.floating,
      showCloseIcon: false,
      backgroundColor: AppColors.surfaceHigh,
      elevation: 6,
      margin: EdgeInsets.fromLTRB(160, 0, 160, bottom),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppColors.faded(0.12))),
      content: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppColors.text)),
    );

/// Asks before something that can't be undone: [yes] runs only when that row is chosen.
Future<void> tvConfirm(BuildContext context, {required String title, String? subtitle, required String yes, required VoidCallback run}) =>
    showTvOptions(context, title: title, subtitle: subtitle, options: [
      TvOption('Keep it', Icons.close, () {}),
      TvOption(yes, Icons.delete_outline, run),
    ]);

/// Add to a playlist ›: Liked Songs (one song) and every playlist.
TvOption tvAddToPlaylist(BuildContext context, List<Track> tracks, {String? what}) {
  final pl = context.read<PlaylistsModel>();
  return TvOption('Add to a playlist', Icons.playlist_add, opensMore: true, () {
    showTvOptions(context, title: 'Add to a playlist', subtitle: what ?? (tracks.length == 1 ? tracks.single.title : _songs(tracks.length)), options: [
      if (tracks.length == 1 && !pl.isLiked(tracks.single))
        TvOption('Liked Songs', Icons.favorite, () {
          pl.toggleLike(tracks.single);
          tvNotice(context, 'Added to Liked Songs');
        }),
      for (final p in pl.playlists)
        TvOption(p.name, Icons.queue_music, subtitle: _songs(p.trackIds.length), picture: PlaylistArt(playlist: p, radius: 0), () {
          final added = pl.addTracks(p, tracks);
          tvNotice(context, added == 0 ? 'Already in ${p.name}' : 'Added to ${p.name}');
        }),
      TvOption('New playlist', Icons.add, opensMore: true, () async {
        final name = await showTvTextInput(context, title: 'Name the new playlist', hint: 'Road trip, Sunday morning…');
        if (name == null || name.trim().isEmpty || !context.mounted) return;
        final p = pl.create(name.trim());
        pl.addTracks(p, tracks);
        tvNotice(context, 'Added to ${p.name}');
      }),
    ]);
  });
}

/// Find cover online and Use the files' own cover, for an album's or a book's files.
List<TvOption> _coverOptions(BuildContext context, List<Track> files, Future<String?> Function() search) {
  final lib = context.read<LibraryModel>();
  final ids = [for (final t in files) t.id];
  return [
    if (lib.settings.online.onlineCovers)
      TvOption('Find cover online', Icons.travel_explore, () async {
        final path = await search();
        if (path != null) await lib.editMany(ids, TrackEdit(art: path));
      }),
    if (files.any((t) => lib.originalById(t.id)?.art != t.art))
      TvOption('Use the files\' own cover', Icons.restore, () => lib.resetCovers(ids)),
  ];
}

// ---- Songs ----

/// [extra]: options for where the song is (Remove from this playlist).
List<TvOption> songOptions(BuildContext context, Track t, {List<TvOption> extra = const []}) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final liked = pl.isLiked(t);
  final album = lib.albumByKey(t.albumKey);
  return [
    TvOption('Play next', Icons.playlist_play, () => player.playNext(t)),
    TvOption('Add to the queue', Icons.queue_music, () => player.addToQueue(t)),
    tvAddToPlaylist(context, [t]),
    TvOption(liked ? 'Remove from Liked Songs' : 'Add to Liked Songs', liked ? Icons.favorite : Icons.favorite_border, () => pl.toggleLike(t)),
    ...extra,
    // From the music server: Download / Stop downloading / Remove download / Make it mine (0.2.3).
    ...tvDownloadOptions(context, [DownloadItem.track(t, book: lib.bookOfTrack(t.id) != null)]),
    if (album != null) TvOption('Go to the album', Icons.album_outlined, () => nav.openAlbum(album)),
    TvOption('Go to the artist', Icons.person_outline, () => nav.openArtist(t.albumArtist.isEmpty ? t.artist : t.albumArtist)),
    TvOption('Lyrics', Icons.lyrics_outlined, () => showLyricsDialog(context, t)),
    if (lib.settings.online.onlineLyrics) TvOption('Find lyrics online', Icons.travel_explore, () => findLyricsOnline(context, t)),
    TvOption('Details', Icons.info_outline, () => openDetails(context, kind: 'Song', title: t.title, tracks: [t])),
    TvOption('Edit details', Icons.edit_outlined, opensMore: true, () => showEditDetails(context, [t])),
    if (t.isLocal)
      TvOption('Move to Audiobooks', Icons.menu_book_outlined, () async {
        await lib.setIsBook([t.id], true);
        if (context.mounted) tvNotice(context, '"${t.title}" moved to Audiobooks');
      }),
  ];
}

Future<void> showSongOptions(BuildContext context, Track t, {List<TvOption> extra = const []}) => showTvOptions(
      context,
      title: t.title,
      subtitle: '${t.artist} · ${t.album}',
      picture: Artwork(track: t, size: 64, radius: 0),
      options: songOptions(context, t, extra: extra),
    );

// ---- Albums ----

List<TvOption> albumOptions(BuildContext context, Album a, {bool onPage = false}) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final nav = context.read<AppNav>();
  final fav = pl.isFavouriteAlbum(a);
  final label = 'Album · ${a.title}';
  return [
    if (!onPage) ...[
      TvOption('Play', Icons.play_arrow, () => player.playTracks(a.tracks, label: label)),
      TvOption('Shuffle', Icons.shuffle, () => player.playTracks(a.tracks, shuffle: true, label: label)),
      TvOption('Open the album', Icons.album_outlined, () => nav.openAlbum(a)),
    ],
    TvOption('Add to the queue', Icons.queue_music, () async {
      for (final t in a.tracks) {
        await player.addToQueue(t);
      }
    }),
    tvAddToPlaylist(context, a.tracks, what: a.title),
    TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
        () => pl.setFavouriteAlbums([a], !fav)),
    ...tvDownloadOptions(context, [for (final t in a.tracks) DownloadItem.track(t)],
        keep: (kind: KeepKind.album, key: a.key, label: a.title)),
    TvOption('Go to the artist', Icons.person_outline, () => nav.openArtist(a.artist)),
    ..._coverOptions(context, a.tracks, () => showCoverSearch(context, artist: a.artist, album: a.title)),
    TvOption('Details', Icons.info_outline, () => openDetails(context, kind: 'Album', title: a.title, tracks: a.tracks)),
    TvOption('Edit details', Icons.edit_outlined, opensMore: true, () => showEditDetails(context, a.tracks, album: true)),
  ];
}

Future<void> showAlbumOptions(BuildContext context, Album a, {bool onPage = false}) => showTvOptions(
      context,
      title: a.title,
      subtitle: a.artist,
      picture: Artwork(track: a.artTrack, size: 64, radius: 0),
      options: albumOptions(context, a, onPage: onPage),
    );

// ---- Artists ----

List<TvOption> artistOptions(BuildContext context, Artist a, {bool onPage = false}) {
  final player = context.read<PlayerModel>();
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final label = 'Artist · ${a.name}';
  return [
    if (!onPage) ...[
      TvOption('Play', Icons.play_arrow, () => player.playTracks(a.tracks, label: label)),
      TvOption('Shuffle', Icons.shuffle, () => player.playTracks(a.tracks, shuffle: true, label: label)),
      TvOption('Open the artist', Icons.person_outline, () => nav.openArtist(a.name)),
    ],
    tvAddToPlaylist(context, a.tracks, what: a.name),
    if (a.albums.isNotEmpty)
      TvOption('Change picture', Icons.image_outlined, opensMore: true, () {
        showTvOptions(context, title: 'Picture for ${a.name}', subtitle: 'One of their album covers', options: [
          for (final album in a.albums)
            TvOption(album.title, Icons.album_outlined, picture: ArtworkFill(track: album.artTrack, radius: 0), () async {
              await lib.setArtistPicture(a, album: album);
              if (context.mounted) tvNotice(context, '${a.name} now shows "${album.title}"');
            }),
        ]);
      }),
    if (lib.hasArtistPicture(a))
      TvOption('Use the automatic picture', Icons.restore, () => lib.setArtistPicture(a)),
  ];
}

Future<void> showArtistOptions(BuildContext context, Artist a, {bool onPage = false}) => showTvOptions(
      context,
      title: a.name,
      subtitle: '${a.albums.length} album${a.albums.length == 1 ? '' : 's'} · ${_songs(a.tracks.length)}',
      picture: Artwork(artist: a, size: 64, radius: 0, placeholder: Icons.person),
      options: artistOptions(context, a, onPage: onPage),
    );

// ---- Playlists and Liked Songs ----

/// A playlist's options, or Liked Songs' when [p] is null.
List<TvOption> playlistOptions(BuildContext context, Playlist? p, {bool onPage = false}) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final lib = context.read<LibraryModel>();
  final nav = context.read<AppNav>();
  final name = p?.name ?? 'Liked Songs';
  final label = p == null ? 'Liked Songs' : 'Playlist · $name';
  List<Track> songs() => [for (final id in p?.trackIds ?? pl.liked) ?lib.byId(id)];
  return [
    if (!onPage) ...[
      TvOption('Play', Icons.play_arrow, () => player.playTracks(songs(), label: label)),
      TvOption('Shuffle', Icons.shuffle, () => player.playTracks(songs(), shuffle: true, label: label)),
      TvOption(p == null ? 'Open Liked Songs' : 'Open the playlist', Icons.queue_music, () => p == null ? nav.openLiked() : nav.openPlaylist(p)),
    ],
    TvOption('Add to the queue', Icons.queue_music, () async {
      for (final t in songs()) {
        await player.addToQueue(t);
      }
    }),
    ...tvDownloadOptions(context, [for (final t in songs()) DownloadItem.track(t)],
        keep: p == null ? (kind: KeepKind.liked, key: '', label: 'Liked Songs') : (kind: KeepKind.playlist, key: p.id, label: p.name)),
    if (p != null)
      TvOption('Rename', Icons.drive_file_rename_outline, opensMore: true, () async {
        final to = await showTvTextInput(context, title: 'Rename the playlist', initial: p.name);
        if (to != null && to.trim().isNotEmpty) pl.rename(p, to.trim());
      }),
    if (p != null)
      TvOption('Delete the playlist', Icons.delete_outline, opensMore: true, () {
        tvConfirm(context, title: 'Delete "${p.name}"?', subtitle: 'The songs stay in your library', yes: 'Delete it', run: () {
          if (onPage) Navigator.of(context).maybePop();
          pl.delete(p);
        });
      }),
  ];
}

Future<void> showPlaylistOptions(BuildContext context, Playlist? p, {bool onPage = false}) {
  final pl = context.read<PlaylistsModel>();
  final n = p?.trackIds.length ?? pl.liked.length;
  return showTvOptions(
    context,
    title: p?.name ?? 'Liked Songs',
    subtitle: _songs(n),
    picture: p == null ? null : PlaylistArt(playlist: p, radius: 0),
    options: playlistOptions(context, p, onPage: onPage),
  );
}

// ---- Audiobooks ----

List<TvOption> bookOptions(BuildContext context, Book b, {bool onPage = false}) {
  final player = context.read<PlayerModel>();
  final pl = context.read<PlaylistsModel>();
  final listening = context.read<ListeningModel>();
  final nav = context.read<AppNav>();
  final state = listening.stateOf(b);
  final fav = pl.isFavouriteBook(b);
  final series = b.series;
  return [
    if (!onPage) ...[
      TvOption(state == BookState.inProgress ? 'Carry on listening' : 'Play', Icons.play_arrow,
          () => player.playBook(b, fromStart: state == BookState.finished)),
      if (state != BookState.notStarted) TvOption('Play from the start', Icons.replay, () => player.playBook(b, fromStart: true)),
      TvOption('Open the book', Icons.menu_book_outlined, () => nav.openBook(b)),
    ],
    if (series != null && series.trim().isNotEmpty)
      TvOption('Go to the series', Icons.collections_bookmark_outlined, () => nav.openSeries(series)),
    TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
        () => pl.setFavouriteBooks([b], !fav)),
    if (state != BookState.finished)
      TvOption('Mark as finished', Icons.done_all, () => listening.setFinished(b, true))
    else
      TvOption('Mark as not finished', Icons.remove_done, () => listening.setFinished(b, false)),
    ...tvDownloadOptions(context, [for (final t in b.parts) DownloadItem.track(t, book: true)],
        keep: (kind: KeepKind.book, key: b.id, label: b.title)),
    ..._coverOptions(context, b.parts, () => showBookCoverSearch(context, title: b.title, author: b.author)),
    TvOption('Details', Icons.info_outline, () => openDetails(context, kind: 'Audiobook', title: b.title, tracks: b.parts, book: b)),
    TvOption('Edit details', Icons.edit_outlined, opensMore: true, () => showEditBook(context, b)),
  ];
}

Future<void> showBookOptions(BuildContext context, Book b, {bool onPage = false}) => showTvOptions(
      context,
      title: b.title,
      subtitle: b.author,
      picture: BookCover(book: b, width: 64, radius: 0),
      options: bookOptions(context, b, onPage: onPage),
    );

List<TvOption> seriesOptions(BuildContext context, BookSeries s, {bool onPage = false}) {
  final pl = context.read<PlaylistsModel>();
  final listening = context.read<ListeningModel>();
  final nav = context.read<AppNav>();
  final progress = seriesProgress(s, listening);
  final fav = pl.isFavouriteSeries(s.name);
  return [
    if (!onPage) ...[
      TvOption(progress.finished == 0 ? 'Play' : (progress.allFinished ? 'Listen again' : 'Continue'), Icons.play_arrow,
          () => playSeries(context, s)),
      TvOption('Open the series', Icons.collections_bookmark_outlined, () => nav.openSeries(s.name)),
    ],
    TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
        () => pl.setFavouriteSeries([s.name], !fav)),
    TvOption(progress.allFinished ? 'Mark all as not finished' : 'Mark all as finished',
        progress.allFinished ? Icons.remove_done : Icons.done_all, () => markSeriesFinished(listening, s, !progress.allFinished)),
    TvOption('Edit series', Icons.edit_outlined, opensMore: true, () async {
      final renamed = await showEditSeries(context, s);
      // On its page under its old name: open it again under the new one.
      if (onPage && renamed != null && renamed != s.name && context.mounted) {
        Navigator.of(context).pop();
        nav.openSeries(renamed);
      }
    }),
  ];
}

Future<void> showSeriesOptions(BuildContext context, BookSeries s, {bool onPage = false}) => showTvOptions(
      context,
      title: s.name,
      subtitle: '${s.books.length} book${s.books.length == 1 ? '' : 's'}',
      options: seriesOptions(context, s, onPage: onPage),
    );

// ---- Videos ----

List<TvOption> videoOptions(BuildContext context, VideoItem v) {
  final model = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final place = model.placeOf(v.id);
  final watched = place?.watched ?? false;
  final started = place?.inProgress ?? false;
  return [
    TvOption(started ? 'Carry on watching' : 'Play', Icons.play_arrow, () => nav.openVideo(v)),
    // Always offered (the user, 23 Oct): starts at 0:00 whether or not it was started before.
    TvOption('Watch from the beginning', Icons.replay, () async {
      await model.setWatched([v.id], false);
      nav.openVideo(v);
    }),
    TvOption(watched ? 'Mark as not watched' : 'Mark as watched', watched ? Icons.remove_done : Icons.done,
        () => model.setWatched([v.id], !watched)),
    ...tvDownloadOptions(context, [DownloadItem.video(v)]),
    TvOption('Go to the collection', Icons.video_library_outlined, () => nav.openVideoCollection(v.collection)),
    TvOption('Details', Icons.info_outline, () => openVideoDetails(context, v)),
    TvOption('Edit details', Icons.edit_outlined, opensMore: true, () => showEditVideos(context, [v])),
  ];
}

Future<void> showVideoOptions(BuildContext context, VideoItem v) => showTvOptions(
      context,
      title: v.title,
      subtitle: [if (v.collection != v.title) v.collection, ?v.episodeLabel].join(' · '),
      options: videoOptions(context, v),
    );

/// [season]: on the collection's page, the season tab showing (its heading and videos), which
/// can be downloaded or kept offline on its own (0.2.3).
List<TvOption> collectionOptions(BuildContext context, VideoCollection c,
    {bool onPage = false, ({String heading, String label, List<VideoItem> videos})? season}) {
  final model = context.read<VideoLibraryModel>();
  final nav = context.read<AppNav>();
  final fav = model.isFavourite(c);
  final next = model.nextUp(c);
  final allWatched = c.main.isNotEmpty && model.watchedCount(c) == c.main.length;
  return [
    if (!onPage) ...[
      if (next != null) TvOption('Play ${next.episodeLabel ?? next.title}', Icons.play_arrow, () => nav.openVideo(next)),
      TvOption('Open the collection', Icons.video_library_outlined, () => nav.openVideoCollection(c.name)),
    ],
    TvOption(fav ? 'Remove from favourites' : 'Add to favourites', fav ? Icons.favorite : Icons.favorite_border,
        () => model.setFavourite(c, !fav)),
    TvOption(allWatched ? 'Mark all as not watched' : 'Mark all as watched', allWatched ? Icons.remove_done : Icons.done_all,
        () => model.setWatched([for (final v in c.main) v.id], !allWatched)),
    // From a server: the whole collection, and the season showing (0.2.3).
    ...tvDownloadOptions(context, [for (final v in c.videos) DownloadItem.video(v)],
        keep: (kind: KeepKind.collection, key: c.key, label: c.name)),
    if (season != null)
      for (final o in tvDownloadOptions(context, [for (final v in season.videos) DownloadItem.video(v)],
          keep: (kind: KeepKind.season, key: DownloadsModel.seasonKey(c, season.heading), label: '${c.name} – ${season.label}')))
        TvOption('${o.label}: ${season.label}', o.icon, o.onSelected, opensMore: o.opensMore),
    TvOption('Details', Icons.info_outline, () => openCollectionDetails(context, c)),
    TvOption('Edit details', Icons.edit_outlined, opensMore: true, () async {
      final renamed = await showEditCollection(context, c);
      if (onPage && renamed != null && renamed != c.name && context.mounted) {
        Navigator.of(context).pop();
        nav.openVideoCollection(renamed);
      }
    }),
  ];
}

Future<void> showCollectionOptions(BuildContext context, VideoCollection c,
        {bool onPage = false, ({String heading, String label, List<VideoItem> videos})? season}) =>
    showTvOptions(
      context,
      title: c.name,
      subtitle: [?c.category, '${c.videos.length} video${c.videos.length == 1 ? '' : 's'}'].join(' · '),
      options: collectionOptions(context, c, onPage: onPage, season: season),
    );
