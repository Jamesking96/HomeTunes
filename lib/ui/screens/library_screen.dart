// The Library tab ("Your Library"): four swipeable tabs listing playlists, artists, albums
// and every song. There's also a + button to create a new playlist.
//
// HomeTunes (0.1.18): the Artists, Albums and Songs tabs can be narrowed down like the Books
// tab: a box to filter by title, All / Favourites (or Liked) chips, a filter sheet (artist,
// album, genre, decade) and a sort menu. The sorting and filtering is in
// state/music_filters.dart; each tab remembers its choices while the app is open.
//
// Each tab is its own small widget that watches LibraryModel / PlaylistsModel, so only the
// visible tab's list is built. Tapping an item opens its page through AppNav, which pushes it
// on this tab's own navigator (so the bottom bar stays in place).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../state/library_model.dart';
import '../../state/music_filters.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/artwork.dart';
import '../widgets/cards.dart';
import '../widgets/music_filter_sheet.dart';
import '../widgets/track_tile.dart';

/// Tabs: Playlists · Artists · Albums · Songs.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = context.read<AppNav>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Your Library', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'New playlist',
              icon: const Icon(Icons.add),
              // Ask for a name, create the playlist, then open it straight away.
              onPressed: () async {
                final name = await askForName(context, title: 'New playlist');
                if (name != null && context.mounted) {
                  nav.openPlaylist(context.read<PlaylistsModel>().create(name));
                }
              },
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Playlists'), Tab(text: 'Artists'), Tab(text: 'Albums'), Tab(text: 'Songs')],
          ),
        ),
        body: const TabBarView(children: [_PlaylistsTab(), _ArtistsTab(), _AlbumsTab(), _SongsTab()]),
      ),
    );
  }
}

/// Liked Songs (always first) followed by the user's playlists.
class _PlaylistsTab extends StatelessWidget {
  const _PlaylistsTab();

  @override
  Widget build(BuildContext context) {
    final pl = context.watch<PlaylistsModel>();
    final lib = context.watch<LibraryModel>();
    final nav = context.read<AppNav>();
    final accent = Theme.of(context).colorScheme.primary;
    return ListView(children: [
      // Liked Songs gets a gradient tile in the accent colour instead of a cover.
      ListTile(
        leading: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            gradient: LinearGradient(colors: [accent, accent.withValues(alpha: 0.35)]),
          ),
          child: const Icon(Icons.favorite, color: Colors.white),
        ),
        title: const Text('Liked Songs', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${pl.liked.length} songs'),
        onTap: nav.openLiked,
      ),
      for (final p in pl.playlists)
        ListTile(
          leading: Artwork(
            track: p.trackIds.isEmpty ? null : lib.byId(p.trackIds.first),
            size: 52,
            placeholder: Icons.queue_music,
          ),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('Playlist · ${p.trackIds.length} songs'),
          onTap: () => nav.openPlaylist(p),
        ),
      if (pl.playlists.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Create a playlist with the + button above.', style: TextStyle(color: AppColors.textDim)),
        ),
    ]);
  }
}

/// What the Artists, Albums and Songs tabs share: the title box, the picked filters, the
/// Favourites chip and the chip row. Kept alive so swiping between tabs keeps the choices.
abstract class _FilteredTabState<W extends StatefulWidget> extends State<W> with AutomaticKeepAliveClientMixin {
  final search = TextEditingController();
  String query = '';
  MusicFilters filters = MusicFilters.none;
  bool favouritesOnly = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  void setQuery(String v) => setState(() => query = v);

  /// Forgets the typed title, the picked filters and the Favourites chip.
  void clearAll() => setState(() {
        search.clear();
        query = '';
        filters = MusicFilters.none;
        favouritesOnly = false;
      });

  bool get narrowed => query.trim().isNotEmpty || !filters.isEmpty || favouritesOnly;

  /// Opens the filter sheet over [items] and keeps what's picked.
  Future<void> chooseFilters<T>(List<T> items, List<FilterField<T>> fields, String showLabel) async {
    final picked = await showMusicFilterSheet<T>(
      context,
      items: items,
      fields: fields,
      current: filters,
      showLabel: showLabel,
    );
    if (picked != null && mounted) setState(() => filters = picked);
  }

