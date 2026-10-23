// The TV's audiobook pages (0.2.0, step 3 of the TV interface): a book and a series.
//  * A book: its cover, author, narrator / series / year / length, where you are (time left and a
//    bar), Play / Resume / Pause / Listen again, Play from the start, the heart, and its
//    description; then its bookmarks and chapters as big rows. OK on a chapter or bookmark plays
//    from there (inside the book if it's the one playing).
//  * A series: its picture, authors, how many books are finished, Play / Continue (the next book
//    that isn't finished) and the heart; then its books in order. OK opens a book's page.
// In TV mode AppNav opens these instead of the usual pages.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/bookmarks_model.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/book_card.dart' show BookCover, bookCoverRatio;
import '../widgets/series_card.dart' show SeriesCover, seriesProgress, seriesCounts;
import 'tv_browse.dart';
import 'tv_detail.dart';
import 'tv_items.dart';
import 'tv_options.dart';
import 'tv_widgets.dart';

/// One row of a book's page: a heading, a bookmark or a chapter.
sealed class _BookRow {}

class _Heading extends _BookRow {
  _Heading(this.text);
  final String text;
}

class _Mark extends _BookRow {
  _Mark(this.bookmark);
  final Bookmark bookmark;
}

class _Chapter extends _BookRow {
  _Chapter(this.index, this.chapter, this.length);
  final int index;
  final BookChapter chapter;
  final Duration length;
}

class TvBookPage extends StatelessWidget {
  const TvBookPage({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final book = lib.bookById(bookId);
    if (book == null) return const TvMissingPage(icon: Icons.menu_book_outlined, title: 'This audiobook isn\'t in your library any more');
    final pl = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();
    final player = context.read<PlayerModel>();
    // Only these two facts about the player, so the page doesn't redraw on every tick.
    final playingThis = context.select<PlayerModel, bool>((p) => p.book?.id == bookId);
    final isPlaying = context.select<PlayerModel, bool>((p) => p.book?.id == bookId && p.playing);
    final state = listening.stateOf(book);
    final progress = listening.progressFor(book);
    final chapters = book.chapters;
    final bookmarks = context.watch<BookmarksModel>().forBook(book);
    final current = _currentChapter(book, chapters, progress);
    final fav = pl.isFavouriteBook(book);
    final series = book.series;
    final ratio = bookCoverRatio(context);

    final status = switch (state) {
      BookState.notStarted => 'Not started',
      BookState.finished => 'Finished',
      BookState.inProgress => '${formatLong(listening.timeLeft(book))} left · ${(listening.fractionDone(book) * 100).round()}%',
    };
    final mainLabel = playingThis
        ? (isPlaying ? 'Pause' : 'Resume')
        : switch (state) {
            BookState.notStarted => 'Play',
            BookState.inProgress => 'Resume',
            BookState.finished => 'Listen again',
          };

    final rows = <_BookRow>[
      if (bookmarks.isNotEmpty) _Heading('${bookmarks.length} bookmark${bookmarks.length == 1 ? '' : 's'}'),
      for (final b in bookmarks) _Mark(b),
      if (chapters.isNotEmpty) _Heading('${chapters.length} chapter${chapters.length == 1 ? '' : 's'}'),
      for (var i = 0; i < chapters.length; i++)
        _Chapter(i, chapters[i], (i + 1 < chapters.length ? chapters[i + 1].offset : book.duration) - chapters[i].offset),
    ];

    return TvDetailPage<_BookRow>(
      itemHeight: 56,
      header: TvDetailHeader(
        picture: BookCover(book: book, width: 150, radius: 0),
        pictureWidth: 150,
        aspectRatio: 1 / ratio,
        kind: 'Audiobook',
        title: book.title,
        lines: [
          book.author,
          [
            if (book.narrator != null) 'Read by ${book.narrator}',
            ?book.seriesLabel,
            if (book.year != null) '${book.year}',
            formatLong(book.duration),
          ].join(' · '),
          status,
        ],
        buttons: [
          TvButton(
            key: const ValueKey('tv-page-play'),
            label: mainLabel,
            icon: isPlaying ? Icons.pause : Icons.play_arrow,
            primary: true,
            onPressed: () => playingThis ? player.togglePlay() : player.playBook(book, fromStart: state == BookState.finished),
          ),
          if (state == BookState.inProgress)
            TvButton(label: 'From the start', icon: Icons.replay, onPressed: () => player.playBook(book, fromStart: true)),
          TvIconButton(
            icon: fav ? Icons.favorite : Icons.favorite_border,
            label: fav ? 'Remove from favourites' : 'Add to favourites',
            on: fav,
            onPressed: () => pl.setFavouriteBooks([book], !fav),
          ),
          TvIconButton(
            icon: Icons.more_horiz,
            label: 'More options',
            onPressed: () => showTvOptions(context, title: book.title, subtitle: book.author, options: [
              if (series != null && series.trim().isNotEmpty)
                TvOption('Go to the series', Icons.collections_bookmark_outlined, () => nav.openSeries(series)),
              if (state != BookState.finished)
                TvOption('Mark as finished', Icons.done_all, () => listening.setFinished(book, true))
              else
                TvOption('Mark as not finished', Icons.remove_done, () => listening.setFinished(book, false)),
            ]),
          ),
        ],
        below: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (state == BookState.inProgress) TvProgressBar(listening.fractionDone(book)),
          if (book.description != null) ...[
            if (state == BookState.inProgress) const SizedBox(height: 12),
            TvDescription(book.description!),
          ],
        ]),
      ),
      items: rows,
      itemBuilder: (context, row, i, node) => switch (row) {
        _Heading(:final text) => TvListHeading(text),
        _Mark(:final bookmark) => TvRow(
            key: ValueKey('tv-bookmark:${bookmark.id}'),
            focusNode: node,
            height: 56,
            leading: const Icon(Icons.bookmark_outline),
            title: bookmark.note.trim().isEmpty ? 'Bookmark' : bookmark.note.trim(),
            subtitle: 'At ${formatElapsed(book.offsetOf(book.indexOfPart(bookmark.partId).clamp(0, book.parts.length - 1), bookmark.position))}',
            onPressed: () {
              final part = book.indexOfPart(bookmark.partId);
              if (part >= 0) player.playBook(book, partIndex: part, at: bookmark.position);
            },
          ),
        _Chapter(:final index, :final chapter, :final length) => TvRow(
            key: ValueKey('tv-chapter:$index'),
            focusNode: node,
            height: 56,
            highlight: index == current,
            leading: SizedBox(
              width: 28,
              child: index == current
                  ? Icon(isPlaying ? Icons.graphic_eq : Icons.bookmark, color: AppColors.accent)
                  : Text('${index + 1}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textDim)),
            ),
            title: chapter.title,
            subtitle: 'Starts at ${formatElapsed(chapter.offset)}',
            trailing: Text(formatDuration(length)),
            onPressed: () => playingThis ? player.goToChapter(index) : player.playBook(book, partIndex: chapter.part, at: chapter.start),
          ),
      },
    );
  }

