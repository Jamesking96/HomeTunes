import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';

enum BookFilter { all, inProgress, notStarted, finished }

enum BookSort { recentlyListened, title, author, series, recentlyAdded }

/// The Books tab: every audiobook as a grid of covers.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  BookFilter _filter = BookFilter.all;
  BookSort _sort = BookSort.recentlyListened;

  static String _filterLabel(BookFilter f) => switch (f) {
        BookFilter.all => 'All',
        BookFilter.inProgress => 'In progress',
        BookFilter.notStarted => 'Not started',
        BookFilter.finished => 'Finished',
      };

  static String _sortLabel(BookSort s) => switch (s) {
        BookSort.recentlyListened => 'Recently listened',
        BookSort.title => 'Title',
        BookSort.author => 'Author',
        BookSort.series => 'Series',
        BookSort.recentlyAdded => 'Recently added',
      };

  bool _matches(Book b, ListeningModel l) => switch (_filter) {
        BookFilter.all => true,
        BookFilter.inProgress => l.stateOf(b) == BookState.inProgress,
        BookFilter.notStarted => l.stateOf(b) == BookState.notStarted,
        BookFilter.finished => l.stateOf(b) == BookState.finished,
      };

  /// Books in display order, split into headed groups for author/series sorts.
  List<(String?, List<Book>)> _groups(List<Book> books, ListeningModel l) {
    int byTitle(Book a, Book b) => naturalCompare(a.title, b.title);
    int bySeries(Book a, Book b) {
      final c = (a.seriesIndex ?? 1e9).compareTo(b.seriesIndex ?? 1e9);
      return c != 0 ? c : byTitle(a, b);
    }

    switch (_sort) {
      case BookSort.title:
        return [(null, [...books]..sort(byTitle))];
      case BookSort.recentlyAdded:
        return [(null, [...books]..sort((a, b) => b.addedMs.compareTo(a.addedMs)))];
      case BookSort.recentlyListened:
        return [
          (
            null,
            [...books]
              ..sort((a, b) {
                final c = l.lastListened(b).compareTo(l.lastListened(a));
                return c != 0 ? c : byTitle(a, b);
              })
          )
        ];
      case BookSort.author:
      case BookSort.series:
        final map = <String, List<Book>>{};
        for (final b in books) {
          final key = _sort == BookSort.author ? b.author : (b.series ?? 'Not in a series');
          (map[key] ??= []).add(b);
        }
        final keys = map.keys.toList()
          ..sort((a, b) {
            // "Not in a series" goes last.
            if (a == 'Not in a series') return 1;
            if (b == 'Not in a series') return -1;
            return naturalCompare(a, b);
          });
        return [for (final k in keys) (k, map[k]!..sort(_sort == BookSort.series ? bySeries : byTitle))];
    }
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final ratio = bookCoverRatio(context);

    if (lib.books.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audiobooks', style: TextStyle(fontWeight: FontWeight.w800))),
        body: EmptyState(
          icon: Icons.menu_book_outlined,
          title: lib.busy ? 'Looking for audiobooks…' : 'No audiobooks yet',
          message: lib.busy
              ? lib.status
              : 'Add the folder your audiobooks are in under Settings › Audiobooks. '
                  '.m4b files and files with the genre "Audiobook" in your music folders show up here too.',
          action: lib.busy
              ? null
              : FilledButton.icon(
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add audiobooks'),
                  onPressed: () => context.read<AppNav>().selectTab(AppNav.settingsTab),
                ),
        ),
      );
    }

    final counts = {for (final f in BookFilter.values) f: 0};
    for (final b in lib.books) {
      counts[BookFilter.all] = counts[BookFilter.all]! + 1;
      final s = listening.stateOf(b);
      final f = switch (s) {
        BookState.inProgress => BookFilter.inProgress,
        BookState.notStarted => BookFilter.notStarted,
        BookState.finished => BookFilter.finished,
      };
      counts[f] = counts[f]! + 1;
    }
    final shown = [for (final b in lib.books) if (_matches(b, listening)) b];
    final groups = _groups(shown, listening);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audiobooks', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<BookSort>(
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (_) => [
              for (final s in BookSort.values) CheckedPopupMenuItem(value: s, checked: s == _sort, child: Text(_sortLabel(s))),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(builder: (context, c) {
        final cols = gridColumns(c.maxWidth);
        final itemWidth = (c.maxWidth - 16) / cols;
        final grid = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisExtent: bookCardHeight(itemWidth, ratio),
        );
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final f in BookFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('${_filterLabel(f)} (${counts[f]})'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (shown.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No books here.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
              ),
            ),
          for (final (header, books) in groups) ...[
            if (header != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              sliver: SliverGrid.builder(
                gridDelegate: grid,
                itemCount: books.length,
                itemBuilder: (_, i) => BookCard(book: books[i]),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ]);
      }),
    );
  }
}
