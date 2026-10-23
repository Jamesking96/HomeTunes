// The TV's Music screen (0.2.0, step 2 of the TV interface; mockup "Music library"): tabs for
// Albums, Artists, Songs, Playlists, Genres and Folders, each a grid of big tiles (or a list of
// big rows) with the A–Z strip down the right. The Sort button picks the order from a list in
// the options panel. Albums, artists and playlists open their pages (their TV versions come in
// step 3); a genre or a folder opens a simple TV page of its songs (tv_song_pages.dart).
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../state/library_index.dart' show sortKey;
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_options.dart';
import 'tv_song_pages.dart';
import 'tv_widgets.dart';

/// The Music screen's tabs, in order.
enum TvMusicTab {
  albums('Albums'),
  artists('Artists'),
  songs('Songs'),
  playlists('Playlists'),
  genres('Genres'),
  folders('Folders');

  const TvMusicTab(this.label);
  final String label;
}

enum TvAlbumSort {
  title('A–Z'),
  artist('Artist'),
  recentlyAdded('Recently added'),
  year('Year');

  const TvAlbumSort(this.label);
  final String label;
}

enum TvArtistSort {
  name('A–Z'),
  mostSongs('Most songs');

  const TvArtistSort(this.label);
  final String label;
}

enum TvSongSort {
  title('A–Z'),
  artist('Artist'),
  recentlyAdded('Recently added');

  const TvSongSort(this.label);
  final String label;
}

/// The hints while browsing a library tab.
const tvLibraryHints = <TvHint>[('→', 'at the edge: jump A–Z'), ('↑', 'tabs'), ('Hold OK', 'Options'), ('←', 'menu')];

/// The albums in [sort] order.
List<Album> tvSortAlbums(LibraryModel lib, TvAlbumSort sort) => switch (sort) {
      TvAlbumSort.title => [...lib.albums]..sort((a, b) => sortKey(a.title).compareTo(sortKey(b.title))),
      TvAlbumSort.artist => lib.albums, // already by artist, then title
      TvAlbumSort.recentlyAdded => lib.albumsByNewest,
      TvAlbumSort.year => [...lib.albums]..sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0)),
    };

class TvMusicScreen extends StatefulWidget {
  const TvMusicScreen({super.key});

  @override
  State<TvMusicScreen> createState() => _TvMusicScreenState();
}

class _TvMusicScreenState extends State<TvMusicScreen> {
  var _tab = TvMusicTab.albums;
  var _albumSort = TvAlbumSort.title;
  var _artistSort = TvArtistSort.name;
  var _songSort = TvSongSort.title;

