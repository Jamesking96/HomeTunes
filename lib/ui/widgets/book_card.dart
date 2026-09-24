import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/library_model.dart';
import '../../state/listening_model.dart';
import '../nav.dart';
import '../theme.dart';
import 'artwork.dart';

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
    final track = book.artTrack;
    final lib = context.read<LibraryModel>();
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
  const BookCard({super.key, required this.book, this.width});

  @override
  Widget build(BuildContext context) {
    final listening = context.watch<ListeningModel>();
    final state = listening.stateOf(book);
    final accent = Theme.of(context).colorScheme.primary;

    final card = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.read<AppNav>().openBook(book),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: LayoutBuilder(builder: (context, c) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
double bookCardHeight(double width, double ratio) => (width - 16) * ratio + 16 + 6 + 9 + 40;
