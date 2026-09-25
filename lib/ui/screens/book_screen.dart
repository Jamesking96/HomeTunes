// The page for one audiobook: cover, title, author, narrator/series/year, a progress bar,
// Play / Resume buttons, an "About this book" section (description and any PDF that came with
// it), the book's bookmarks, and its chapter list.
//
// Opened through AppNav.openBook (from the Books tab, Home, search and Now Playing). The listening
// state (where you are, finished or not) comes from ListeningModel; playing goes through
// PlayerModel.playBook, which handles resuming at the saved place. Editing opens edit_book.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/bookmarks_model.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/bookmark_widgets.dart';
import '../widgets/cards.dart';
import 'edit_book.dart';

/// One audiobook: details, Resume / Play, and its chapters.
class BookScreen extends StatelessWidget {
  /// The book's id (from the book index). Looked up fresh on each build so edits show at once.
  final String bookId;
  const BookScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
    // Use select() so this page only rebuilds when these two facts change, not on every position
    // tick of the player.
    final playingThis = context.select<PlayerModel, bool>((p) => p.book?.id == bookId);
    final isPlaying = context.select<PlayerModel, bool>((p) => p.playing);
    final book = lib.bookById(bookId);
    if (book == null) {
      return Scaffold(appBar: AppBar(), body: const EmptyState(icon: Icons.menu_book, title: 'Book not found'));
    }
    final player = context.read<PlayerModel>();
    final state = listening.stateOf(book);
    final progress = listening.progressFor(book);
    final chapters = book.chapters;
    final bookmarks = context.watch<BookmarksModel>().forBook(book);
    // Which chapter to highlight: worked out from the saved place, not the live position.
    final current = _currentChapter(book, chapters, progress);
    final accent = Theme.of(context).colorScheme.primary;
    // Wide screens put the cover beside the details; narrow ones stack everything centred.
    final wide = MediaQuery.sizeOf(context).width > 600;

    // 1. The small grey line of details under the author ("Read by … · Series · 2019 · 9h 12m").
    final details = [
      if (book.narrator != null) 'Read by ${book.narrator}',
      if (book.seriesLabel != null) book.seriesLabel!,
      if (book.year != null) '${book.year}',
      formatLong(book.duration),
    ].join(' · ');

    // 2. Status line: not started / finished / time left and % done.
    final status = switch (state) {
      BookState.notStarted => 'Not started',
      BookState.finished => 'Finished',
      BookState.inProgress =>
        '${formatLong(listening.timeLeft(book))} left · ${(listening.fractionDone(book) * 100).round()}%',
    };

    // The main button: pause/resume if this book is already loaded, otherwise start it.
    // A finished book starts again from the beginning ("Listen again").
    Future<void> play() async {
      if (playingThis) {
        await player.togglePlay();
      } else {
        await player.playBook(book, fromStart: state == BookState.finished);
      }
    }

    final mainLabel = playingThis
        ? (isPlaying ? 'Pause' : 'Resume')
        : switch (state) {
            BookState.notStarted => 'Play',
            BookState.inProgress => 'Resume',
            BookState.finished => 'Listen again',
          };

