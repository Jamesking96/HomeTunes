// Audiobook series (0.1.75, the user: "allow for the favouriting and adding audiobook series to
// be connected to the sidebar"): the card on the Audiobooks Series and Favourites tabs, and the
// menu shared by the card (right-click / press and hold) and the series page.
//
// A series is the books that share a series name (BookSeries in state/book_index.dart).
// Favourite series are kept by name in playlists.json (PlaylistsModel.favouriteSeries); a series
// in the sidebar is a QuickLink of kind series.
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
import 'book_card.dart';
import 'quick_links.dart';

/// How far through [s] you are: books finished, and the book to play next (the first one in
/// order that isn't finished; the first book once they all are).
({int finished, Book next, bool allFinished}) seriesProgress(BookSeries s, ListeningModel l) {
  final finished = s.books.where((b) => l.stateOf(b) == BookState.finished).length;
  final next = s.books.firstWhere((b) => l.stateOf(b) != BookState.finished, orElse: () => s.books.first);
  return (finished: finished, next: next, allFinished: finished == s.books.length);
}

/// "3 books · 1 finished".
String seriesCounts(BookSeries s, ListeningModel l) {
  final n = s.books.length;
  final done = seriesProgress(s, l).finished;
  return '$n book${n == 1 ? '' : 's'}${done == 0 ? '' : ' · ${done == n ? 'all' : '$done'} finished'}';
}

/// Plays the next book of [s] (carrying on where you left off).
Future<void> playSeries(BuildContext context, BookSeries s) {
  final p = seriesProgress(s, context.read<ListeningModel>());
  return context.read<PlayerModel>().playBook(p.next, fromStart: p.allFinished);
}

/// Every book in [s] finished, or none.
Future<void> markSeriesFinished(ListeningModel l, BookSeries s, bool finished) async {
  for (final b in s.books) {
    await l.setFinished(b, finished);
  }
}

/// The series menu at [at]: Open, Play / Continue, favourites, sidebar, Mark all as finished.
/// [onPage] leaves out "Open series page" (it's already open).
Future<void> showSeriesMenu(BuildContext context, BookSeries s, Offset at, {bool onPage = false}) async {
  final playlists = context.read<PlaylistsModel>();
  final lib = context.read<LibraryModel>();
  final listening = context.read<ListeningModel>();
  final nav = context.read<AppNav>();
  final fav = playlists.isFavouriteSeries(s.name);
  final inSidebar = lib.isQuickLink(QuickLinkKind.series, s.name);
  final progress = seriesProgress(s, listening);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  PopupMenuItem<VoidCallback> item(String key, IconData icon, String text, VoidCallback run) => PopupMenuItem(
    key: ValueKey('series-menu-$key'),
    value: run,
    child: ListTile(leading: Icon(icon), title: Text(text), contentPadding: EdgeInsets.zero),
  );
  final run = await showMenu<VoidCallback>(
    context: context,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    items: [
      if (!onPage) item('open', Icons.open_in_new, 'Open series page', () => nav.openSeries(s.name)),
      item(
        'play',
        Icons.play_arrow_rounded,
        progress.finished == 0 ? 'Play' : 'Continue',
        () => playSeries(context, s),
      ),
      item(
        'favourite',
        fav ? Icons.favorite : Icons.favorite_border,
        fav ? 'Remove from favourites' : 'Add to favourites',
        () => playlists.setFavouriteSeries([s.name], !fav),
      ),
      item(
        'sidebar',
        quickLinkMenuIcon(inSidebar),
        quickLinkMenuText(inSidebar),
        () => lib.toggleQuickLink(QuickLink(QuickLinkKind.series, s.name, s.name)),
      ),
      item(
        'finished',
        progress.allFinished ? Icons.remove_done : Icons.done_all,
        progress.allFinished ? 'Mark all as not finished' : 'Mark all as finished',
        () => markSeriesFinished(listening, s, !progress.allFinished),
      ),
    ],
  );
  run?.call();
}

/// A series' card: its picture (the first book's cover) with the number of books on it, how
/// much is finished, its name and counts. Tap to open its page; right-click or press and hold
/// for the menu. The same height as a [BookCard] ([bookCardHeight]), so they sit in one grid.
class SeriesCard extends StatelessWidget {
  final BookSeries series;
  const SeriesCard({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final listening = context.watch<ListeningModel>();
    final fav = context.select<PlaylistsModel, bool>((p) => p.isFavouriteSeries(series.name));
    final accent = Theme.of(context).colorScheme.primary;
    final progress = seriesProgress(series, listening);
    final n = series.books.length;
    void menu(Offset at) => showSeriesMenu(context, series, at);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('series-card:${series.name}'),
        borderRadius: AppShape.circular(8),
        onTap: () => context.read<AppNav>().openSeries(series.name),
        onSecondaryTapUp: (d) => menu(d.globalPosition),
        onLongPress: () {
          final box = context.findRenderObject() as RenderBox;
          menu(box.localToGlobal(box.size.center(Offset.zero)));
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: LayoutBuilder(
            builder: (context, c) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    children: [
                      BookCover(book: series.coverBook, width: c.maxWidth),
                      // How many books, bottom left, like a stack of them.
                      Positioned(
                        left: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: AppShape.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.collections_bookmark, size: 13, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                '$n',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (fav)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Icon(Icons.favorite, size: 18, color: accent, shadows: const [Shadow(blurRadius: 4)]),
                        ),
                      if (progress.allFinished)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                            child: Icon(Icons.check, size: 14, color: AppColors.current.onAccent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // How much of the series is finished (the same slot as a book's progress bar).
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: progress.finished == 0 || progress.allFinished
                        ? const SizedBox(height: 3)
                        : ClipRRect(
                            borderRadius: AppShape.circular(2),
                            child: LinearProgressIndicator(
                              value: progress.finished / n,
                              minHeight: 3,
                              backgroundColor: AppColors.surfaceHigh,
                            ),
                          ),
                  ),
                  Text(
                    series.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    seriesCounts(series, listening),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textDim, fontSize: 13),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
