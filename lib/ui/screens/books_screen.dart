// The Audiobooks tab: every audiobook as a grid of covers, with ways to narrow it down.
//
// 0.1.74 (the user: "align more with the Music and Videos tabs, where we have sub-tabs"): sub-tabs
// Series · All · In progress · Not started · Finished · Favourites (the last five were chips
// before). Like Your Library's tabs, each has its own filter bar (a box to filter by title,
// author, narrator or series, the Filter button and the Sort menu), the All / Favourites chips
// with counts, and a removable chip per filter picked; each tab keeps its own choices.
// The Series tab shows a heading per series with its books in order (sortSeries); the others
// sort with sortBooks (state/book_index.dart). Books are built by LibraryModel; progress comes
// from ListeningModel.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/music_filters.dart';
import '../../state/playlists_model.dart';
import '../nav.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';
import '../widgets/music_access_banner.dart';
import '../widgets/music_filter_sheet.dart';
import '../widgets/rescan_button.dart';

/// The sub-tabs along the top of the Audiobooks tab, in the order shown.
enum BookTab { series, all, inProgress, notStarted, finished, favourites }

/// What the Audiobooks filter sheet can narrow by.
final List<FilterField<Book>> bookFields = [
  FilterField('Author', (b) => [if (b.author.isNotEmpty) b.author]),
  FilterField('Narrator', (b) => [?b.narrator]),
  FilterField('Series', (b) => [?b.series]),
  FilterField('Genre', (b) => {for (final t in b.parts) if (t.genre?.trim().isNotEmpty ?? false) t.genre!.trim()}),
  FilterField('Decade', (b) => [?decadeOf(b.year)]),
];

/// The Audiobooks tab.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: BookTab.values.length, vsync: this);

  /// The Favourites tab, so the sidebar's Favourite audiobooks can clear its filters.
  final _favourites = GlobalKey<_BookTabState>();

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  static String _label(BookTab t) => switch (t) {
        BookTab.series => 'Series',
        BookTab.all => 'All',
        BookTab.inProgress => 'In progress',
        BookTab.notStarted => 'Not started',
        BookTab.finished => 'Finished',
        BookTab.favourites => 'Favourites',
      };

  @override
  Widget build(BuildContext context) {
    // The sidebar's Favourite audiobooks (1 Oct): the Favourites tab, with nothing narrowing it.
    context.select<AppNav, String?>((n) => n.viewRequest);
    if (context.read<AppNav>().takeView(AppNav.favouriteBooksView)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabs.index = BookTab.favourites.index;
        _favourites.currentState?.clearAll();
      });
    }
    final lib = context.watch<LibraryModel>();
    const title = Text('Audiobooks', style: TextStyle(fontWeight: FontWeight.w800));
    const rescan = RescanButton(tooltip: 'Rescan audiobook and music folders');

    // No books at all yet: a helpful message and a button straight to Settings > Audiobooks.
    if (lib.books.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: title, actions: const [rescan]),
        body: Column(children: [
          const MusicAccessBanner(),
          Expanded(
            child: EmptyState(
              icon: Icons.menu_book_outlined,
              title: lib.busy ? 'Looking for audiobooks…' : 'No audiobooks yet',
              message: lib.busy
                  ? 'Progress is shown at the bottom of the screen.'
                  : 'Add the folder your audiobooks are in under Settings › Audiobooks. '
                      '.m4b files and files with the genre "Audiobook" in your music folders show up here too.',
              action: lib.busy
                  ? null
                  : FilledButton.icon(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add audiobooks'),
                      onPressed: () => context.read<AppNav>().openSettings('audiobooks', setting: 'book-folders'),
                    ),
            ),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: title,
        actions: const [rescan],
        // The sub-tabs, laid out like Your Library's and Videos'.
        bottom: TabBar(
          key: const ValueKey('book-tabs'),
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in BookTab.values) Tab(text: _label(t))],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          for (final t in BookTab.values) _BookTab(key: t == BookTab.favourites ? _favourites : ValueKey(t), tab: t),
        ],
      ),
    );
  }
}

/// One sub-tab: its filter bar, chips and grid of covers. Kept alive, so each tab remembers what
/// was typed, picked and sorted while you look at the others (like Your Library's tabs).
class _BookTab extends StatefulWidget {
  final BookTab tab;
  const _BookTab({super.key, required this.tab});

