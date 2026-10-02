// The page for one artist: a header with a round picture and play/shuffle buttons, a grid of
// the artist's albums, then a list of every song by them.
//
// Since 0.1.26 (asked for on 29 Sep), clicking an album here doesn't open a new page: its songs
// open in a panel right under the row of covers it's in (click it again, or the panel's ✕, to
// close it). Right-click / press and hold on an album has "Open album page" for the full page,
// and hovering a cover shows a play button (AlbumCard, HoverPlayCover in cards.dart).
//
// Opened through AppNav.openArtist (from album pages, cards and song menus). Artists are grouped
// by album artist in LibraryModel, and this page looks the artist up by name on every build so
// edits show straight away.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artist_picture.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/track_tile.dart';

/// Shows one artist, found by [name] in the library.
class ArtistScreen extends StatefulWidget {
  final String name;
  const ArtistScreen({super.key, required this.name});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  /// The album whose songs are showing under its row (by album key), if any.
  String? _open;

  void _toggle(Album a) => setState(() => _open = _open == a.key ? null : a.key);

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final artist = lib.artistByName(widget.name);
    // The artist may disappear after an edit (e.g. all their songs were renamed to someone else).
    if (artist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.person, title: 'Artist not found'),
      );
    }
    final tracks = artist.tracks;
    final label = 'Artist · ${artist.name}';
    final albums = artist.albums;
    final scope = [for (final a in albums) a.key];

    return Scaffold(
      appBar: AppBar(),
      // A scrolling list of "slivers" so the albums and the long song list share one scroll.
      body: CustomScrollView(
        slivers: [
          // 1. Header: round picture, name, counts and the play/shuffle buttons.
          SliverToBoxAdapter(
            child: CollectionHeader(
              // The picture chosen for the artist, or their first album's cover, drawn as a
              // circle; a click on it (or the button) changes it (0.1.53).
              art: LayoutBuilder(
                builder: (_, c) => Tooltip(
                  message: 'Change picture',
                  child: InkWell(
                    key: const ValueKey('artist-header-picture'),
                    customBorder: const CircleBorder(),
                    onTap: () => showArtistPictureOptions(context, artist),
                    child: Artwork(artist: artist, size: c.maxWidth, radius: c.maxWidth / 2, placeholder: Icons.person),
                  ),
                ),
              ),
              kind: 'Artist',
              title: artist.name,
              subtitle: '${albums.length} albums · ${tracks.length} songs',
              tracks: tracks,
              contextLabel: label,
              extraActions: [
                IconButton(
                  key: const ValueKey('artist-change-picture'),
                  tooltip: 'Change picture',
                  icon: const Icon(Icons.image_outlined),
                  onPressed: () => showArtistPictureOptions(context, artist),
                ),
              ],
            ),
          ),
          // 2. "Albums" heading, then the covers row by row; the open album's songs go under its row.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('Albums', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          SliverLayoutBuilder(
            builder: (context, c) {
              final cols = gridColumns(c.crossAxisExtent - 16);
              final rows = <Widget>[];
              for (var start = 0; start < albums.length; start += cols) {
                final row = albums.sublist(start, (start + cols).clamp(0, albums.length));
                rows.add(
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < cols; i++)
                        Expanded(
                          child: i < row.length
                              ? AlbumCard(
                                  key: ValueKey('artist-album:${row[i].key}'),
                                  album: row[i],
                                  showArtist: false,
                                  scope: scope,
                                  highlighted: row[i].key == _open,
                                  onTap: () => _toggle(row[i]),
                                )
                              : const SizedBox.shrink(),
                        ),
                    ],
                  ),
                );
                final open = row.where((a) => a.key == _open).firstOrNull;
                if (open != null) {
                  rows.add(
                    AlbumSongsPanel(
                      key: ValueKey('album-panel:${open.key}'),
                      album: open,
                      onClose: () => setState(() => _open = null),
                    ),
                  );
                }
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverList.list(children: rows),
              );
            },
          ),
          // 3. "All songs" heading and every song by this artist.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text('All songs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
          SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (_, i) => TrackTile(track: tracks[i], list: tracks, index: i, contextLabel: label),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// An album's songs shown in place on the artist page: title and details, Play, Shuffle,
/// "Open album page" and a close button, then the songs in order (split by disc when needed).
class AlbumSongsPanel extends StatelessWidget {
  final Album album;
  final VoidCallback onClose;
  const AlbumSongsPanel({super.key, required this.album, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final tracks = album.tracks;
    final label = 'Album · ${album.title}';
    final player = context.read<PlayerModel>();
    final multiDisc = tracks.map((t) => t.discNumber ?? 1).toSet().length > 1;
    final details = [
      if (album.year != null) '${album.year}',
      '${tracks.length} song${tracks.length == 1 ? '' : 's'}',
      formatLong(album.totalDuration),
    ].join(' · ');

    final songs = <Widget>[];
    int? disc;
    for (var i = 0; i < tracks.length; i++) {
      final d = tracks[i].discNumber ?? 1;
      if (multiDisc && d != disc) {
        disc = d;
        songs.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Disc $d',
              style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600),
            ),
          ),
        );
      }
      songs.add(TrackTile(track: tracks[i], list: tracks, index: i, showNumber: true, contextLabel: label));
    }

    // A Material (not a coloured box) so the song rows' hover and tap highlights show.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppShape.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        Text(details, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play',
                    icon: const Icon(Icons.play_circle_fill),
                    iconSize: 36,
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () => player.playTracks(tracks, label: label),
                  ),
                  IconButton(
                    tooltip: 'Shuffle',
                    icon: const Icon(Icons.shuffle),
                    onPressed: () => player.playTracks(tracks, shuffle: true, label: label),
                  ),
                  IconButton(
                    key: const ValueKey('panel-open-page'),
                    tooltip: 'Open album page',
                    icon: const Icon(Icons.open_in_new),
                    onPressed: () => context.read<AppNav>().openAlbum(album),
                  ),
                  IconButton(
                    key: const ValueKey('panel-close'),
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            ...songs,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
