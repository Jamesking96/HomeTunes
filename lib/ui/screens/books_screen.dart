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
import '../widgets/music_access_banner.dart';

enum BookFilter { all, inProgress, notStarted, finished }

/// The Books tab: every audiobook as a grid of covers.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  BookFilter _filter = BookFilter.all;
  BookSort _sort = BookSort.recentlyListened;

  /// One author / narrator / series to show (chosen with the filter button).
  BookFilters _only = BookFilters.none;

  /// Search box in the app bar (title, author, narrator, series).
  bool _searching = false;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() => setState(() {
        _searching = false;
        _search.clear();
        _query = '';
      });

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
        BookSort.narrator => 'Narrator',
        BookSort.series => 'Series (in order)',
        BookSort.recentlyAdded => 'Recently added',
      };

  bool _matches(Book b, ListeningModel l) => switch (_filter) {
        BookFilter.all => true,
        BookFilter.inProgress => l.stateOf(b) == BookState.inProgress,
        BookFilter.notStarted => l.stateOf(b) == BookState.notStarted,
        BookFilter.finished => l.stateOf(b) == BookState.finished,
      };

  /// The filter sheet: pick an author, narrator and/or series to show.
  Future<void> _chooseFilters(List<Book> books) async {
    final picked = await showModalBottomSheet<BookFilters>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (_) => _FilterSheet(books: books, current: _only),
    );
    if (picked != null && mounted) setState(() => _only = picked);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final ratio = bookCoverRatio(context);

    if (lib.books.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audiobooks', style: TextStyle(fontWeight: FontWeight.w800))),
        body: Column(children: [
          const MusicAccessBanner(),
          Expanded(
            child: EmptyState(
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
          ),
        ]),
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
    final found = _query.trim().isEmpty ? null : {for (final b in searchBookList(lib.books, _query)) b.id};
    final shown = [
      for (final b in lib.books)
        if (_matches(b, listening) && _only.matches(b) && (found == null || found.contains(b.id))) b
    ];
    final groups = sortBooks(shown, _sort, lastListened: listening.lastListened);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Title, author, narrator or series',
                  border: InputBorder.none,
                ),
              )
            : const Text('Audiobooks', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search audiobooks',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: _searching ? _closeSearch : () => setState(() => _searching = true),
          ),
          IconButton(
            tooltip: 'Filter by author, narrator or series',
            icon: Badge(
              isLabelVisible: !_only.isEmpty,
              smallSize: 8,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: () => _chooseFilters(lib.books),
          ),
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
                  // Author / narrator / series filters in use: tap × to remove.
                  for (final (label, value, clear) in [
                    ('Author', _only.author, () => _only.copyWith(clearAuthor: true)),
                    ('Narrator', _only.narrator, () => _only.copyWith(clearNarrator: true)),
                    ('Series', _only.series, () => _only.copyWith(clearSeries: true)),
                  ])
                    if (value != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          avatar: const Icon(Icons.filter_list, size: 16),
                          label: Text('$label: $value'),
                          onPressed: () => _chooseFilters(lib.books),
                          onDeleted: () => setState(() => _only = clear()),
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
                child: Text('No books match.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
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

/// Pick one author, narrator and/or series to show. Returns the new filters.
class _FilterSheet extends StatefulWidget {
  final List<Book> books;
  final BookFilters current;
  const _FilterSheet({required this.books, required this.current});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late BookFilters _f = widget.current;

  /// Choices narrow each other: once an author is picked, only their
  /// narrators and series are offered.
  List<Book> _others({bool author = true, bool narrator = true, bool series = true}) => [
        for (final b in widget.books)
          if ((!author || _f.author == null || b.author == _f.author) &&
              (!narrator || _f.narrator == null || b.narrator == _f.narrator) &&
              (!series || _f.series == null || b.series == _f.series))
            b
      ];

  Widget _dropdown({
    required String label,
    required String? value,
    required Map<String, int> options,
    required ValueChanged<String?> onChanged,
  }) {
    final items = {...options};
    if (value != null && !items.containsKey(value)) items[value] = 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All')),
          for (final e in items.entries)
            DropdownMenuItem<String?>(value: e.key, child: Text('${e.key}  (${e.value})', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Show only', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _dropdown(
            label: 'Author',
            value: _f.author,
            options: BookFilters.choices(_others(author: false), (b) => b.author),
            onChanged: (v) => setState(() => _f = v == null ? _f.copyWith(clearAuthor: true) : _f.copyWith(author: v)),
          ),
          _dropdown(
            label: 'Narrator',
            value: _f.narrator,
            options: BookFilters.choices(_others(narrator: false), (b) => b.narrator),
            onChanged: (v) =>
                setState(() => _f = v == null ? _f.copyWith(clearNarrator: true) : _f.copyWith(narrator: v)),
          ),
          _dropdown(
            label: 'Series',
            value: _f.series,
            options: BookFilters.choices(_others(series: false), (b) => b.series),
            onChanged: (v) => setState(() => _f = v == null ? _f.copyWith(clearSeries: true) : _f.copyWith(series: v)),
          ),
          const SizedBox(height: 4),
          Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(context, BookFilters.none),
              child: const Text('Clear all'),
            ),
            const Spacer(),
            FilledButton(onPressed: () => Navigator.pop(context, _f), child: const Text('Show books')),
          ]),
        ]),
      ),
    );
  }
}
