import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_index.dart';
import '../../models/book.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/track_tile.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final results = _query.trim().isEmpty ? SearchResults.empty : lib.search(_query);
    final books = lib.searchBooks(_query);
    final chapters = lib.searchChapters(_query);
    final ratio = bookCoverRatio(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: TextField(
          controller: _ctrl,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums, books or chapters',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            filled: true,
            fillColor: AppColors.surfaceHigh,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      body: _query.trim().isEmpty
          ? const EmptyState(
              icon: Icons.search, title: 'Search your library', message: 'Find songs, artists, albums, audiobooks and their chapters.')
          : results.isEmpty && books.isEmpty && chapters.isEmpty
              ? EmptyState(icon: Icons.search_off, title: 'No results for "$_query"')
              : CustomScrollView(slivers: [
                  if (results.artists.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        title: 'Artists',
                        height: 210,
                        children: [for (final a in results.artists.take(12)) ArtistCard(artist: a, width: 150)],
                      ),
                    ),
                  if (results.albums.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        title: 'Albums',
                        height: 220,
                        children: [for (final a in results.albums.take(12)) AlbumCard(album: a, width: 160)],
                      ),
                    ),
                  if (books.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        title: 'Audiobooks',
                        height: bookCardHeight(150, ratio),
                        children: [for (final b in books.take(12)) BookCard(book: b, width: 150)],
                      ),
                    ),
                  if (results.tracks.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                        child: Text('Songs', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: results.tracks.length,
                      itemBuilder: (_, i) => TrackTile(
                        track: results.tracks[i],
                        list: results.tracks,
                        index: i,
                        contextLabel: 'Search · $_query',
                      ),
                    ),
                  ],
                  if (chapters.isNotEmpty) ...[
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
                        child: Text('Audiobook chapters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    SliverList.builder(
                      itemCount: chapters.length,
                      itemBuilder: (_, i) => _ChapterResult(book: chapters[i].book, chapter: chapters[i].chapter),
                    ),
                  ],
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ]),
    );
  }
}

/// A chapter found by search: tap to play the book from there.
class _ChapterResult extends StatelessWidget {
  final Book book;
  final int chapter;
  const _ChapterResult({required this.book, required this.chapter});

  @override
  Widget build(BuildContext context) {
    final c = book.chapters[chapter];
    return ListTile(
      leading: SizedBox(width: 44, child: Center(child: BookCover(book: book, width: 40, radius: 4))),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${book.title} · starts at ${formatElapsed(c.offset)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.play_circle_outline),
      onTap: () {
        final player = context.read<PlayerModel>();
        if (player.book?.id == book.id) {
          player.goToChapter(chapter);
          if (!player.playing) player.play();
        } else {
          player.playBook(book, partIndex: c.part, at: c.start);
        }
      },
    );
  }
}
