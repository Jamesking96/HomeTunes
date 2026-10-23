// The TV's Search screen (0.2.0, step 6 of the TV interface; mockup "Search"). The remote has no
// letters, so the left of the screen is a keyboard: the letters, the digits, Space, Delete and
// Clear. The results on the right update with every key (artists, songs, albums, audiobooks,
// video collections, videos and audiobook chapters); → from the keyboard's right edge goes to
// them, ← from their left edge comes back. A real keyboard (or a remote's number keys) types too.
//
// The matching is the phone's (LibraryModel.search / searchBooks / searchChapters and
// video_filters.dart); this screen only lays it out for the remote.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/video_item.dart';
import '../../state/library_model.dart';
import '../../state/player_model.dart';
import '../../state/video_filters.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart' show BookCover;
import 'tv_browse.dart';
import 'tv_detail.dart' show TvListHeading;
import 'tv_items.dart';
import 'tv_widgets.dart';

/// The Search tab's place in the menu.
const tvSearchTab = 1;

const tvSearchHints = <TvHint>[('OK', 'type'), ('→', 'results'), ('Hold OK', 'Options'), ('←', 'menu')];

/// The keyboard's keys, a row at a time: a–z then 1–0.
const tvKeyboardRows = [
  ['a', 'b', 'c', 'd', 'e', 'f'],
  ['g', 'h', 'i', 'j', 'k', 'l'],
  ['m', 'n', 'o', 'p', 'q', 'r'],
  ['s', 't', 'u', 'v', 'w', 'x'],
  ['y', 'z', '1', '2', '3', '4'],
  ['5', '6', '7', '8', '9', '0'],
];

class TvSearchScreen extends StatefulWidget {
  const TvSearchScreen({super.key});

  @override
  State<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends State<TvSearchScreen> {
  String _query = '';

  void _type(String s) => setState(() => _query += s);

  void _delete() {
    if (_query.isEmpty) return;
    setState(() => _query = _query.substring(0, _query.length - 1));
  }

  void _clear() => setState(() => _query = '');

  /// A real keyboard, or the remote's number keys, while the on-screen keyboard has focus.
  KeyEventResult _hardKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _delete();
      return KeyEventResult.handled;
    }
    final c = e.character?.toLowerCase();
    if (c != null && c.length == 1 && RegExp(r'[a-z0-9 ]').hasMatch(c)) {
      // A space at the start does nothing (it would find everything with a space in it).
      if (c != ' ' || _query.isNotEmpty) _type(c);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return TvPageHints(
      tab: tvSearchTab,
      hints: tvSearchHints,
      child: TvPage(
        title: 'Search',
        body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _hardKey,
            child: _Keyboard(query: _query, onType: _type, onDelete: _delete, onClear: _clear),
          ),
          const SizedBox(width: 28),
          Expanded(child: TvSearchResults(query: _query)),
        ]),
      ),
    );
  }
}

/// The typed text over the keys.
class _Keyboard extends StatelessWidget {
  const _Keyboard({required this.query, required this.onType, required this.onDelete, required this.onClear});
  final String query;
  final ValueChanged<String> onType;
  final VoidCallback onDelete, onClear;

  static const _key = 42.0, _gap = 6.0;
  static const width = _key * 6 + _gap * 5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          key: const ValueKey('tv-search-text'),
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.search, size: 20, color: AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: query.isEmpty
                  ? Text('Type to search', style: TextStyle(fontSize: 16, color: AppColors.textDim))
                  : Text('$query|',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        for (final row in tvKeyboardRows) ...[
          Row(children: [
            for (var i = 0; i < row.length; i++) ...[
              if (i > 0) const SizedBox(width: _gap),
              _Key(label: row[i], width: _key, onPressed: () => onType(row[i])),
            ],
          ]),
          const SizedBox(height: _gap),
        ],
        Row(children: [
          _Key(label: 'Space', width: _key * 2 + _gap, onPressed: query.isEmpty ? null : () => onType(' ')),
          const SizedBox(width: _gap),
          _Key(label: 'Delete', icon: Icons.backspace_outlined, width: _key * 2 + _gap, onPressed: onDelete, onHold: onClear),
          const SizedBox(width: _gap),
          _Key(label: 'Clear', width: _key * 2 + _gap, onPressed: onClear),
        ]),
      ]),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.width, required this.onPressed, this.icon, this.onHold});
  final String label;
  final IconData? icon;
  final double width;
  final VoidCallback? onPressed, onHold;

  @override
  Widget build(BuildContext context) {
    // Space with nothing typed yet still takes focus (so the row doesn't jump about), just dimmed.
    final enabled = onPressed != null;
    return TvPressable(
      key: ValueKey('tv-key-$label'),
      semanticLabel: label,
      onPressed: onPressed ?? () {},
      onHold: onHold,
      builder: (context, focused) => TvFocusFrame(
        focused: focused,
        radius: 8,
        grow: false,
        child: Container(
          width: width,
          height: 40,
          alignment: Alignment.center,
          color: focused ? AppColors.accent : AppColors.surfaceHigh,
          child: icon != null
              ? Icon(icon, size: 18, color: focused ? AppColors.current.onAccent : Colors.white)
              : Text(
                  label.length == 1 ? label.toUpperCase() : label,
                  style: TextStyle(
                    fontSize: label.length == 1 ? 17 : 13,
                    fontWeight: FontWeight.w600,
                    color: focused ? AppColors.current.onAccent : (enabled ? Colors.white : AppColors.textDim),
                  ),
                ),
        ),
      ),
    );
  }
}

