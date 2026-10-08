// The page for one audiobook series (0.1.75): its picture, name, author(s), how many books and
// how many are finished, Play / Continue (the next book that isn't finished), a favourite heart,
// Add to sidebar, Mark all as finished, then its books in reading order.
//
// Opened through AppNav.openSeries (a series card, the sidebar, or "Series" on a book's page).
// A series is the books sharing a series name (seriesNamed in state/book_index.dart), looked up
// on each build so a rescan or an edit shows at once.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/quick_links.dart';
import '../widgets/selectable_title.dart';
import '../widgets/series_card.dart';

class SeriesScreen extends StatelessWidget {
  final String name;
  const SeriesScreen({super.key, required this.name});

  /// "Book 2", "Book 2.5", or nothing for a book without a number.
  static String? numberOf(Book b) {
    final i = b.seriesIndex;
    if (i == null) return null;
    return 'Book ${i == i.roundToDouble() ? i.round() : i}';
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final playlists = context.watch<PlaylistsModel>();
    final series = seriesNamed(lib.books, name);
    if (series == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.collections_bookmark_outlined,
          title: 'Series not found',
          message: 'No audiobook in your library has this series any more.',
        ),
      );
    }
    final accent = Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width > 600;
    final progress = seriesProgress(series, listening);
    final nextState = listening.stateOf(progress.next);
    final fav = playlists.isFavouriteSeries(name);
    final n = series.books.length;

    final playLabel = progress.allFinished
        ? 'Listen again'
        : nextState == BookState.inProgress
        ? 'Continue ${progress.next.title}'
        : (progress.finished == 0 ? 'Play' : 'Play ${progress.next.title}');

    final info = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('AUDIOBOOK SERIES', style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: AppColors.textDim)),
        const SizedBox(height: 6),
        SelectableTitle(
          name,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          maxLines: 3,
          style: TextStyle(fontSize: wide ? 34 : 24, fontWeight: FontWeight.w800, height: 1.15),
        ),
        const SizedBox(height: 6),
        if (series.authors.isNotEmpty)
          Text(series.authors.join(', '), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          seriesCounts(series, listening),
          key: const ValueKey('series-counts'),
          style: TextStyle(color: AppColors.textDim),
        ),
        if (progress.finished > 0 && !progress.allFinished) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: AppShape.circular(2),
              child: LinearProgressIndicator(
                value: progress.finished / n,
                minHeight: 4,
                backgroundColor: AppColors.surfaceHigh,
              ),
            ),
          ),
        ],
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          key: const ValueKey('series-play'),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(playLabel, overflow: TextOverflow.ellipsis),
          onPressed: () => playSeries(context, series),
        ),
        IconButton(
          key: const ValueKey('series-favourite'),
          tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
          icon: Icon(fav ? Icons.favorite : Icons.favorite_border, color: fav ? accent : null),
          onPressed: () => playlists.setFavouriteSeries([name], !fav),
        ),
        // A quick link in the sidebar, like an album's or a collection's.
        QuickLinkButton(link: QuickLink(QuickLinkKind.series, name, name)),
        OutlinedButton.icon(
          key: const ValueKey('series-mark-all'),
          icon: Icon(progress.allFinished ? Icons.remove_done : Icons.done_all),
          label: Text(progress.allFinished ? 'Mark all as not finished' : 'Mark all as finished'),
          onPressed: () => markSeriesFinished(listening, series, !progress.allFinished),
        ),
      ],
    );

    final coverWidth = wide ? 200.0 : 180.0;
    final header = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [accent.withValues(alpha: 0.22), AppColors.bg],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: wide
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    BookCover(book: series.coverBook, width: coverWidth),
                    const SizedBox(width: 24),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 16),
                actions,
              ],
            )
          : Column(
              children: [
                BookCover(book: series.coverBook, width: coverWidth),
                const SizedBox(height: 16),
                info,
                const SizedBox(height: 12),
                actions,
              ],
            ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          Builder(
            builder: (button) => IconButton(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert),
              onPressed: () {
                final box = button.findRenderObject() as RenderBox;
                showSeriesMenu(button, series, box.localToGlobal(box.size.bottomCenter(Offset.zero)), onPage: true);
              },
            ),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: header),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                '$n book${n == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          // The books in reading order: number, cover, title, how far through, and play.
          SliverList.builder(
            itemCount: n,
            itemBuilder: (context, i) => _BookRow(book: series.books[i], next: series.books[i] == progress.next),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

/// One book in the series' list.
class _BookRow extends StatelessWidget {
  final Book book;

  /// The book Play / Continue starts, marked so it's easy to spot.
  final bool next;
  const _BookRow({required this.book, required this.next});

  @override
  Widget build(BuildContext context) {
    final listening = context.watch<ListeningModel>();
    final state = listening.stateOf(book);
    final accent = Theme.of(context).colorScheme.primary;
    final number = SeriesScreen.numberOf(book);
    final status = switch (state) {
      BookState.notStarted => formatLong(book.duration),
      BookState.inProgress => '${formatLong(listening.timeLeft(book))} left',
      BookState.finished => 'Finished',
    };
    return ListTile(
      key: ValueKey('series-book:${book.id}'),
      leading: BookCover(book: book, width: 48, radius: 4),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text([?number, status].join(' · '), style: TextStyle(color: next ? accent : AppColors.textDim)),
          if (state == BookState.inProgress)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: AppShape.circular(2),
                child: LinearProgressIndicator(
                  value: listening.fractionDone(book),
                  minHeight: 3,
                  backgroundColor: AppColors.surfaceHigh,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == BookState.finished) Icon(Icons.check_circle, color: accent, size: 20),
          IconButton(
            tooltip: state == BookState.inProgress ? 'Resume' : 'Play',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => context.read<PlayerModel>().playBook(book, fromStart: state == BookState.finished),
          ),
        ],
      ),
      onTap: () => context.read<AppNav>().openBook(book),
    );
  }
}