  Future<void> _chooseSort<T extends Enum>(String what, List<T> values, T current, String Function(T) label, ValueChanged<T> pick) {
    return showTvOptions(context, title: 'Sort $what', options: [
      for (final v in values)
        TvOption(label(v), v == current ? Icons.check : Icons.sort, () => setState(() => pick(v))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final playlists = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();

    final actions = <Widget>[
      if (_tab == TvMusicTab.albums)
        TvButton(
          key: const ValueKey('tv-sort'),
          label: 'Sort: ${_albumSort.label}',
          icon: Icons.sort,
          onPressed: () => _chooseSort('albums', TvAlbumSort.values, _albumSort, (s) => s.label, (s) => _albumSort = s),
        ),
      if (_tab == TvMusicTab.artists)
        TvButton(
          key: const ValueKey('tv-sort'),
          label: 'Sort: ${_artistSort.label}',
          icon: Icons.sort,
          onPressed: () => _chooseSort('artists', TvArtistSort.values, _artistSort, (s) => s.label, (s) => _artistSort = s),
        ),
      if (_tab == TvMusicTab.songs) ...[
        TvButton(
          key: const ValueKey('tv-shuffle'),
          label: 'Shuffle',
          icon: Icons.shuffle,
          onPressed: lib.tracks.isEmpty ? null : () => context.read<PlayerModel>().shufflePlay(lib.tracks, label: 'All songs'),
        ),
        TvButton(
          key: const ValueKey('tv-sort'),
          label: 'Sort: ${_songSort.label}',
          icon: Icons.sort,
          onPressed: () => _chooseSort('songs', TvSongSort.values, _songSort, (s) => s.label, (s) => _songSort = s),
        ),
      ],
    ];

    final Widget body;
    if (lib.tracks.isEmpty && _tab != TvMusicTab.playlists) {
      body = TvEmpty(
        icon: Icons.library_music_outlined,
        title: lib.busy ? 'Looking through your folders…' : 'No music yet',
        message: lib.busy ? null : 'Choose the folders your music is in, on a USB drive or the TV itself, or connect a server.',
        action: lib.busy
            ? null
            : TvButton(label: 'Add music folders', icon: Icons.folder_open, primary: true, onPressed: () => nav.openSettings('library', setting: 'music-folders')),
      );
    } else {
      body = switch (_tab) {
        TvMusicTab.albums => TvAzGrid<Album>(
            key: ValueKey('albums-${_albumSort.name}'),
            items: tvSortAlbums(lib, _albumSort),
            letterOf: switch (_albumSort) {
              TvAlbumSort.title => (a) => tvLetterOf(a.title),
              TvAlbumSort.artist => (a) => tvLetterOf(a.artist),
              _ => null,
            },
            itemBuilder: (context, a, i, node, w) => tvAlbumTile(context, a, node: node, width: w),
          ),
        TvMusicTab.artists => TvAzGrid<Artist>(
            key: ValueKey('artists-${_artistSort.name}'),
            items: _artistSort == TvArtistSort.name
                ? lib.artists
                : ([...lib.artists]..sort((a, b) => b.tracks.length.compareTo(a.tracks.length))),
            letterOf: _artistSort == TvArtistSort.name ? (a) => tvLetterOf(a.name) : null,
            itemBuilder: (context, a, i, node, w) => tvArtistTile(context, a, node: node, width: w),
          ),
        TvMusicTab.songs => _songs(lib),
        TvMusicTab.playlists => TvAzGrid<Object>(
            key: const ValueKey('playlists'),
            items: ['liked', ...playlists.playlists],
            itemBuilder: (context, x, i, node, w) =>
                x is String ? tvLikedTile(context, node: node, width: w) : tvPlaylistTile(context, x as Playlist, node: node, width: w),
          ),
        TvMusicTab.genres => _genres(lib, nav),
        TvMusicTab.folders => _folders(lib, nav),
      };
    }

    return TvPageHints(
      tab: AppNav.libraryTab,
      hints: tvLibraryHints,
      child: TvPage(
        title: 'Music',
        tabs: TvTabBar(
          labels: [for (final t in TvMusicTab.values) t.label],
          selected: _tab.index,
          onSelect: (i) => setState(() => _tab = TvMusicTab.values[i]),
        ),
        actions: actions,
        body: body,
      ),
    );
  }

  Widget _songs(LibraryModel lib) {
    final songs = switch (_songSort) {
      TvSongSort.title => lib.songsByTitle,
      TvSongSort.artist => lib.albums.expand((a) => a.tracks).toList(),
      TvSongSort.recentlyAdded => [...lib.tracks]..sort((a, b) => (b.modifiedMs ?? 0).compareTo(a.modifiedMs ?? 0)),
    };
    return TvAzGrid<Track>(
      key: ValueKey('songs-${_songSort.name}'),
      items: songs,
      itemHeight: 52,
      letterOf: switch (_songSort) {
        TvSongSort.title => (t) => tvLetterOf(t.title),
        TvSongSort.artist => (t) => tvLetterOf(t.albumArtist),
        _ => null,
      },
      itemBuilder: (context, t, i, node, w) =>
          SizedBox(width: w, child: tvSongRow(context, t, list: songs, index: i, label: 'All songs', node: node)),
    );
  }

  Widget _genres(LibraryModel lib, AppNav nav) {
    final genres = genresOf(lib);
    if (genres.isEmpty) {
      return const TvEmpty(icon: Icons.category_outlined, title: 'No genres', message: 'None of your songs have a genre in their details.');
    }
    return TvAzGrid<(String, int)>(
      key: const ValueKey('genres'),
      items: genres,
      letterOf: (g) => tvLetterOf(g.$1),
      itemBuilder: (context, g, i, node, w) => TvTile(
        key: ValueKey('tv-genre:${g.$1}'),
        focusNode: node,
        width: w,
        picture: TvColourPicture(colour: TvColourPicture.forName(g.$1), label: g.$1),
        title: g.$1,
        subtitle: '${g.$2} song${g.$2 == 1 ? '' : 's'}',
        onPressed: () => nav.push(TvGenrePage(genre: g.$1)),
      ),
    );
  }

  Widget _folders(LibraryModel lib, AppNav nav) {
    // The music folders chosen in Settings that have songs in them.
    final roots = [
      for (final f in lib.folders)
        if (lib.tracks.any((t) => t.path != null && p.isWithin(f, t.path!))) f,
    ];
    if (roots.isEmpty) {
      return const TvEmpty(icon: Icons.folder_outlined, title: 'No music folders', message: 'Songs from a server aren\'t in folders.');
    }
    return TvAzGrid<String>(
      key: const ValueKey('folders'),
      items: roots,
      itemHeight: 56,
      itemBuilder: (context, f, i, node, w) {
        final n = songsInFolder(lib, f).length;
        return SizedBox(
          width: w,
          child: TvRow(
            key: ValueKey('tv-folder:$f'),
            focusNode: node,
            height: 56,
            leading: const Icon(Icons.folder_outlined),
            title: p.basename(f),
            subtitle: f,
            trailing: Text('$n song${n == 1 ? '' : 's'}  ›'),
            onPressed: () => nav.push(TvFolderPage(folder: f)),
          ),
        );
      },
    );
  }
}
