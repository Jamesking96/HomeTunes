// The TV's music pages (0.2.0, step 3 of the TV interface; mockup "Album page"): an album, an
// artist, a playlist and Liked Songs. Each has a big header with Play (Pause / Resume while its
// music is the one playing), Shuffle and its other buttons, then one big row per song: OK plays
// from that song, holding OK gives the song's options. In TV mode AppNav opens these instead of
// the usual pages (AppNav.tv).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/playlist_art.dart';
import 'tv_browse.dart';
import 'tv_detail.dart';
import 'tv_items.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

String _songs(int n) => '$n song${n == 1 ? '' : 's'}';

/// Play (or Pause / Resume while [tracks] are what's playing) and Shuffle.
List<Widget> tvPlayButtons(BuildContext context, List<Track> tracks, String label) {
  final player = context.read<PlayerModel>();
  final from = context.select<PlayerModel, bool>((p) => p.isPlayingFrom(tracks));
  final now = context.select<PlayerModel, bool>((p) => p.isPlayingNowFrom(tracks));
  return [
    TvButton(
      key: const ValueKey('tv-page-play'),
      label: now ? 'Pause' : (from ? 'Resume' : 'Play'),
      icon: now ? Icons.pause : Icons.play_arrow,
      primary: true,
      onPressed: tracks.isEmpty ? null : () => player.playOrPauseFrom(tracks, label: label),
    ),
    TvButton(
      key: const ValueKey('tv-page-shuffle'),
      label: 'Shuffle',
      icon: Icons.shuffle,
      onPressed: tracks.isEmpty ? null : () => player.playTracks(tracks, shuffle: true, label: label),
    ),
  ];
}

/// The id of the song playing now (to mark its row), or null.
String? _playingId(BuildContext context) =>
    context.select<PlayerModel, String?>((p) => p.current == null || p.inBook ? null : p.current!.id);

// ---- Album ----

class TvAlbumPage extends StatelessWidget {
  const TvAlbumPage({super.key, required this.albumKey});
  final String albumKey;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final album = lib.albumByKey(albumKey);
    if (album == null) return const TvMissingPage(icon: Icons.album_outlined, title: 'This album isn\'t in your library any more');
    final pl = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();
    final player = context.read<PlayerModel>();
    final tracks = album.tracks;
    final label = 'Album · ${album.title}';
    final playing = _playingId(context);
    final fav = pl.isFavouriteAlbum(album);
    final multiDisc = tracks.map((t) => t.discNumber ?? 1).toSet().length > 1;
    final items = <Object>[];
    int? disc;
    for (final t in tracks) {
      final d = t.discNumber ?? 1;
      if (multiDisc && d != disc) items.add('Disc $d');
      disc = d;
      items.add(t);
    }

    return TvDetailPage<Object>(
      header: TvDetailHeader(
        picture: ArtworkFill(track: album.artTrack, radius: 0),
        kind: 'Album',
        title: album.title,
        lines: [
          [album.artist, if (album.year != null) '${album.year}', _songs(tracks.length), formatLong(album.totalDuration)].join(' · '),
        ],
        buttons: [
          ...tvPlayButtons(context, tracks, label),
          TvIconButton(
            icon: fav ? Icons.favorite : Icons.favorite_border,
            label: fav ? 'Remove from favourites' : 'Add to favourites',
            on: fav,
            onPressed: () => pl.setFavouriteAlbums([album], !fav),
          ),
          TvIconButton(
            icon: Icons.more_horiz,
            label: 'More options',
            onPressed: () => showTvOptions(context, title: album.title, subtitle: album.artist, options: [
              TvOption('Go to the artist', Icons.person_outline, () => nav.openArtist(album.artist)),
              TvOption('Add every song to the queue', Icons.queue_music, () async {
                for (final t in tracks) {
                  await player.addToQueue(t);
                }
              }),
            ]),
          ),
        ],
      ),
      items: items,
      itemBuilder: (context, x, i, node) {
        if (x is String) return TvListHeading(x);
        final t = x as Track;
        final index = tracks.indexOf(t);
        final here = t.id == playing;
        return TvRow(
          key: ValueKey('tv-song:${t.id}'),
          focusNode: node,
          leading: SizedBox(
            width: 28,
            child: here
                ? Icon(Icons.graphic_eq, color: AppColors.accent)
                : Text('${t.trackNumber ?? index + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
          ),
          title: t.title,
          subtitle: t.artist != album.artist ? t.artist : null,
          trailing: Text(t.hasDuration ? formatDuration(t.duration) : ''),
          focusedHint: 'Hold OK for options',
          highlight: here,
          onPressed: () => player.playTracks(tracks, start: index, label: label),
          onHold: () => showSongOptions(context, t),
        );
      },
    );
  }
}

