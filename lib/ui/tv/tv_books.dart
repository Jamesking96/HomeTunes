// The TV's Audiobooks screen (0.2.0, step 2 of the TV interface): the same tabs as the
// Audiobooks tab elsewhere (Series, All, In progress, Not started, Finished, Favourites) as
// grids of big covers, with the A–Z strip where the order is by name. A book opens its page,
// a series its page (their TV versions come in step 3); holding OK gives Play, Carry on and the
// rest.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import 'tv_browse.dart';
import 'tv_items.dart';
import 'tv_music.dart' show tvEmptyLibraryHints, tvLibraryHints;
import 'tv_options.dart';

enum TvBookTab {
  series('Series'),
  all('All'),
  inProgress('In progress'),
  notStarted('Not started'),
  finished('Finished'),
  favourites('Favourites');

  const TvBookTab(this.label);
  final String label;
}

enum TvBookSort {
  title('A–Z'),
  author('Author'),
  recentlyListened('Recently listened'),
  recentlyAdded('Recently added');

  const TvBookSort(this.label);
  final String label;
}

class TvBooksScreen extends StatefulWidget {
  const TvBooksScreen({super.key});

  @override
  State<TvBooksScreen> createState() => _TvBooksScreenState();
}

class _TvBooksScreenState extends State<TvBooksScreen> {
  var _tab = TvBookTab.series;
  var _sort = TvBookSort.title;

  List<Book> _sorted(List<Book> books, ListeningModel l) => switch (_sort) {
        TvBookSort.title => [...books]..sort((a, b) => naturalCompare(a.title, b.title)),
        TvBookSort.author => [...books]..sort((a, b) {
            final c = naturalCompare(a.author, b.author);
            return c != 0 ? c : compareBySeries(a, b);
          }),
        TvBookSort.recentlyListened => [...books]..sort((a, b) => l.lastListened(b).compareTo(l.lastListened(a))),
        TvBookSort.recentlyAdded => [...books]..sort((a, b) => b.addedMs.compareTo(a.addedMs)),
      };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final playlists = context.watch<PlaylistsModel>();
    final nav = context.read<AppNav>();
    final aspect = tvBookAspect(context);
    // The sidebar elsewhere can ask for Favourite audiobooks.
    if (nav.takeView(AppNav.favouriteBooksView)) _tab = TvBookTab.favourites;

    final Widget body;
    if (lib.books.isEmpty) {
      body = TvEmpty(
        icon: Icons.menu_book_outlined,
        title: lib.busy ? 'Looking through your folders…' : 'No audiobooks yet',
        message: lib.busy ? null : 'Choose the folders your audiobooks are in, on a USB drive or the TV itself, or connect a server.',
        action: lib.busy
            ? null
            : TvButton(label: 'Add audiobook folders', icon: Icons.folder_open, primary: true, onPressed: () => nav.openSettings('books')),
      );
    } else if (_tab == TvBookTab.series) {
      // A tile per series (A–Z), then the books that aren't in one.
      final groups = sortSeries(lib.books, SeriesSort.name);
      final items = <Object>[
        ...seriesOf(groups),
        for (final (h, g) in groups)
          if (h == noSeries) ...g,
      ];
      body = TvAzGrid<Object>(
        key: const ValueKey('series'),
        items: items,
        aspectRatio: aspect,
        letterOf: (x) => tvLetterOf(x is BookSeries ? x.name : (x as Book).title),
        itemBuilder: (context, x, i, node, w) =>
            x is BookSeries ? tvSeriesTile(context, x, node: node, width: w, aspectRatio: aspect) : tvBookTile(context, x as Book, node: node, width: w, aspectRatio: aspect),
      );
    } else {
      final books = [
        for (final b in lib.books)
          if (switch (_tab) {
            TvBookTab.favourites => playlists.isFavouriteBook(b),
            TvBookTab.inProgress => listening.stateOf(b) == BookState.inProgress,
            TvBookTab.notStarted => listening.stateOf(b) == BookState.notStarted,
            TvBookTab.finished => listening.stateOf(b) == BookState.finished,
            _ => true,
          })
            b,
      ];
      final favSeries = _tab == TvBookTab.favourites
          ? [for (final s in seriesOf(sortSeries(lib.books, SeriesSort.name))) if (playlists.isFavouriteSeries(s.name)) s]
          : const <BookSeries>[];
      final items = <Object>[...favSeries, ..._sorted(books, listening)];
      body = items.isEmpty
          ? TvEmpty(
              icon: Icons.menu_book_outlined,
              title: switch (_tab) {
                TvBookTab.inProgress => 'No books in progress',
                TvBookTab.notStarted => 'No books waiting to be started',
                TvBookTab.finished => 'No finished books yet',
                _ => 'No favourites yet',
              },
              message: _tab == TvBookTab.favourites ? 'Hold OK on a book or a series and choose Add to favourites.' : null,
            )
          : TvAzGrid<Object>(
              key: ValueKey('books-${_tab.name}-${_sort.name}'),
              items: items,
              aspectRatio: aspect,
              letterOf: switch (_sort) {
                TvBookSort.title when favSeries.isEmpty => (x) => tvLetterOf((x as Book).title),
                TvBookSort.author when favSeries.isEmpty => (x) => tvLetterOf((x as Book).author),
                _ => null,
              },
              itemBuilder: (context, x, i, node, w) =>
                  x is BookSeries ? tvSeriesTile(context, x, node: node, width: w, aspectRatio: aspect) : tvBookTile(context, x as Book, node: node, width: w, aspectRatio: aspect),
            );
    }

    return TvPageHints(
      tab: AppNav.booksTab,
      hints: lib.books.isEmpty && !lib.busy ? tvEmptyLibraryHints : tvLibraryHints,
      child: TvPage(
        title: 'Audiobooks',
        tabs: TvTabBar(
          labels: [for (final t in TvBookTab.values) t.label],
          selected: _tab.index,
          onSelect: (i) => setState(() => _tab = TvBookTab.values[i]),
        ),
        actions: [
          if (_tab != TvBookTab.series && lib.books.isNotEmpty)
            TvButton(
              key: const ValueKey('tv-sort'),
              label: 'Sort: ${_sort.label}',
              icon: Icons.sort,
              onPressed: () => showTvOptions(context, title: 'Sort audiobooks', options: [
                for (final s in TvBookSort.values)
                  TvOption(s.label, s == _sort ? Icons.check : Icons.sort, () => setState(() => _sort = s)),
              ]),
            ),
        ],
        body: body,
      ),
    );
  }
}
