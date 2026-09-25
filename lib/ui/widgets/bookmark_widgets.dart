// Audiobook bookmarks: adding one at the current spot, the note dialog, jumping to a bookmark,
// the bookmark row, and the Bookmarks sheet opened from Now Playing.
//
// A bookmark is saved against one file of the book (partId) plus a position inside that file,
// because books can be several files. For display it's turned into a time from the start of
// the whole book and matched to its chapter. Storage is BookmarksModel (bookmarks.json).
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/bookmarks_model.dart';
import '../../state/player_model.dart';
import '../theme.dart';

/// Bookmarks the spot being listened to right now, and offers to add a note.
Future<void> addBookmarkNow(BuildContext context) async {
  final player = context.read<PlayerModel>();
  final bookmarks = context.read<BookmarksModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final t = player.current;
  // Only for books (music has no bookmarks).
  if (player.book == null || t == null) return;
  // Saved as "this file, this far in"; the message shows the time into the whole book.
  final b = await bookmarks.add(t.id, player.position);
  messenger?.showSnackBar(SnackBar(
    content: Text('Bookmark added at ${formatElapsed(player.bookOffset)}'),
    action: SnackBarAction(
      label: 'Add note',
      onPressed: () async {
        if (!context.mounted) return;
        final note = await askForBookmarkNote(context);
        if (note != null) await bookmarks.setNote(b, note);
      },
    ),
  ));
}

/// Asks for a bookmark's note. Returns null if cancelled.
Future<String?> askForBookmarkNote(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  // useRootNavigator: show above everything, including the player sheet and bottom bars.
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: const Text('Bookmark note'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        minLines: 1,
        maxLines: 4,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'What happens here?'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
      ],
    ),
  ).whenComplete(ctrl.dispose); // tidy up the text box once the dialog closes
}

/// Plays [book] from a bookmark (or just jumps there if it's playing).
Future<void> playBookmark(BuildContext context, Book book, Bookmark b) async {
  final player = context.read<PlayerModel>();
  final part = book.indexOfPart(b.partId);
  if (part < 0) return; // that file is no longer part of the book
  // Same book already loaded: just seek (keeps the queue and speed as they are).
  if (player.book?.id == book.id) {
    await player.goToPart(part, b.position);
    if (!player.playing) await player.play();
  } else {
    await player.playBook(book, partIndex: part, at: b.position);
  }
}

/// One bookmark: where it is (chapter + time), its note, and a menu.
class BookmarkTile extends StatelessWidget {
  final Book book;
  final Bookmark bookmark;
  /// Called after a tap starts playback (the sheet uses it to close itself).
  final VoidCallback? onPlayed;
  const BookmarkTile({super.key, required this.book, required this.bookmark, this.onPlayed});

  @override
  Widget build(BuildContext context) {
    final bookmarks = context.read<BookmarksModel>();
    final part = book.indexOfPart(bookmark.partId);
    final at = book.offsetOf(part, bookmark.position);
    final chapters = book.chapters;
    // Chapters are in order, so the last one starting at or before the bookmark is the one
    // it's in.
    var chapter = '';
    for (final c in chapters) {
      if (c.offset <= at) chapter = c.title;
    }
    // With a note: the note is the title and "time · chapter" underneath. Without: the chapter
    // is the title and the time underneath.
    return ListTile(
      leading: Icon(Icons.bookmark, color: Theme.of(context).colorScheme.primary),
      title: Text(bookmark.note.isEmpty ? chapter : bookmark.note, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(bookmark.note.isEmpty ? formatElapsed(at) : '${formatElapsed(at)} · $chapter',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        // Starts playing (reading what it needs right away), then closes the sheet.
        playBookmark(context, book, bookmark);
        onPlayed?.call();
      },
      trailing: PopupMenuButton<String>(
        tooltip: 'Bookmark options',
        onSelected: (v) async {
          if (v == 'note') {
            final note = await askForBookmarkNote(context, initial: bookmark.note);
            if (note != null) await bookmarks.setNote(bookmark, note);
          } else if (v == 'delete') {
            await bookmarks.remove(bookmark);
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'note', child: Text(bookmark.note.isEmpty ? 'Add note' : 'Edit note')),
          const PopupMenuItem(value: 'delete', child: Text('Delete bookmark')),
        ],
      ),
    );
  }
}

/// The playing book's bookmarks in a sheet (Now Playing).
Future<void> showBookmarksSheet(BuildContext context) {
  final book = context.read<PlayerModel>().book;
  if (book == null) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    showDragHandle: true,
    // A sheet that opens about half-height and can be dragged up; the Consumer keeps the list
    // up to date as bookmarks are added, edited or deleted while it's open.
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.95,
      builder: (_, scroll) => Consumer<BookmarksModel>(builder: (context, model, _) {
        final list = model.forBook(book);
        return ListView(controller: scroll, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Text('Bookmarks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Add here'),
                onPressed: () => addBookmarkNow(context),
              ),
            ]),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No bookmarks yet. Tap the bookmark button while listening to save a spot.',
                  textAlign: TextAlign.center, style: TextStyle(color: AppColors.textDim)),
            ),
          for (final b in list)
            BookmarkTile(book: book, bookmark: b, onPlayed: () => Navigator.pop(ctx)),
        ]);
      }),
    ),
  );
}