  @override
  State<_BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<_BookTab> with AutomaticKeepAliveClientMixin {
  final _search = TextEditingController();
  String _query = '';
  MusicFilters _filters = MusicFilters.none;
  bool _favouritesOnly = false;

  /// The sort on the book tabs (not saved, so it starts as "Recently listened" each run)…
  BookSort _sort = BookSort.recentlyListened;

  /// …and on the Series tab (series A to Z to start with).
  SeriesSort _seriesSort = SeriesSort.name;

  /// The other way round from the sort's usual direction (0.1.69).
  bool _reversed = false;

  BookTab get _tab => widget.tab;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Forgets the typed words, the picked filters and the Favourites chip.
  void clearAll() => setState(() {
        _search.clear();
        _query = '';
        _filters = MusicFilters.none;
        _favouritesOnly = false;
      });

  bool get _narrowed => _query.trim().isNotEmpty || !_filters.isEmpty || _favouritesOnly;

  static String _sortLabel(BookSort s) => switch (s) {
        BookSort.recentlyListened => 'Recently listened',
        BookSort.title => 'Title',
        BookSort.author => 'Author',
        BookSort.narrator => 'Narrator',
        BookSort.series => 'Series (in order)',
        BookSort.recentlyAdded => 'Recently added',
      };

  static SortWords _words(BookSort s) => switch (s) {
        BookSort.recentlyListened || BookSort.recentlyAdded => SortWords.date,
        BookSort.title || BookSort.author || BookSort.narrator => SortWords.text,
        BookSort.series => SortWords.order,
      };

  static String _seriesLabel(SeriesSort s) => switch (s) {
        SeriesSort.name => 'Series name',
        SeriesSort.author => 'Author',
        SeriesSort.recentlyListened => 'Recently listened',
        SeriesSort.recentlyAdded => 'Recently added',
        SeriesSort.mostBooks => 'Most books',
      };

  static SortWords _seriesWords(SeriesSort s) => switch (s) {
        SeriesSort.name || SeriesSort.author => SortWords.text,
        SeriesSort.recentlyListened || SeriesSort.recentlyAdded => SortWords.date,
        SeriesSort.mostBooks => SortWords.number,
      };

  /// Whether book [b] belongs on this tab at all.
  bool _onTab(Book b, ListeningModel l, PlaylistsModel p) => switch (_tab) {
        BookTab.series || BookTab.all => true,
        BookTab.favourites => p.isFavouriteBook(b),
        BookTab.inProgress => l.stateOf(b) == BookState.inProgress,
        BookTab.notStarted => l.stateOf(b) == BookState.notStarted,
        BookTab.finished => l.stateOf(b) == BookState.finished,
      };

  /// What the tab says when it has no books at all (before any filtering).
  String get _emptyText => switch (_tab) {
        BookTab.series || BookTab.all => 'No audiobooks yet.',
        BookTab.inProgress => 'No books in progress.',
        BookTab.notStarted => 'No books waiting to be started.',
        BookTab.finished => 'No finished books yet.',
        BookTab.favourites => 'No favourite books yet. Tap the heart on a book to add it here.',
      };

  Future<void> _chooseFilters(List<Book> books) async {
    final picked = await showMusicFilterSheet<Book>(
      context,
      items: books,
      fields: bookFields,
      current: _filters,
      showLabel: 'Show books',
    );
    if (picked != null && mounted) setState(() => _filters = picked);
  }

  /// All / Favourites chips with counts (not on the Favourites tab), then one removable chip per
  /// picked filter. The same as Your Library's tabs.
  Widget _chipRow({required int all, required int favourites, required VoidCallback onEditFilters}) {
    final chips = [
      if (_tab != BookTab.favourites) ...[
        ChoiceChip(
          key: const ValueKey('books-all-chip'),
          label: Text('All ($all)'),
          selected: !_favouritesOnly,
          onSelected: (_) => setState(() => _favouritesOnly = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          key: const ValueKey('books-favourites-chip'),
          avatar: const Icon(Icons.favorite, size: 16),
          label: Text('Favourites ($favourites)'),
          selected: _favouritesOnly,
          onSelected: (_) => setState(() => _favouritesOnly = true),
        ),
      ],
      for (final e in _filters.picked.entries)
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: InputChip(
            avatar: const Icon(Icons.filter_list, size: 16),
            label: Text('${e.key}: ${e.value}'),
            onPressed: onEditFilters,
            onDeleted: () => setState(() => _filters = _filters.withValue(e.key, null)),
          ),
        ),
    ];
    if (chips.isEmpty) return const SizedBox(height: 8);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: chips,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    final playlists = context.watch<PlaylistsModel>();
    final ratio = bookCoverRatio(context);

    // 1. The tab's books, then the typed words (title, author, narrator or series) and the
    //    picked filters; the Favourites chip narrows that to favourites.
    final onTab = [for (final b in lib.books) if (_onTab(b, listening, playlists)) b];
    final found = _query.trim().isEmpty ? null : {for (final b in searchBookList(onTab, _query)) b.id};
    final passing = [
      for (final b in onTab)
        if ((found == null || found.contains(b.id)) && _filters.matches(b, bookFields)) b
    ];
    final favourites = passing.where(playlists.isFavouriteBook).toList();
    final shown = _favouritesOnly ? favourites : passing;

    // 2. Sorted into headed groups: one per series on the Series tab; for the other tabs, the
    //    author / narrator / series sorts give headings and the rest one plain list.
    final series = _tab == BookTab.series;
    final groups = series
        ? sortSeries(shown, _seriesSort, lastListened: listening.lastListened, reverse: _reversed)
        : reverseGroupsIf(_reversed, sortBooks(shown, _sort, lastListened: listening.lastListened));
    // Everything shown, in the order shown: what "Select all" ticks.
    final shownIds = [for (final (_, g) in groups) for (final b in g) b.id];
    void edit() => _chooseFilters(lib.books);

    final Widget body;
    if (shownIds.isEmpty) {
      body = SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              _narrowed ? 'No books match.' : _emptyText,
              key: ValueKey('books-empty-${_tab.name}'),
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textDim),
            ),
            if (_narrowed) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: clearAll, child: const Text('Clear filters')),
            ],
          ]),
        ),
      );
    } else {
      body = _grid(groups, shownIds, ratio, series: series);
    }

    final filterBar = series
        ? MusicFilterBar<SeriesSort>(
            controller: _search,
            hint: 'Filter by title, author, narrator or series',
            onChanged: (v) => setState(() => _query = v),
            filtersActive: !_filters.isEmpty,
            onFilter: edit,
            sort: _seriesSort,
            sorts: SeriesSort.values,
            sortLabel: _seriesLabel,
            onSort: (s) => setState(() {
              _seriesSort = s;
              _reversed = false;
            }),
            sortWords: _seriesWords,
            reversed: _reversed,
            onReversed: (r) => setState(() => _reversed = r),
          )
        : MusicFilterBar<BookSort>(
            controller: _search,
            hint: 'Filter by title, author, narrator or series',
            onChanged: (v) => setState(() => _query = v),
            filtersActive: !_filters.isEmpty,
            onFilter: edit,
            sort: _sort,
            sorts: BookSort.values,
            sortLabel: _sortLabel,
            onSort: (s) => setState(() {
              _sort = s;
              _reversed = false;
            }),
            sortWords: _words,
            reversed: _reversed,
            onReversed: (r) => setState(() => _reversed = r),
          );

    return Column(children: [
      filterBar,
      _chipRow(all: passing.length, favourites: favourites.length, onEditFilters: edit),
      Expanded(child: body),
    ]);
  }

  /// The covers, one optional heading + grid per group. On the Series tab each heading also
  /// says how many books the series has here.
  Widget _grid(List<(String?, List<Book>)> groups, List<String> shownIds, double ratio, {required bool series}) {
    return LayoutBuilder(builder: (context, c) {
      final cols = gridColumns(c.maxWidth);
      // 16 = the 8 px padding on each side of the grid.
      final itemWidth = (c.maxWidth - 16) / cols;
      final grid = SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisExtent: bookCardHeight(itemWidth, ratio),
      );
      return CustomScrollView(key: PageStorageKey('books-${_tab.name}'), slivers: [
        for (final (header, books) in groups) ...[
          if (header != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text.rich(
                  key: series ? ValueKey('series-heading:$header') : null,
                  TextSpan(children: [
                    TextSpan(text: header, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    if (series && header != noSeries)
                      TextSpan(
                        text: '  ${books.length} book${books.length == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 13, color: AppColors.textDim),
                      ),
                  ]),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverGrid.builder(
              gridDelegate: grid,
              itemCount: books.length,
              itemBuilder: (_, i) => BookCard(book: books[i], scope: shownIds),
            ),
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]);
    });
  }
}
