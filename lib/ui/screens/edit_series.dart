// Edit series (0.1.76, the user: "We might need a method to edit series like how we do with
// video collections"), opened from a series' page or its menu:
//  * Name: renames the series on every book (its picture, description, favourite and sidebar
//    link come along);
//  * Author: the author of every book in it (left alone unless changed);
//  * Description: the series' own;
//  * Books: drag them into order (numbered 1, 2, 3… when saved), take one out with ✕, or
//    Add books… from the rest of the library.
// Like Edit book and Edit collection, the changes are saved as HomeTunes edits on the books'
// files (LibraryModel.editSeries); the files themselves aren't changed.
//
// Change picture… (showSeriesPictureOptions): an image file, one of its books' covers, or back to
// the first book's cover, like an artist's picture.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../state/book_index.dart';
import '../../state/library_model.dart';
import '../../state/playlists_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import 'series_screen.dart' show SeriesScreen;

/// Opens Edit series. Returns the series' name after saving (new if it was renamed), or null if
/// nothing was saved.
Future<String?> showEditSeries(BuildContext context, BookSeries series) {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (_) {
      final editor = _EditSeries(series: series, fullScreen: !wide);
      return wide
          ? Dialog(
              backgroundColor: AppColors.surface,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600, maxHeight: 800), child: editor),
            )
          : Dialog.fullscreen(backgroundColor: AppColors.bg, child: editor);
    },
  );
}

class _EditSeries extends StatefulWidget {
  final BookSeries series;
  final bool fullScreen;
  const _EditSeries({required this.series, required this.fullScreen});

  @override
  State<_EditSeries> createState() => _EditSeriesState();
}

class _EditSeriesState extends State<_EditSeries> {
  late final _name = TextEditingController(text: widget.series.name);
  late final _author = TextEditingController(text: _sameAuthor ?? '');
  late final _description =
      TextEditingController(text: context.read<LibraryModel>().seriesDescription(widget.series.name) ?? '');

  /// The books in the order shown (drag to change), without any taken out, with any added.
  late final List<Book> _books = [...widget.series.books];
  final _added = <Book>[];
  final _removed = <Book>[];
  bool _reordered = false;
  bool _saving = false;

  /// The author, when every book has the same one.
  String? get _sameAuthor {
    final authors = widget.series.authors;
    return authors.length == 1 ? authors.single : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _author.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(const SnackBar(content: Text('A series needs a name.')));
      return;
    }
    final lib = context.read<LibraryModel>();
    final playlists = context.read<PlaylistsModel>();
    final old = widget.series.name;
    final author = _author.text.trim();
    final description = _description.text.trim();
    final descriptionChanged = description != (lib.seriesDescription(old) ?? '');
    setState(() => _saving = true);
    try {
      await lib.editSeries(
        widget.series,
        name: name,
        author: author.isNotEmpty && author != (_sameAuthor ?? '') ? author : null,
        // Dragged: everything shown is numbered 1, 2, 3… in that order (added books too).
        order: _reordered ? _books : null,
        add: _added,
        remove: _removed,
      );
      if (name != old) playlists.renameFavouriteSeries(old, name);
      if (descriptionChanged) await lib.setSeriesDescription(name, description);
      if (mounted) Navigator.of(context).pop(name);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text('Couldn\'t save the changes: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _remove(Book b) => setState(() {
        _books.remove(b);
        if (!_added.remove(b)) _removed.add(b);
      });

  Future<void> _addBooks() async {
    final picked = await _pickBooks(context, exclude: {for (final b in _books) b.id});
    if (picked == null || picked.isEmpty) return;
    setState(() {
      for (final b in picked) {
        _removed.removeWhere((x) => x.id == b.id);
        if (widget.series.books.any((x) => x.id == b.id)) {
          _books.add(b); // taken out and put back
        } else {
          _books.add(b);
          _added.add(b);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration field(String label, {String? hint}) => InputDecoration(labelText: label, hintText: hint);
    final multipleAuthors = widget.series.authors.length > 1;
    final form = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        TextField(key: const ValueKey('series-edit-name'), controller: _name, decoration: field('Name')),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('series-edit-author'),
          controller: _author,
          decoration: field('Author',
              hint: multipleAuthors ? '${widget.series.authors.join(', ')} (type one to use it for every book)' : null),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('series-edit-description'),
          controller: _description,
          minLines: 2,
          maxLines: 6,
          decoration: field('Description'),
        ),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
            child: Text('Books (${_books.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          TextButton.icon(
            key: const ValueKey('series-edit-add'),
            icon: const Icon(Icons.add),
            label: const Text('Add books…'),
            onPressed: _addBooks,
          ),
        ]),
        Text('Drag to change the order. Books are numbered 1, 2, 3… in this order when you save.',
            style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _books.length,
          onReorderItem: (from, to) => setState(() {
            _books.insert(to, _books.removeAt(from));
            _reordered = true;
          }),
          itemBuilder: (context, i) {
            final b = _books[i];
            final number = SeriesScreen.numberOf(b);
            return ListTile(
              key: ValueKey('series-edit-book:${b.id}'),
              contentPadding: EdgeInsets.zero,
              leading: ReorderableDragStartListener(
                index: i,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.drag_indicator),
                  const SizedBox(width: 8),
                  BookCover(book: b, width: 36, radius: 4),
                ]),
              ),
              title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  ?(_added.contains(b) ? 'Adding' : number),
                  b.author,
                ].join(' · '),
                style: TextStyle(color: AppColors.textDim, fontSize: 12),
              ),
              trailing: IconButton(
                key: ValueKey('series-edit-remove:${b.id}'),
                tooltip: 'Take out of the series',
                icon: const Icon(Icons.close),
                onPressed: () => _remove(b),
              ),
            );
          },
        ),
        if (_removed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Taking out: ${_removed.map((b) => b.title).join(', ')}',
              style: TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
          ),
      ],
    );

    final save = FilledButton(
      key: const ValueKey('series-edit-save'),
      onPressed: _saving ? null : _save,
      child: const Text('Save'),
    );
    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Edit series'),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: save)],
        ),
        body: form,
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
        child: Text('Edit series', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
      ),
      Expanded(child: form),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          const SizedBox(width: 8),
          save,
        ]),
      ),
    ]);
  }
}

