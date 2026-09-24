import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/collection_header.dart';
import '../widgets/track_tile.dart';
import '../../models/track_edit.dart';
import '../../services/music_info.dart';
import 'cover_search_dialog.dart';
import 'info_lookup_dialog.dart';
import 'edit_details.dart';

class AlbumScreen extends StatelessWidget {
  final String albumKey;
  const AlbumScreen({super.key, required this.albumKey});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final album = lib.albumByKey(albumKey);
    if (album == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.album, title: 'Album not found'));
    }
    final tracks = album.tracks;
    final multiDisc = tracks.map((t) => t.discNumber ?? 1).toSet().length > 1;
    final label = 'Album · ${album.title}';

    final children = <Widget>[];
    int? disc;
    for (var i = 0; i < tracks.length; i++) {
      final d = tracks[i].discNumber ?? 1;
      if (multiDisc && d != disc) {
        disc = d;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(children: [
            const Icon(Icons.album, size: 18, color: AppColors.textDim),
            const SizedBox(width: 8),
            Text('Disc $d', style: const TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
          ]),
        ));
      }
      children.add(TrackTile(track: tracks[i], list: tracks, index: i, showNumber: true, contextLabel: label));
    }

    return Scaffold(
      appBar: AppBar(),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        CollectionHeader(
          art: ArtworkFill(track: album.artTrack),
          kind: 'Album',
          title: album.title,
          subtitle: [
            album.artist,
            if (album.year != null) '${album.year}',
            '${tracks.length} songs, ${formatLong(album.totalDuration)}',
          ].join(' · '),
          tracks: tracks,
          contextLabel: label,
          extraActions: [
            IconButton(
              tooltip: 'Edit album details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final firstId = tracks.first.id;
                // Grab these first: renaming the album rebuilds this page as
                // "not found", which unmounts this button's context.
                final navigator = Navigator.of(context);
                final library = context.read<LibraryModel>();
                final saved = await showEditDetails(context, tracks, album: true);
                if (!saved) return;
                // Renaming the album (or its artist) changes which album the songs group
                // under, so follow them to the album's new page.
                final newKey = library.byId(firstId)?.albumKey;
                if (newKey != null && newKey != albumKey && navigator.mounted) {
                  navigator.pushReplacement(
                    MaterialPageRoute(builder: (_) => AlbumScreen(albumKey: newKey)),
                  );
                }
              },
            ),
            IconButton(
              tooltip: 'Add album to playlist',
              icon: const Icon(Icons.playlist_add),
              onPressed: () => showAddToPlaylist(context, tracks),
            ),
            TextButton(
              onPressed: () => context.read<AppNav>().openArtist(album.artist),
              child: Text(album.artist),
            ),
          ],
        ),
        _MissingInfoPrompts(albumKey: albumKey),
        ...children,
      ]),
    );
  }
}

/// What an album page can offer to look up online when it's missing.
enum _Missing { cover, artist, year, genre, trackNumbers }

/// A separate "look it up online?" box for each thing the album is missing
/// (cover, artist, year, genre, track numbers), controlled by the two
/// switches in Settings > Online lookups.
class _MissingInfoPrompts extends StatefulWidget {
  final String albumKey;
  const _MissingInfoPrompts({required this.albumKey});

  /// Prompts the user said "not now" to, for this run of the app.
  static final Set<String> _dismissed = {};

  @override
  State<_MissingInfoPrompts> createState() => _MissingInfoPromptsState();
}

class _MissingInfoPromptsState extends State<_MissingInfoPrompts> {
  _Missing? _busy;

  String _key(_Missing m) => '${widget.albumKey}#${m.name}';

  Future<void> _find(_Missing m) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final album = lib.albumByKey(widget.albumKey);
    if (album == null) return;
    final ids = [for (final t in album.tracks) t.id];
    final artist = album.artist == 'Unknown Artist' ? '' : album.artist;

