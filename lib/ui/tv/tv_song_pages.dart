// Two simple TV pages for the Music screen's Genres and Folders tabs (0.2.0, step 2 of the TV
// interface): a genre's songs, and a folder's subfolders and songs. Each has Play and Shuffle
// at the top, then one big row per song (OK plays from that song; holding OK gives its options).
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_index.dart' show compareTracksInAlbum;
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_widgets.dart';

/// The songs with [genre], by artist, album and track.
List<Track> songsInGenre(LibraryModel lib, String genre) {
  final list = [for (final t in lib.tracks) if (t.genre?.trim() == genre) t];
  list.sort((a, b) {
    final c = _byName(a.albumArtist, b.albumArtist);
    if (c != 0) return c;
    final d = _byName(a.album, b.album);
    return d != 0 ? d : compareTracksInAlbum(a, b);
  });
  return list;
}

int _byName(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

/// Every genre in the library with its number of songs, A–Z.
List<(String, int)> genresOf(LibraryModel lib) {
  final counts = <String, int>{};
  for (final t in lib.tracks) {
    final g = t.genre?.trim();
    if (g != null && g.isNotEmpty) counts[g] = (counts[g] ?? 0) + 1;
  }
  return [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => _byName(a.$1, b.$1));
}

/// A folder's songs: those in it and everything under it ([deep]), or only those right in it.
List<Track> songsInFolder(LibraryModel lib, String folder, {bool deep = true}) {
  final list = [
    for (final t in lib.tracks)
      if (t.path != null && (deep ? p.isWithin(folder, t.path!) : p.equals(p.dirname(t.path!), folder))) t,
  ]..sort((a, b) => a.path!.toLowerCase().compareTo(b.path!.toLowerCase()));
  return list;
}

/// The folders right inside [folder] that hold songs (somewhere under them), with their counts.
List<(String, int)> subfoldersOf(LibraryModel lib, String folder) {
  final counts = <String, int>{};
  for (final t in lib.tracks) {
    final path = t.path;
    if (path == null || !p.isWithin(folder, path)) continue;
    final rest = p.split(p.relative(path, from: folder));
    if (rest.length < 2) continue; // right in the folder
    final sub = p.join(folder, rest.first);
    counts[sub] = (counts[sub] ?? 0) + 1;
  }
  return [for (final e in counts.entries) (e.key, e.value)]..sort((a, b) => _byName(p.basename(a.$1), p.basename(b.$1)));
}

/// A genre's songs.
class TvGenrePage extends StatelessWidget {
  const TvGenrePage({super.key, required this.genre});
  final String genre;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final songs = songsInGenre(lib, genre);
    return _TvSongListPage(
      kind: 'GENRE',
      title: genre,
      label: 'Genre · $genre',
      songs: songs,
    );
  }
}

/// A folder's subfolders and songs.
class TvFolderPage extends StatelessWidget {
  const TvFolderPage({super.key, required this.folder});
  final String folder;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    final subs = subfoldersOf(lib, folder);
    final here = songsInFolder(lib, folder, deep: false);
    return _TvSongListPage(
      kind: 'FOLDER',
      title: p.basename(folder),
      label: 'Folder · ${p.basename(folder)}',
      songs: here,
      allSongs: () => songsInFolder(lib, folder),
      folders: [
        for (final (path, n) in subs)
          (
            path,
            (FocusNode node) => TvRow(
                  key: ValueKey('tv-folder:$path'),
                  focusNode: node,
                  leading: const Icon(Icons.folder_outlined),
                  title: p.basename(path),
                  trailing: Text('$n song${n == 1 ? '' : 's'}  ›'),
                  onPressed: () => nav.push(TvFolderPage(folder: path)),
                ),
          ),
      ],
    );
  }
}

/// The page both use: a heading, Play and Shuffle, then [folders] (rows) and [songs].
class _TvSongListPage extends StatelessWidget {
  const _TvSongListPage({required this.kind, required this.title, required this.label, required this.songs, this.allSongs, this.folders = const []});
  final String kind, title, label;
  final List<Track> songs;

  /// What Play and Shuffle play (a folder: everything under it); [songs] when null.
  final List<Track> Function()? allSongs;
  final List<(String, Widget Function(FocusNode))> folders;

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerModel>();
    final all = allSongs?.call() ?? songs;
    final items = <Object>[...folders, ...songs];
    final n = all.length;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(kind, style: TextStyle(fontSize: 12, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: AppColors.textDim)),
        const SizedBox(height: 4),
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 4),
        Text('$n song${n == 1 ? '' : 's'}', style: TextStyle(fontSize: 14, color: AppColors.textDim)),
        const SizedBox(height: 14),
        Row(children: [
          TvButton(label: 'Play', icon: Icons.play_arrow, primary: true, onPressed: all.isEmpty ? null : () => player.playTracks(all, label: label)),
          const SizedBox(width: 12),
          TvButton(label: 'Shuffle', icon: Icons.shuffle, onPressed: all.isEmpty ? null : () => player.shufflePlay(all, label: label)),
        ]),
      ]),
    );
    return Material(
      color: AppColors.bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(TvStyle.sideMargin, TvStyle.topMargin, 20, TvStyle.bottomMargin),
        child: TvAzGrid<Object>(
          items: items,
          itemHeight: 52,
          header: header,
          itemBuilder: (context, item, i, node, width) {
            if (item is Track) {
              final at = i - folders.length;
              return SizedBox(width: width, child: tvSongRow(context, item, list: songs, index: at, label: label, node: node));
            }
            final (_, build) = item as (String, Widget Function(FocusNode));
            return SizedBox(width: width, child: build(node));
          },
        ),
      ),
    );
  }
}