/// What matches [query]: shelves of tiles and lists of rows, best first.
class TvSearchResults extends StatelessWidget {
  const TvSearchResults({super.key, required this.query});
  final String query;

  /// How many of each kind are shown (the phone's shelves stop at 12 too).
  static const most = 12;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final videoModel = context.watch<VideoLibraryModel?>();
    final q = query.trim();
    if (q.isEmpty) {
      return const TvEmpty(
        icon: Icons.search,
        title: 'Search your library',
        message: 'Songs, artists, albums, audiobooks and their chapters, videos and video collections. The results show as you type.',
      );
    }
    final results = lib.search(q);
    final books = lib.searchBooks(q);
    final chapters = lib.searchChapters(q);
    final collections = videoModel == null ? const <VideoCollection>[] : searchCollections(videoModel.collections, q);
    final videos = videoModel == null ? const <VideoItem>[] : searchVideos(videoModel.videos, q);
    if (results.isEmpty && books.isEmpty && chapters.isEmpty && collections.isEmpty && videos.isEmpty) {
      return TvEmpty(icon: Icons.search_off, title: 'Nothing found for "$q"', message: 'Try fewer letters, or part of a name.');
    }
    final songs = results.tracks.take(most).toList();
    final label = 'Search · $q';
    final bookAspect = tvBookAspect(context);
    Widget gap() => const SizedBox(height: 14);
    return ListView(
      key: const ValueKey('tv-search-results'),
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
      clipBehavior: Clip.none,
      children: [
        if (results.artists.isNotEmpty) ...[
          TvShelf(
            key: const ValueKey('tv-search-artists'),
            title: 'Artists',
            children: [for (final a in results.artists.take(most)) tvArtistTile(context, a, width: 104)],
          ),
          gap(),
        ],
        if (songs.isNotEmpty) ...[
          TvListHeading(results.tracks.length > most ? 'Songs · ${results.tracks.length}' : 'Songs'),
          for (var i = 0; i < songs.length; i++)
            // Playing one plays all the songs found, from there.
            tvSongRow(context, songs[i], list: results.tracks, index: i, label: label),
          gap(),
        ],
        if (results.albums.isNotEmpty) ...[
          TvShelf(
            key: const ValueKey('tv-search-albums'),
            title: 'Albums',
            children: [for (final a in results.albums.take(most)) tvAlbumTile(context, a, width: 120)],
          ),
          gap(),
        ],
        if (books.isNotEmpty) ...[
          TvShelf(
            key: const ValueKey('tv-search-books'),
            title: 'Audiobooks',
            children: [for (final b in books.take(most)) tvBookTile(context, b, width: 110, aspectRatio: bookAspect)],
          ),
          gap(),
        ],
        if (collections.isNotEmpty) ...[
          TvShelf(
            key: const ValueKey('tv-search-collections'),
            title: 'Video collections',
            children: [for (final c in collections.take(most)) tvCollectionTile(context, c, width: 130)],
          ),
          gap(),
        ],
        if (videos.isNotEmpty) ...[
          TvShelf(
            key: const ValueKey('tv-search-videos'),
            title: 'Videos',
            children: [for (final v in videos.take(most)) tvVideoTile(context, v, width: 180)],
          ),
          gap(),
        ],
        if (chapters.isNotEmpty) ...[
          const TvListHeading('Audiobook chapters'),
          for (final c in chapters.take(most)) _ChapterRow(book: c.book, chapter: c.chapter),
        ],
      ],
    );
  }
}

/// A chapter found by search: OK plays the book from there.
class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.book, required this.chapter});
  final Book book;
  final int chapter;

  @override
  Widget build(BuildContext context) {
    final c = book.chapters[chapter];
    return TvRow(
      key: ValueKey('tv-chapter:${book.id}:$chapter'),
      leading: BookCover(book: book, width: 40, radius: 4),
      title: c.title,
      subtitle: '${book.title} · starts at ${formatElapsed(c.offset)}',
      trailing: const Icon(Icons.play_circle_outline),
      onPressed: () {
        final player = context.read<PlayerModel>();
        if (player.book?.id == book.id) {
          player.goToChapter(chapter);
          if (!player.playing) player.play();
        } else {
          player.playBook(book, partIndex: c.part, at: c.start);
        }
      },
      onHold: () => showBookOptions(context, book),
    );
  }
}
