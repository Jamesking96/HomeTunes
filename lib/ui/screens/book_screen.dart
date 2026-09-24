import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/player_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import '../widgets/cards.dart';

/// One audiobook: details, Resume / Play, and its chapters.
class BookScreen extends StatelessWidget {
  final String bookId;
  const BookScreen({super.key, required this.bookId});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final listening = context.watch<ListeningModel>();
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
    final current = _currentChapter(book, chapters, progress);
    final accent = Theme.of(context).colorScheme.primary;
    final wide = MediaQuery.sizeOf(context).width > 600;

    final details = [
      if (book.narrator != null) 'Read by ${book.narrator}',
      if (book.seriesLabel != null) book.seriesLabel!,
      if (book.year != null) '${book.year}',
      formatLong(book.duration),
    ].join(' · ');

    final status = switch (state) {
      BookState.notStarted => 'Not started',
      BookState.finished => 'Finished',
      BookState.inProgress =>
        '${formatLong(listening.timeLeft(book))} left · ${(listening.fractionDone(book) * 100).round()}%',
    };

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

    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(child: header),
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
              onTap: () => playingThis ? player.goToChapter(i) : player.playBook(book, partIndex: ch.part, at: ch.start),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }

  /// Index of the chapter the listener is in (by the saved place), or -1.
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
    await lib.setIsBook(ids, false);
    if (navigator.canPop()) navigator.pop();
    messenger?.showSnackBar(SnackBar(
      content: Text('"${book.title}" moved to Music'),
      action: SnackBarAction(label: 'Undo', onPressed: () => lib.setIsBook(ids, null)),
    ));
  }
}