  /// All / Favourites chips with counts, then one removable chip per picked filter.
  Widget chipRow({
    required int all,
    required int favourites,
    required String favouritesLabel,
    required VoidCallback onEditFilters,
  }) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          ChoiceChip(
            label: Text('All ($all)'),
            selected: !favouritesOnly,
            onSelected: (_) => setState(() => favouritesOnly = false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            key: const ValueKey('library-favourites'),
            avatar: const Icon(Icons.favorite, size: 16),
            label: Text('$favouritesLabel ($favourites)'),
            selected: favouritesOnly,
            onSelected: (_) => setState(() => favouritesOnly = true),
          ),
          for (final e in filters.picked.entries)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: InputChip(
                avatar: const Icon(Icons.filter_list, size: 16),
                label: Text('${e.key}: ${e.value}'),
                onPressed: onEditFilters,
                onDeleted: () => setState(() => filters = filters.withValue(e.key, null)),
              ),
            ),
        ],
      ),
    );
  }

  /// Shown when nothing passes the title box, chips and filters.
  Widget noMatches(String what) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('No $what match.', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
          const SizedBox(height: 8),
          TextButton(onPressed: clearAll, child: const Text('Clear filters')),
        ]),
      );
}

/// Every artist (grouped by album artist), with a round picture from their first album.
class _ArtistsTab extends StatefulWidget {
  const _ArtistsTab();

  @override
  State<_ArtistsTab> createState() => _ArtistsTabState();
}

class _ArtistsTabState extends _FilteredTabState<_ArtistsTab> {
  ArtistSort _sort = ArtistSort.name;

  static String _sortLabel(ArtistSort s) => switch (s) {
        ArtistSort.name => 'Name (A–Z)',
        ArtistSort.nameDescending => 'Name (Z–A)',
        ArtistSort.mostAlbums => 'Most albums',
        ArtistSort.mostSongs => 'Most songs',
        ArtistSort.recentlyAdded => 'Recently added',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = context.watch<LibraryModel>();
    final playlists = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();
    if (lib.artists.isEmpty) return const EmptyState(icon: Icons.person_outline, title: 'No artists yet');
    // An artist is a favourite when one of their albums is, or one of their songs is liked.
    bool favourite(Artist a) => a.albums.any(playlists.isFavouriteAlbum) || a.tracks.any(playlists.isLiked);
    final passing = [
      for (final a in lib.artists)
        if (titleMatches(a.name, query) && filters.matches(a, artistFields)) a
    ];
    final favourites = passing.where(favourite).toList();
    final shown = sortArtists(favouritesOnly ? favourites : passing, _sort);
    void edit() => chooseFilters(lib.artists, artistFields, 'Show artists');
    return Column(children: [
      MusicFilterBar<ArtistSort>(
        controller: search,
        hint: 'Filter by artist name',
        onChanged: setQuery,
        filtersActive: !filters.isEmpty,
        onFilter: edit,
        sort: _sort,
        sorts: ArtistSort.values,
        sortLabel: _sortLabel,
        onSort: (s) => setState(() => _sort = s),
      ),
      chipRow(all: passing.length, favourites: favourites.length, favouritesLabel: 'Favourites', onEditFilters: edit),
      Expanded(
        child: shown.isEmpty
            ? SingleChildScrollView(child: noMatches('artists'))
            // .builder only builds the rows on screen, which keeps big libraries smooth.
            : ListView.builder(
                itemCount: shown.length,
                itemBuilder: (_, i) {
                  final a = shown[i];
                  final songs = a.tracks.length;
                  return ListTile(
                    leading: Artwork(
                      track: a.albums.first.artTrack,
                      size: 52,
                      radius: 26,
                      placeholder: Icons.person,
                    ),
                    title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${a.albums.length} album${a.albums.length == 1 ? '' : 's'} · '
                        '$songs song${songs == 1 ? '' : 's'}'),
                    onTap: () => nav.openArtist(a.name),
                  );
                },
              ),
      ),
    ]);
  }
}

/// A grid of every album's cover card.
class _AlbumsTab extends StatefulWidget {
  const _AlbumsTab();