    // 3. The block of text beside/under the cover.
    final info = Column(
      crossAxisAlignment: wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('AUDIOBOOK', style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: AppColors.textDim)),
        const SizedBox(height: 6),
        Text(book.title,
            textAlign: wide ? TextAlign.start : TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: wide ? 34 : 24, fontWeight: FontWeight.w800, height: 1.15)),
        const SizedBox(height: 6),
        Text(book.author, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(details, textAlign: wide ? TextAlign.start : TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
        const SizedBox(height: 10),
        if (state == BookState.inProgress)
          SizedBox(
            width: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: listening.fractionDone(book),
                minHeight: 4,
                backgroundColor: AppColors.surfaceHigh,
              ),
            ),
          ),
        const SizedBox(height: 6),
        Text(status, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
      ],
    );

    // 4. The row of buttons: Play/Resume, Play from start, Edit, and a ⋮ menu.
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilledButton.icon(
          icon: Icon(playingThis && isPlaying ? Icons.pause : Icons.play_arrow_rounded),
          label: Text(mainLabel),
          onPressed: play,
        ),
        if (state == BookState.inProgress)
          OutlinedButton.icon(
            icon: const Icon(Icons.replay),
            label: const Text('Play from start'),
            onPressed: () => player.playBook(book, fromStart: true),
          ),
        IconButton(
          tooltip: 'Edit book details',
          icon: const Icon(Icons.edit_outlined),
          onPressed: () => _edit(context, book),
        ),
        // Each menu item's value is the function to run, so onSelected just calls it.
        PopupMenuButton<VoidCallback>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (f) => f(),
          itemBuilder: (_) => [
            if (state != BookState.finished)
              PopupMenuItem(
                value: () => listening.setFinished(book, true),
                child: const Text('Mark as finished'),
              ),
            if (state != BookState.notStarted)
              PopupMenuItem(
                value: () => listening.setFinished(book, false),
                child: Text(state == BookState.finished ? 'Mark as not finished' : 'Start over (clear progress)'),
              ),
            PopupMenuItem(
              value: () => _moveToMusic(context, book),
              child: const Text('Move to Music…'),
            ),
          ],
        ),
      ],
    );

    // 5. The header: cover + info + buttons on a soft accent-coloured gradient.
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
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                BookCover(book: book, width: coverWidth),
                const SizedBox(width: 24),
                Expanded(child: info),
              ]),
              const SizedBox(height: 16),
              actions,
            ])
          : Column(children: [
              BookCover(book: book, width: coverWidth),
              const SizedBox(height: 16),
              info,
              const SizedBox(height: 12),
              actions,
            ]),
    );

    // 6. The page: header, About, bookmarks (if any), then the chapter list.
    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: header),
        if (book.description != null || _openableCompanions(book).isNotEmpty)
          SliverToBoxAdapter(child: _About(book: book, companions: _openableCompanions(book))),
        if (bookmarks.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text('${bookmarks.length} bookmark${bookmarks.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ),
          SliverList.builder(
            itemCount: bookmarks.length,
            itemBuilder: (_, i) => BookmarkTile(book: book, bookmark: bookmarks[i]),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('${chapters.length} chapter${chapters.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        SliverList.builder(
          itemCount: chapters.length,
          itemBuilder: (_, i) {
            final ch = chapters[i];
            // A chapter ends where the next one starts (or at the end of the book),
            // which gives its length.
            final end = i + 1 < chapters.length ? chapters[i + 1].offset : book.duration;
            final isCurrent = i == current;
            return ListTile(
              leading: SizedBox(
                width: 32,
                child: isCurrent
                    ? Icon(playingThis && isPlaying ? Icons.graphic_eq : Icons.bookmark_outline, color: accent, size: 20)
                    : Text('${i + 1}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)),
              ),
              title: Text(ch.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: isCurrent ? accent : null, fontWeight: FontWeight.w500)),
              subtitle: Text('Starts at ${formatDuration(ch.offset)}'),
              trailing: Text(formatDuration(end - ch.offset), style: const TextStyle(color: AppColors.textDim)),
              // If the book is loaded, jump within it; otherwise start the book at
              // this chapter's file and spot.
              onTap: () => playingThis ? player.goToChapter(i) : player.playBook(book, partIndex: ch.part, at: ch.start),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }

  /// Companion files (PDFs) that can be opened here: on computers, where
  /// they open in the usual app. (Android doesn't let apps see them.)
  static List<String> _openableCompanions(Book book) =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux ? book.companions : const [];

  /// Index of the chapter the listener is in (by the saved place), or -1.
  static int _currentChapter(Book book, List<BookChapter> chapters, BookProgress? progress) {
    if (progress == null || progress.finished) return -1;
    final part = book.indexOfPart(progress.partId);
    if (part < 0) return -1;
    // Turn "file + position in file" into a position in the whole book, then find the last chapter
    // that starts at or before it.
    final at = book.offsetOf(part, progress.position);
    var found = -1;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].offset <= at) found = i;
    }
    return found;
  }

  /// Opens the editor; renaming the book gives it a new id, so follow it.
  Future<void> _edit(BuildContext context, Book book) async {
    final lib = context.read<LibraryModel>();
    final navigator = Navigator.of(context);
    // Remember a file from the book so we can find the (possibly renamed) book again afterwards.
    final firstPart = book.parts.first.id;
    final saved = await showEditBook(context, book);
    if (!saved) return;
    final now = lib.bookOfTrack(firstPart);
    if (now != null && now.id != book.id && navigator.mounted) {
      navigator.pushReplacement(MaterialPageRoute(builder: (_) => BookScreen(bookId: now.id)));
    }
  }

  /// Asks, then marks all the book's files as music ("Move to Music"). The snackbar's Undo
  /// clears the override again so the usual book rules decide.
  Future<void> _moveToMusic(BuildContext context, Book book) async {
    final lib = context.read<LibraryModel>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Move "${book.title}" to Music?'),
        content: Text('Its ${book.parts.length} file${book.parts.length == 1 ? '' : 's'} will show up as songs instead. '
            'You can move them back with "Move to Books" on any of them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Move to Music')),
        ],
      ),
    );
    if (ok != true) return;
    final ids = [for (final t in book.parts) t.id];
    // The book no longer exists once its files are music, so close this page.
    await lib.setIsBook(ids, false);
    if (navigator.canPop()) navigator.pop();
    messenger?.showSnackBar(SnackBar(
      content: Text('"${book.title}" moved to Music'),
      action: SnackBarAction(label: 'Undo', onPressed: () => lib.setIsBook(ids, null)),
    ));
  }
}

/// The book's description (folded to a few lines until opened) and the
/// files that come with it.
class _About extends StatefulWidget {
  final Book book;
  final List<String> companions;
  const _About({required this.book, required this.companions});

  @override
  State<_About> createState() => _AboutState();
}

class _AboutState extends State<_About> {
  /// Whether the description is expanded.
  bool _open = false;

  /// Opens a companion file (e.g. a PDF) in the computer's usual app for it.
  Future<void> _openFile(String path) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [path]);
      } else {
        await Process.start('xdg-open', [path]);
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t open ${p.basename(path)}: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.book.description;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (text != null) ...[
          const Text('About this book', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _open
                ? SelectableText(text, style: const TextStyle(color: AppColors.textDim, height: 1.45))
                : Text(text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textDim, height: 1.45)),
          ),
          // Only offer "Show more" when the text is long enough to have been cut short.
          if (text.length > 240 || '\n'.allMatches(text).length > 3)
            TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => setState(() => _open = !_open),
              child: Text(_open ? 'Show less' : 'Show more'),
            ),
        ],
        if (widget.companions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in widget.companions)
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_label(f, widget.companions.length)),
                onPressed: () => _openFile(f),
              ),
          ]),
        ],
      ]),
    );
  }

  /// "Book PDF" when there's one, else its file name.
  static String _label(String path, int count) {
    final ext = p.extension(path).replaceFirst('.', '').toUpperCase();
    return count == 1 ? 'Open the book\'s $ext' : p.basename(path);
  }
}