// ---- Artist ----

class TvArtistPage extends StatelessWidget {
  const TvArtistPage({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final artist = lib.artistByName(name);
    if (artist == null) return const TvMissingPage(icon: Icons.person_outline, title: 'This artist isn\'t in your library any more');
    final tracks = artist.tracks;
    final label = 'Artist · ${artist.name}';
    final playing = _playingId(context);
    final albums = artist.albums;
    return TvDetailPage<Object>(
      header: TvDetailHeader(
        picture: LayoutBuilder(builder: (context, c) => Artwork(artist: artist, size: c.maxWidth, radius: 0, placeholder: Icons.person)),
        round: true,
        kind: 'Artist',
        title: artist.name,
        lines: ['${albums.length} album${albums.length == 1 ? '' : 's'} · ${_songs(tracks.length)}'],
        buttons: tvPlayButtons(context, tracks, label),
        after: TvShelf(title: 'Albums', children: [for (final a in albums) tvAlbumTile(context, a, width: 124)]),
      ),
      items: <Object>['Songs', ...tracks],
      itemBuilder: (context, x, i, node) => x is String
          ? TvListHeading(x)
          : tvSongRow(context, x as Track, list: tracks, index: i - 1, label: label, node: node, highlight: x.id == playing),
    );
  }
}

// ---- Playlists and Liked Songs ----

class TvPlaylistPage extends StatelessWidget {
  /// A playlist, or Liked Songs when [playlistId] is null.
  const TvPlaylistPage({super.key, required String this.playlistId});
  const TvPlaylistPage.liked({super.key}) : playlistId = null;
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final pl = context.watch<PlaylistsModel>();
    final playing = _playingId(context);
    final id = playlistId;
    final playlist = id == null ? null : pl.byId(id);
    if (id != null && playlist == null) return const TvMissingPage(icon: Icons.queue_music, title: 'This playlist has been deleted');

    // Each song with its place in the playlist (songs that can't be found now are skipped, and
    // kept in the playlist for when they come back).
    final ids = playlist?.trackIds ?? pl.liked;
    final found = <(int, Track)>[
      for (var i = 0; i < ids.length; i++)
        if (lib.byId(ids[i]) case final t?) (i, t),
    ];
    final tracks = [for (final (_, t) in found) t];
    final missing = ids.length - tracks.length;
    final name = playlist?.name ?? 'Liked Songs';
    final label = playlist == null ? 'Liked Songs' : 'Playlist · $name';
    final length = tracks.fold(Duration.zero, (a, t) => a + t.duration);

    return TvDetailPage<Object>(
      header: TvDetailHeader(
        picture: playlist == null
            ? TvColourPicture(colour: AppColors.accent, icon: Icons.favorite)
            : PlaylistArt(playlist: playlist, radius: 0),
        kind: playlist == null ? 'Playlist' : 'Playlist',
        title: name,
        lines: [
          [_songs(tracks.length), if (length > Duration.zero) formatLong(length), if (missing > 0) '$missing not available now'].join(' · '),
        ],
        buttons: tvPlayButtons(context, tracks, label),
      ),
      items: tracks.isEmpty ? <Object>['No songs here yet.'] : <Object>[...found],
      itemBuilder: (context, x, i, node) {
        if (x is String) return TvListHeading(x);
        final (at, t) = x as (int, Track);
        return tvSongRow(
          context,
          t,
          list: tracks,
          index: i,
          label: label,
          node: node,
          highlight: t.id == playing,
          extra: [
            if (playlist != null) TvOption('Remove from this playlist', Icons.remove_circle_outline, () => pl.removeAt(playlist, at)),
          ],
        );
      },
    );
  }
}