  @override
  State<_AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends _FilteredTabState<_AlbumsTab> {
  AlbumSort _sort = AlbumSort.artist;

  static String _sortLabel(AlbumSort s) => switch (s) {
        AlbumSort.artist => 'Artist',
        AlbumSort.title => 'Title',
        AlbumSort.newest => 'Year (newest first)',
        AlbumSort.oldest => 'Year (oldest first)',
        AlbumSort.recentlyAdded => 'Recently added',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = context.watch<LibraryModel>();
    final playlists = context.watch<PlaylistsModel>();
    if (lib.albums.isEmpty) return const EmptyState(icon: Icons.album_outlined, title: 'No albums yet');
    final passing = [
      for (final a in lib.albums)
        if (titleMatches(a.title, query) && filters.matches(a, albumFields)) a
    ];
    final favourites = passing.where(playlists.isFavouriteAlbum).toList();
    final groups = sortAlbums(favouritesOnly ? favourites : passing, _sort);
    // Everything shown, in the order shown (for the cards' "select all" and play scope).
    final keys = [for (final (_, g) in groups) for (final a in g) a.key];
    void edit() => chooseFilters(lib.albums, albumFields, 'Show albums');

    Widget body;
    if (keys.isEmpty) {
      // No favourites at all yet gets the how-to message; otherwise nothing matched.
      final noFavouritesYet = favouritesOnly && !lib.albums.any(playlists.isFavouriteAlbum);
      body = noFavouritesYet
          ? const EmptyState(
              icon: Icons.favorite_border,
              title: 'No favourite albums yet',
              message: 'Tap the heart on an album\'s page, or right-click (press and hold on a phone) an album '
                  'and choose Add to favourites.',
            )
          : SingleChildScrollView(child: noMatches('albums'));
    } else {
      body = LayoutBuilder(builder: (context, c) {
        final grid = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridColumns(c.maxWidth),
          childAspectRatio: 0.78,
        );
        return CustomScrollView(slivers: [
          // One optional heading (the decade, for the year sorts) + grid per group.
          for (final (header, albums) in groups) ...[
            if (header != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverGrid.builder(
                gridDelegate: grid,
                itemCount: albums.length,
                itemBuilder: (_, i) => AlbumCard(album: albums[i], scope: keys),
              ),
            ),
          ],
        ]);
      });
    }

    return Column(children: [
      MusicFilterBar<AlbumSort>(
        controller: search,
        hint: 'Filter by album title',
        onChanged: setQuery,
        filtersActive: !filters.isEmpty,
        onFilter: edit,
        sort: _sort,
        sorts: AlbumSort.values,
        sortLabel: _sortLabel,
        onSort: (s) => setState(() => _sort = s),
      ),
      chipRow(all: passing.length, favourites: favourites.length, favouritesLabel: 'Favourites', onEditFilters: edit),
      Expanded(child: body),
    ]);
  }
}

/// Every song, with a Shuffle button for the songs shown.
class _SongsTab extends StatefulWidget {
  const _SongsTab();

  @override
  State<_SongsTab> createState() => _SongsTabState();
}

class _SongsTabState extends _FilteredTabState<_SongsTab> {
  SongSort _sort = SongSort.title;

  static String _sortLabel(SongSort s) => switch (s) {
        SongSort.title => 'Title',
        SongSort.artist => 'Artist',
        SongSort.album => 'Album',
        SongSort.newest => 'Year (newest first)',
        SongSort.recentlyAdded => 'Recently added',
        SongSort.longest => 'Longest first',
      };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = context.watch<LibraryModel>();
    final playlists = context.watch<PlaylistsModel>();
    if (lib.tracks.isEmpty) return const EmptyState(icon: Icons.music_note_outlined, title: 'No songs yet');
    // songsByTitle is worked out once per library change, so the default sort costs nothing.
    final passing = [
      for (final t in lib.songsByTitle)
        if (titleMatches(t.title, query) && filters.matches(t, songFields)) t
    ];
    final liked = passing.where(playlists.isLiked).toList();
    final picked = favouritesOnly ? liked : passing;
    final songs = _sort == SongSort.title ? picked : sortSongs(picked, _sort);
    final label = narrowed ? 'Songs' : 'All songs';
    void edit() => chooseFilters(lib.tracks, songFields, 'Show songs');
    return Column(children: [
      MusicFilterBar<SongSort>(
        controller: search,
        hint: 'Filter by song title',
        onChanged: setQuery,
        filtersActive: !filters.isEmpty,
        onFilter: edit,
        sort: _sort,
        sorts: SongSort.values,
        sortLabel: _sortLabel,
        onSort: (s) => setState(() => _sort = s),
      ),
      chipRow(all: passing.length, favourites: liked.length, favouritesLabel: 'Liked', onEditFilters: edit),
      Expanded(
        child: songs.isEmpty
            ? SingleChildScrollView(child: noMatches('songs'))
            : ListView.builder(
                // One extra row at the top for the song count and Shuffle button, so rows are shifted by one.
                itemCount: songs.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      child: Row(children: [
                        Text('${songs.length} song${songs.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: AppColors.textDim)),
                        const Spacer(),
                        FilledButton.icon(
                          icon: const Icon(Icons.shuffle),
                          label: const Text('Shuffle'),
                          onPressed: () => context.read<PlayerModel>().shufflePlay(songs, label: label),
                        ),
                      ]),
                    );
                  }
                  return TrackTile(track: songs[i - 1], list: songs, index: i - 1, contextLabel: label);
                },
              ),
      ),
    ]);
  }
}
