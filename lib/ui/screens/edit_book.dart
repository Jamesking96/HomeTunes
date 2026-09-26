// The "Edit book" dialog: change an audiobook's title, author, narrator, series and number,
// year, genre and cover, all at once for every file in the book. With several books selected
// (Books tab, right-click / press and hold → Select) it edits them together: title and number in
// series are left out, and details that differ show --:-- and are kept unless changed.
//
// Opened from the book page (book_screen.dart). Nothing is written into the files here: the
// changes are saved as TrackEdits in LibraryModel (edits.json), the same way song and album edits
// work, and can be written into the files later from Settings > Your edits.
// A book's "title" is stored as each file's album name, and its author as artist + album artist.
// On wide windows it's a centred dialog; on phones it fills the screen.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/track_edit.dart';
import '../../state/library_model.dart';
import '../theme.dart';
import '../widgets/book_card.dart';
import 'book_lookup_dialog.dart';
import 'edit_details.dart' show differentMarker;

/// Edits an audiobook's details and cover. Like album edits, the changes are
/// kept by HomeTunes and applied to every file of the book. Returns true if
/// anything was saved.
Future<bool> showEditBook(BuildContext context, Book book) => showEditBooks(context, [book]);

/// Edits several books together (or one, like [showEditBook]). Returns true if anything was saved.
Future<bool> showEditBooks(BuildContext context, List<Book> books) async {
  if (books.isEmpty) return false;
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) {
      final editor = _EditBook(books: books, fullScreen: !wide);
      return wide
          ? Dialog(
              backgroundColor: AppColors.surface,
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580, maxHeight: 780), child: editor),
            )
          : Dialog.fullscreen(backgroundColor: AppColors.bg, child: editor);
    },
  );
  return saved ?? false;
}

/// The text fields on the form.
enum _F { title, author, narrator, series, seriesIndex, year, genre }

/// The editor itself. [fullScreen] picks the phone layout (app bar with Save) over the dialog.
class _EditBook extends StatefulWidget {
  final List<Book> books;
  final bool fullScreen;
  const _EditBook({required this.books, required this.fullScreen});

  @override
  State<_EditBook> createState() => _EditBookState();
}

class _EditBookState extends State<_EditBook> {
  /// One text box per field, filled with the book's current values.
  final Map<_F, TextEditingController> _ctrl = {};
  /// What each field held when the dialog opened, so we only save the ones that changed.
  final Map<_F, String> _initial = {};
  /// A cover picked (or found online) but not saved yet. Path to a copy in the app's art folder.
  String? _newCover;
  /// True when the user chose "Use the files' own cover" (drop any custom cover on save).
  bool _resetCover = false;
  /// True while saving; disables the buttons so it can't be pressed twice.
  bool _saving = false;

  /// The first book (the only one, unless several are being edited).
  Book get _book => widget.books.first;
  /// Several books at once: no title or number in series, and --:-- where they differ.
  bool get _many => widget.books.length > 1;
  /// The ids of every file in the book(s), which all get the same edit.
  List<String> get _ids => [for (final b in widget.books) for (final t in b.parts) t.id];
  /// Fields where the books differ: the box starts empty and shows --:--.
  final Set<_F> _mixed = {};

  /// A field's value for one book, as text for its box.
  static String _valueOf(Book b, _F f) {
    final idx = b.seriesIndex;
    return switch (f) {
      _F.title => b.title,
      _F.author => b.author,
      _F.narrator => b.narrator ?? '',
      _F.series => b.series ?? '',
      // Show "3" rather than "3.0", but keep real decimals like "2.5" (novellas between books).
      _F.seriesIndex => idx == null ? '' : (idx == idx.roundToDouble() ? '${idx.round()}' : '$idx'),
      _F.year => b.year?.toString() ?? '',
      // Genre isn't part of Book, so take it from the first file.
      _F.genre => b.parts.first.genre ?? '',
    };
  }