/// Add books…: every book not already shown, with a box to find them; tick and press Add.
Future<List<Book>?> _pickBooks(BuildContext context, {required Set<String> exclude}) {
  final books = [
    for (final b in context.read<LibraryModel>().books)
      if (!exclude.contains(b.id)) b
  ]..sort((a, b) => naturalCompare(a.title, b.title));
  return showDialog<List<Book>>(
    context: context,
    builder: (ctx) => _BookPicker(books: books),
  );
}

class _BookPicker extends StatefulWidget {
  final List<Book> books;
  const _BookPicker({required this.books});

  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  String _query = '';
  final _picked = <Book>[];

  @override
  Widget build(BuildContext context) {
    final shown = _query.trim().isEmpty ? widget.books : searchBookList(widget.books, _query);
    return AlertDialog(
      title: const Text('Add books to the series'),
      content: SizedBox(
        width: 480,
        height: 420,
        child: Column(children: [
          TextField(
            key: const ValueKey('series-add-search'),
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Title, author or series'),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text('No books match.', style: TextStyle(color: AppColors.textDim)))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (_, i) {
                      final b = shown[i];
                      return CheckboxListTile(
                        key: ValueKey('series-add-book:${b.id}'),
                        value: _picked.contains(b),
                        onChanged: (on) => setState(() => on == true ? _picked.add(b) : _picked.remove(b)),
                        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([b.author, ?b.seriesLabel].join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const ValueKey('series-add-confirm'),
          onPressed: _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked),
          child: Text(_picked.isEmpty ? 'Add' : 'Add ${_picked.length}'),
        ),
      ],
    );
  }
}

/// Change picture… for a series: an image file, one of its books' covers, or back to automatic
/// (its first book's cover).
Future<void> showSeriesPictureOptions(BuildContext context, BookSeries series) async {
  final lib = context.read<LibraryModel>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  Widget option(BuildContext ctx, String value, IconData icon, String label, String detail) => SimpleDialogOption(
        key: ValueKey('series-picture-$value'),
        onPressed: () => Navigator.of(ctx).pop(value),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon),
          title: Text(label),
          subtitle: Text(detail, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
        ),
      );
  final n = series.books.length;
  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text('Picture for ${series.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
      children: [
        option(ctx, 'file', Icons.image_outlined, 'Choose an image file…', 'A photo or picture you already have'),
        option(ctx, 'book', Icons.menu_book_outlined, 'Use one of its book covers…',
            '$n book${n == 1 ? '' : 's'} to pick from'),
        if (lib.hasSeriesPicture(series.name))
          option(ctx, 'auto', Icons.restore, 'Use the automatic picture', 'The first book\'s cover'),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'auto':
      await lib.setSeriesPicture(series.name);
      messenger?.showSnackBar(const SnackBar(content: Text('Back to the automatic picture')));
    case 'book':
      final book = await _pickCover(context, series);
      if (book == null) return;
      await lib.setSeriesPicture(series.name, book: book);
      messenger?.showSnackBar(SnackBar(content: Text('${series.name} now shows "${book.title}"')));
    case 'file':
      try {
        final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a picture for ${series.name}');
        final path = file?.path;
        if (path == null) return;
        final copy = await lib.importCover(path);
        await lib.setSeriesPicture(series.name, file: copy);
        messenger?.showSnackBar(SnackBar(content: Text('New picture for ${series.name}')));
      } catch (e) {
        messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that picture: $e')));
      }
  }
}

/// A grid of the series' book covers; returns the one tapped (null if closed).
Future<Book?> _pickCover(BuildContext context, BookSeries series) {
  return showDialog<Book>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Pick a cover for ${series.name}', maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: GridView.extent(
          shrinkWrap: true,
          maxCrossAxisExtent: 140,
          childAspectRatio: 0.62,
          children: [
            for (final b in series.books)
              InkWell(
                key: ValueKey('series-cover-pick:${b.id}'),
                borderRadius: AppShape.circular(8),
                onTap: () => Navigator.of(ctx).pop(b),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: LayoutBuilder(
                    builder: (_, c) => Column(children: [
                      BookCover(book: b, width: c.maxWidth),
                      const SizedBox(height: 4),
                      Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel'))],
    ),
  );
}