  /// The chapter the saved place is in, or -1 (as the usual book page works it out).
  static int _currentChapter(Book book, List<BookChapter> chapters, BookProgress? progress) {
    if (progress == null || progress.finished) return -1;
    final part = book.indexOfPart(progress.partId);
    if (part < 0) return -1;
    final at = book.offsetOf(part, progress.position);
    var found = -1;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].offset <= at) found = i;
    }
    return found;
  }
}

class TvSeriesPage extends StatelessWidget {
  const TvSeriesPage({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final pl = context.watch<PlaylistsModel>();
    final player = context.read<PlayerModel>();
    final nav = context.read<AppNav>();
    final series = seriesNamed(lib.books, name);
    if (series == null) return const TvMissingPage(icon: Icons.collections_bookmark_outlined, title: 'No audiobook has this series any more');
    final progress = seriesProgress(series, listening);
    final nextState = listening.stateOf(progress.next);
    final fav = pl.isFavouriteSeries(name);
    final description = lib.seriesDescription(name);
    final ratio = bookCoverRatio(context);
    final playLabel = progress.allFinished
        ? 'Listen again'
        : nextState == BookState.inProgress
            ? 'Continue ${progress.next.title}'
            : (progress.finished == 0 ? 'Play' : 'Play ${progress.next.title}');

    return TvDetailPage<Book>(
      itemHeight: 64,
      header: TvDetailHeader(
        picture: SeriesCover(series: series, width: 150, radius: 0),
        pictureWidth: 150,
        aspectRatio: 1 / ratio,
        kind: 'Audiobook series',
        title: name,
        lines: [series.authors.join(', '), seriesCounts(series, listening)],
        buttons: [
          TvButton(
            key: const ValueKey('tv-page-play'),
            label: playLabel,
            icon: Icons.play_arrow,
            primary: true,
            onPressed: () => player.playBook(progress.next, fromStart: progress.allFinished),
          ),
          TvIconButton(
            icon: fav ? Icons.favorite : Icons.favorite_border,
            label: fav ? 'Remove from favourites' : 'Add to favourites',
            on: fav,
            onPressed: () => pl.setFavouriteSeries([name], !fav),
          ),
        ],
        below: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (progress.finished > 0 && !progress.allFinished) TvProgressBar(progress.finished / series.books.length),
          if (description != null) ...[const SizedBox(height: 12), TvDescription(description)],
        ]),
      ),
      items: series.books,
      itemBuilder: (context, b, i, node) {
        final state = listening.stateOf(b);
        final detail = [
          b.author,
          switch (state) {
            BookState.notStarted => 'Not started',
            BookState.finished => 'Finished',
            BookState.inProgress => '${(listening.fractionDone(b) * 100).round()}% · ${formatLong(listening.timeLeft(b))} left',
          },
        ].join(' · ');
        return TvRow(
          key: ValueKey('tv-book:${b.id}'),
          focusNode: node,
          height: 64,
          highlight: b == progress.next && !progress.allFinished,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(width: 48 / ratio, height: 48, child: BookCover(book: b, width: 48 / ratio, radius: 0)),
          ),
          title: b.seriesIndex == null ? b.title : 'Book ${_number(b.seriesIndex!)} · ${b.title}',
          subtitle: detail,
          trailing: Text(formatLong(b.duration)),
          focusedHint: 'Hold OK for options',
          onPressed: () => nav.openBook(b),
          onHold: () => showBookOptions(context, b),
        );
      },
    );
  }

  static String _number(double n) => n == n.roundToDouble() ? '${n.round()}' : '$n';
}