  @override
  void initState() {
    super.initState();
    for (final f in _F.values) {
      if (_many && (f == _F.title || f == _F.seriesIndex)) continue;
      final values = {for (final b in widget.books) _valueOf(b, f)};
      final common = values.length == 1 ? values.first : '';
      if (values.length > 1) _mixed.add(f);
      _initial[f] = common;
      _ctrl[f] = TextEditingController(text: common);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _label(_F f) => switch (f) {
        _F.title => 'Title',
        _F.author => 'Author',
        _F.narrator => 'Narrator',
        _F.series => 'Series',
        _F.seriesIndex => 'Number in series',
        _F.year => 'Year',
        _F.genre => 'Genre',
      };

  String get _heading => _many ? 'Edit ${widget.books.length} books' : 'Edit book';

  /// A field's text, trimmed ('' for a field that isn't shown).
  String _text(_F f) => _ctrl[f]?.text.trim() ?? '';
  /// Whether a field should be saved: a --:-- box once something is typed in it,
  /// any other box once it differs from what it held when the dialog opened.
  bool _changed(_F f) {
    if (!_ctrl.containsKey(f)) return false;
    return _mixed.contains(f) ? _text(f).isNotEmpty : _text(f) != _initial[f];
  }

  /// "Choose image…": pick a picture file and copy it into the app's own cover folder
  /// (so the cover still works if the original picture is moved).
  Future<void> _pickCover() async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await FilePicker.pickFile(type: FileType.image, dialogTitle: 'Choose a cover image');
      final path = file?.path;
      if (path == null) return;
      final copy = await lib.importCover(path);
      if (!mounted) return;
      setState(() {
        _newCover = copy;
        _resetCover = false;
      });
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t use that image: $e')));
    }
  }

  /// "Find online…" for the cover: search Open Library covers by the typed title and author.
  Future<void> _findCover() async {
    final path = await showBookCoverSearch(context, title: _text(_F.title), author: _text(_F.author));
    if (path == null || !mounted) return;
    setState(() {
      _newCover = path;
      _resetCover = false;
    });
  }

  /// "Find online" for title / author / year: pick a matching book on Open Library.
  Future<void> _lookUp(_F f) async {
    final match = await showBookLookup(context, title: _text(_F.title), author: _text(_F.author));
    if (match == null || !mounted) return;
    // Only the field whose button was pressed is filled in; the others are left as typed.
    setState(() {
      switch (f) {
        case _F.title:
          _ctrl[f]!.text = match.title;
        case _F.author:
          _ctrl[f]!.text = match.author;
        case _F.year:
          if (match.year != null) _ctrl[f]!.text = '${match.year}';
        default:
          break;
      }
    });
  }

  /// The Save button. HomeTunes (0.1.16): a failed save used to leave the dialog stuck on its
  /// spinner; now the error is shown and the dialog stays open so nothing typed is lost.
  Future<void> _save() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await _saveChanges();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Couldn\'t save the changes: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Saves only the fields that changed as one edit applied to every file of the book.
  Future<void> _saveChanges() async {
    final lib = context.read<LibraryModel>();
    String? changed(_F f) => _changed(f) ? _text(f) : null;
    // Title and author can't be emptied; narrator and series can ("" = none).
    String? required(_F f) {
      final v = changed(f);
      return (v == null || v.isEmpty) ? null : v;
    }

    // The book's author is stored as both the artist and the album artist of each file.
    final author = required(_F.author);
    final seriesText = changed(_F.seriesIndex);
    final patch = TrackEdit(
      // The book title lives in the files' album field.
      album: required(_F.title),
      artist: author,
      albumArtist: author,
      narrator: changed(_F.narrator),
      series: changed(_F.series),
      // Accept "2,5" as well as "2.5" for the number in the series.
      seriesIndex: seriesText == null ? null : double.tryParse(seriesText.replaceAll(',', '.')),
      year: changed(_F.year) == null ? null : int.tryParse(_text(_F.year)),
      genre: required(_F.genre),
      art: _newCover,
      // Emptying the number in series or the year removes it (0.1.16; it used to count as
      // "no change", so they couldn't be cleared).
      cleared: {
        if (seriesText != null && seriesText.isEmpty) 'seriesIndex',
        if (changed(_F.year) == '') 'year',
      },
    );
    // Order: reset the cover first, so a newly chosen cover (in the patch) wins.
    if (_resetCover) await lib.resetCovers(_ids);
    if (!patch.isEmpty) await lib.editMany(_ids, patch);
    // A new genre could stop the files counting as a book: keep them in Books.
    if (patch.genre != null) await lib.setIsBook(_ids, true);
  }

