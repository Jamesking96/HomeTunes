// Book covers and book tiles for the Books tab, Home shelves and search results.
//
// [BookCover] draws a cover in the shape the user picked (square or tall, Settings ›
// Audiobooks). [BookCard] adds a progress bar / "finished" tick from ListeningModel and opens
// the book's page when tapped. [bookCardHeight] lets horizontal shelves size themselves.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../../state/selection_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'cards.dart' show SelectableCard;

/// Height ÷ width of book covers: square like music, or tall like a book
/// (Settings > Audiobooks).
double bookCoverRatio(BuildContext context) =>
    context.select<LibraryModel, bool>((l) => l.bookCoversTall) ? 1.5 : 1.0;

/// A book's cover, filling the given width at the chosen shape.
class BookCover extends StatelessWidget {
  final Book book;
  final double width;
  final double radius;
  const BookCover({super.key, required this.book, required this.width, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    final ratio = bookCoverRatio(context);
    // The book's cover comes from one of its files (see Book.artTrack).
    final track = book.artTrack;
    final lib = context.read<LibraryModel>();
    // Same sizing trick as Artwork: fetch/decode at about twice the drawn width, for sharp
    // screens, but no more.
    final px = (width * 2).clamp(64, 800).round();
    final image = lib.artFor(track, size: px);
    final placeholder = Container(
      color: AppColors.surfaceHigh,
      child: Icon(Icons.menu_book, color: AppColors.textDim, size: width * 0.35),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: width * ratio,
        child: image == null
            ? placeholder
            : Image(
                image: ResizeImage.resizeIfNeeded(px, null, image),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

/// Book tile for grids and shelves: cover, progress, title and author.
class BookCard extends StatelessWidget {
  final Book book;
  final double? width;
  /// The ids of all the books shown alongside this one, for "Select all".
  final List<String> scope;
  const BookCard({super.key, required this.book, this.width, this.scope = const []});

  @override
  Widget build(BuildContext context) {
    // Watch ListeningModel so the progress bar and "left" time update as you listen.
    final listening = context.watch<ListeningModel>();
    final state = listening.stateOf(book); // not started / in progress / finished
    final accent = Theme.of(context).colorScheme.primary;

    final card = SelectableCard(
      id: book.id,
      kind: SelectKind.books,
      scope: scope,
      onOpen: () => context.read<AppNav>().openBook(book),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, c) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Cover, with a tick in the corner once the book is finished.
            Stack(children: [
              BookCover(book: book, width: c.maxWidth),
              if (state == BookState.finished)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check, size: 14, color: Colors.black),
                  ),
                ),
            ]),
            const SizedBox(height: 6),
            if (state == BookState.inProgress)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: listening.fractionDone(book),
                    minHeight: 3,
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ),
              ),
            Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            // Second line: time left for a book in progress, otherwise the author.
            Text(
              state == BookState.inProgress ? '${formatLong(listening.timeLeft(book))} left' : book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textDim, fontSize: 13),
            ),
          ]);
        }),
      ),
    );
    return width == null ? card : SizedBox(width: width, child: card);
  }
}

/// Height a [BookCard] needs at [width] (cover + progress + two lines of text).
// The numbers: 16 = padding above and below (8 + 8, also taken off the width for the cover),
// 6 = gap under the cover, 9 = progress bar and its gap (3 + 6), 40 = the two lines of text.
// If BookCard's layout changes, update these too.
double bookCardHeight(double width, double ratio) => (width - 16) * ratio + 16 + 6 + 9 + 40;