    if (m == _Missing.cover) {
      final path = await showCoverSearch(context, artist: artist, album: album.title);
      if (path == null || !mounted) return;
      setState(() => _busy = m);
      await lib.editMany(ids, TrackEdit(art: path));
    } else if (m == _Missing.trackNumbers) {
      final choice = await showInfoLookup(context,
          field: InfoField.trackNumber, songMode: false, artist: artist, album: album.title);
      final picked = choice?.album;
      if (picked == null || !mounted) return;
      setState(() => _busy = m);
      final search = MusicInfoSearch();
      try {
        final list = await search.tracklist(picked.id, preferTrackCount: album.tracks.length);
        final matched = MusicInfoSearch.matchTracks([for (final t in album.tracks) t.title], list);
        final changes = <String, TrackEdit>{
          for (var i = 0; i < album.tracks.length; i++)
            if (matched[i] != null)
              album.tracks[i].id: TrackEdit(trackNumber: matched[i]!.number, discNumber: matched[i]!.disc),
        };
        await lib.editTracks(changes);
        messenger?.showSnackBar(SnackBar(
          content: Text('Track numbers set for ${changes.length} of ${album.tracks.length} songs'
              '${changes.length < album.tracks.length ? ' (the rest didn\'t match by title)' : ''}'),
        ));
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t get the track list: $e')));
      } finally {
        search.close();
      }
    } else {
      final field = switch (m) {
        _Missing.artist => InfoField.artist,
        _Missing.year => InfoField.year,
        _ => InfoField.genre,
      };
      final choice = await showInfoLookup(context, field: field, songMode: false, artist: artist, album: album.title);
      if (choice == null || !mounted) return;
      setState(() => _busy = m);
      await lib.editMany(ids, switch (m) {
        _Missing.artist => TrackEdit(artist: choice.value, albumArtist: choice.value),
        _Missing.year => TrackEdit(year: int.tryParse(choice.value)),
        _ => TrackEdit(genre: choice.value),
      });
      // A new album artist regroups the album under a new key: follow it.
      final newKey = lib.byId(ids.first)?.albumKey;
      if (newKey != null && newKey != widget.albumKey && navigator.mounted) {
        navigator.pushReplacement(MaterialPageRoute(builder: (_) => AlbumScreen(albumKey: newKey)));
        return;
      }
    }
    if (mounted) setState(() => _busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final album = lib.albumByKey(widget.albumKey);
    if (album == null) return const SizedBox.shrink();
    final tracks = album.tracks;
    final noTrackNumbers = tracks.where((t) => t.trackNumber == null).length;

    final missing = <(_Missing, IconData, String, String)>[
      if (lib.onlineCovers && tracks.every((t) => t.art == null))
        (_Missing.cover, Icons.image_search, 'This album has no cover. Look for one online?', 'Find cover'),
      if (lib.onlineDetails && album.artist == 'Unknown Artist')
        (_Missing.artist, Icons.person_search, 'The artist is unknown. Look it up online?', 'Find artist'),
      if (lib.onlineDetails && tracks.every((t) => t.year == null))
        (_Missing.year, Icons.event, 'This album has no year. Look it up online?', 'Find year'),
      if (lib.onlineDetails && tracks.every((t) => t.genre == null))
        (_Missing.genre, Icons.category_outlined, 'This album has no genre. Look it up online?', 'Find genre'),
      if (lib.onlineDetails && noTrackNumbers > 0)
        (
          _Missing.trackNumbers,
          Icons.format_list_numbered,
          noTrackNumbers == tracks.length
              ? 'These songs have no track numbers. Look them up online?'
              : '$noTrackNumbers song${noTrackNumbers == 1 ? '' : 's'} have no track number. Look them up online?',
          'Find track numbers',
        ),
    ].where((x) => !_MissingInfoPrompts._dismissed.contains(_key(x.$1))).toList();

    if (missing.isEmpty) return const SizedBox.shrink();
    return Column(children: [
      for (final (kind, icon, text, action) in missing)
        Card(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          color: AppColors.surfaceHigh,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(children: [
              Icon(icon, color: AppColors.textDim),
              const SizedBox(width: 12),
              Expanded(child: Text(text)),
              _busy == kind
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton(onPressed: _busy != null ? null : () => _find(kind), child: Text(action)),
              IconButton(
                tooltip: 'Not now',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _MissingInfoPrompts._dismissed.add(_key(kind))),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 4),
    ]);
  }
}