  /// "Reset to file details": removes all of the user's edits for this book's files.
  Future<void> _resetAll() async {
    final lib = context.read<LibraryModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to file details?'),
        content: Text(_many
            ? 'Your changes to these ${widget.books.length} books will be removed and they will show the details from '
                'their files (and folder names) again.'
            : 'Your changes to this book will be removed and it will show the details from its files '
                '(and folder names) again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (ok != true) return;
    await lib.resetEdits(_ids);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    // Used to decide whether to offer "Reset to file details" and "Use the files' own cover".
    final parts = [for (final b in widget.books) ...b.parts];
    final anyEdited = parts.any((t) => lib.isEdited(t.id));
    final coversDiffer = _many && {for (final b in widget.books) b.artTrack?.art}.length > 1;
    final anyCustomCover = parts.any((t) {
      final o = lib.originalById(t.id);
      return o != null && t.art != o.art;
    });

    /// Builds one text box. Number fields only accept digits (plus , or . when [decimal]).
    /// [online] adds a "find online" button, if online details lookups are switched on.
    Widget field(_F f, {bool number = false, bool decimal = false, bool online = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _ctrl[f],
            keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal) : TextInputType.text,
            inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))] : null,
            textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
            onChanged: _mixed.contains(f) ? (_) => setState(() {}) : null,
            decoration: InputDecoration(
              labelText: _label(f),
              // Where the books differ: --:--, kept unless something is typed.
              floatingLabelBehavior: _mixed.contains(f) ? FloatingLabelBehavior.always : null,
              hintText: _mixed.contains(f) ? differentMarker : null,
              hintStyle: _mixed.contains(f)
                  ? const TextStyle(color: AppColors.textDim, letterSpacing: 2, fontWeight: FontWeight.w600)
                  : null,
              helperText: _mixed.contains(f)
                  ? (_text(f).isEmpty
                      ? 'Different for each book – leave as $differentMarker to keep them'
                      : 'Every book gets this ${_label(f).toLowerCase()}')
                  : switch (f) {
                      _F.narrator => 'Leave empty for none',
                      _F.series => 'Leave empty if it isn\'t part of a series',
                      _ => null,
                    },
              suffixIcon: _mixed.contains(f) && _text(f).isNotEmpty
                  ? IconButton(
                      tooltip: 'Keep each book\'s own ${_label(f).toLowerCase()}',
                      icon: const Icon(Icons.undo, size: 20),
                      onPressed: _saving ? null : () => setState(() => _ctrl[f]!.clear()),
                    )
                  : online && !_many && lib.onlineDetails
                      ? IconButton(
                          tooltip: 'Find ${_label(f).toLowerCase()} online',
                          icon: const Icon(Icons.travel_explore, size: 20),
                          onPressed: _saving ? null : () => _lookUp(f),
                        )
                      : null,
            ),
          ),
        );

    // The cover preview: the newly picked image if there is one, otherwise the current cover.
    Widget preview;
    if (_newCover != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(_newCover!), width: 120, height: 120 * bookCoverRatio(context), fit: BoxFit.cover),
      );
    } else {
      preview = BookCover(book: _book, width: 120);
    }

    // ---- The form ----
    final form = ListView(
      shrinkWrap: !widget.fullScreen,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        // Cover row: preview on the left, buttons on the right.
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          preview,
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cover', style: TextStyle(fontWeight: FontWeight.w600)),
              Text(
                  _many
                      ? (coversDiffer && _newCover == null && !_resetCover
                          ? '$differentMarker  Different for each book – choose one to give them all the same cover'
                          : 'Applies to all ${widget.books.length} books')
                      : 'Applies to all ${_book.parts.length} files',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickCover,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose image…'),
                ),
                if (lib.onlineCovers && !_many)
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _findCover,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Find online…'),
                  ),
              ]),
              if ((anyCustomCover || _newCover != null) && !_resetCover)
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _newCover = null;
                            _resetCover = true;
                          }),
                  child: const Text('Use the files\' own cover'),
                ),
              if (_resetCover)
                const Text('The files\' own cover will be used.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          ),
        ]),
        // Then the text fields, with series + number and year + genre sharing a row.
        const SizedBox(height: 16),
        if (!_many) field(_F.title, online: true),
        field(_F.author, online: true),
        field(_F.narrator),
        if (_many)
          field(_F.series)
        else
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: field(_F.series)),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: field(_F.seriesIndex, number: true, decimal: true)),
          ]),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: field(_F.year, number: true, online: true)),
          const SizedBox(width: 12),
          Expanded(child: field(_F.genre)),
        ]),
        const SizedBox(height: 6),
        Text(
          _many
              ? 'Changes are saved in HomeTunes and apply to every file of these books. Author, year, genre and '
                  'cover can also be written into the files from Settings › Your edits.'
              : 'Changes are saved in HomeTunes and apply to every file of the book. Title, author, year, genre and '
                  'cover can also be written into the files from Settings › Your edits.',
          style: const TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
        if (anyEdited) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _saving ? null : _resetAll,
              icon: const Icon(Icons.restore),
              label: const Text('Reset to file details'),
            ),
          ),
        ],
      ],
    );

    final saveButton = FilledButton(
      onPressed: _saving ? null : _save,
      child: _saving
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('Save'),
    );

    // Phone layout: an app bar with a close (x) button and Save.
    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
          title: Text(_heading),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: saveButton)],
        ),
        body: form,
      );
    }
    // Dialog layout: title bar, the scrolling form, and Cancel / Save at the bottom.
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
        child: Row(children: [
          Expanded(child: Text(_heading, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
        ]),
      ),
      Flexible(child: form),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          const SizedBox(width: 8),
          saveButton,
        ]),
      ),
    ]);
  }
}
