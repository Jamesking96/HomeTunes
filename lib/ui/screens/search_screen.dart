// The Search tab: one search box that looks through songs, artists, albums, audiobooks,
// audiobook chapters, videos and video collections all at once, showing results as you type.
//
// The actual matching lives in LibraryModel (search / searchBooks / searchChapters, which use
// library_index.dart and book_index.dart) and video_filters.dart (searchVideos /
// searchCollections, 0.1.41). This page just holds the typed text and lays out the results as
// shelves (artists, albums, books, collections, videos) and lists (songs, chapters).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/library_index.dart';
import '../../models/book.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'video_collection_screen.dart' show CollectionCard, collectionCardHeight;
import 'videos_screen.dart' show VideoCard, videoCardHeight;
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/track_tile.dart';

/// The Search tab page.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  /// Width of the video and collection cards on their shelves.
  static const _cardWidth = 220.0;

  final _ctrl = TextEditingController();
  /// What's been typed so far. Each keystroke rebuilds the page and re-runs the search.
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    // Run all the searches for the current text. The book searches return nothing for an empty
    // query, so they're cheap when the box is blank.
    final results = _query.trim().isEmpty ? SearchResults.empty : lib.search(_query);
    final books = lib.searchBooks(_query);
    final chapters = lib.searchChapters(_query);
    final ratio = bookCoverRatio(context);
    // Videos and their collections (0.1.41). Null in tests without the Videos tab's model.
    final videoModel = context.watch<VideoLibraryModel?>();
    final blank = _query.trim().isEmpty;
    final collections = videoModel == null || blank ? const <VideoCollection>[] : searchCollections(videoModel.collections, _query);
    final videos = videoModel == null || blank ? const <VideoItem>[] : searchVideos(videoModel.videos, _query);

    return Scaffold(
      // The search box sits in the app bar, with a clear (x) button once something's typed.
      appBar: AppBar(
        toolbarHeight: 72,
        title: TextField(
          controller: _ctrl,
          autofocus: false,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums, books, chapters or videos',
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
            border: OutlineInputBorder(borderRadius: AppShape.circular(28), borderSide: BorderSide.none),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
      // Body: a hint when nothing's typed, "no results" when nothing matched, else the results.
      body: _query.trim().isEmpty
          ? const EmptyState(
              icon: Icons.search,
              title: 'Search your library',
              message: 'Find songs, artists, albums, audiobooks and their chapters, videos and video collections.')
          : results.isEmpty && books.isEmpty && chapters.isEmpty && collections.isEmpty && videos.isEmpty
              ? EmptyState(icon: Icons.search_off, title: 'No results for "$_query"')
              : CustomScrollView(slivers: [
                  // Horizontal shelves first (artists, albums, audiobooks), capped at 12 each.
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
                        children: [
                          for (final a in results.albums.take(12))
                            AlbumCard(album: a, width: 160, scope: [for (final x in results.albums.take(12)) x.key]),
                        ],
                      ),
                    ),
                  if (books.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        title: 'Audiobooks',
                        height: bookCardHeight(150, ratio),
                        children: [
                          for (final b in books.take(12))
                            BookCard(book: b, width: 150, scope: [for (final x in books.take(12)) x.id]),
                        ],
                      ),
                    ),
                  // Video collections and videos (0.1.41): tap a collection for its page, a video
                  // to play it (both on the Videos tab).
                  if (collections.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        key: const ValueKey('search-collections'),
                        title: 'Video collections',
                        height: collections
                            .take(12)
                            .map((c) => collectionCardHeight(_cardWidth, videoModel!.collectionShapeOf(c)))
                            .reduce(math.max),
                        children: [
                          for (final c in collections.take(12))
                            SizedBox(
                              width: _cardWidth,
                              child: CollectionCard(
                                collection: c,
                                onTap: () => context.read<AppNav>().openVideoCollection(c.name),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (videos.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Shelf(
                        key: const ValueKey('search-videos'),
                        title: 'Videos',
                        height: videos
                            .take(12)
                            .map((v) => videoCardHeight(_cardWidth, videoModel!.shapeOf(v)))
                            .reduce(math.max),
                        children: [
                          for (final v in videos.take(12)) SizedBox(width: _cardWidth, child: VideoCard(video: v)),
                        ],
                      ),
                    ),
                  // Then the matching songs as a normal song list (tapping one plays the
                  // search results from there).
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
                  // And finally any audiobook chapters whose names matched.
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
    // Look up the chapter's name, which file ("part") it's in, and where it starts.
    final c = book.chapters[chapter];
    return ListTile(
      leading: SizedBox(width: 44, child: Center(child: BookCover(book: book, width: 40, radius: 4))),
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${book.title} · starts at ${formatElapsed(c.offset)}', maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.play_circle_outline),
      onTap: () {
        // If this book is already loaded, just jump to the chapter; otherwise start the book there.
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
