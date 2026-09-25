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

/// Edits an audiobook's details and cover. Like album edits, the changes are
/// kept by HomeTunes and applied to every file of the book. Returns true if
/// anything was saved.
Future<bool> showEditBook(BuildContext context, Book book) async {
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final saved = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (_) {
      final editor = _EditBook(book: book, fullScreen: !wide);
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

enum _F { title, author, narrator, series, seriesIndex, year, genre }

class _EditBook extends StatefulWidget {
  final Book book;
  final bool fullScreen;
  const _EditBook({required this.book, required this.fullScreen});

  @override
  State<_EditBook> createState() => _EditBookState();
}

class _EditBookState extends State<_EditBook> {
  final Map<_F, TextEditingController> _ctrl = {};
  final Map<_F, String> _initial = {};
  String? _newCover;
  bool _resetCover = false;
  bool _saving = false;

  Book get _book => widget.book;
  List<String> get _ids => [for (final t in _book.parts) t.id];

  @override
  void initState() {
    super.initState();
    final idx = _book.seriesIndex;
    final values = {
      _F.title: _book.title,
      _F.author: _book.author,
      _F.narrator: _book.narrator ?? '',
      _F.series: _book.series ?? '',
      _F.seriesIndex: idx == null ? '' : (idx == idx.roundToDouble() ? '${idx.round()}' : '$idx'),
      _F.year: _book.year?.toString() ?? '',
      _F.genre: _book.parts.first.genre ?? '',
    };
    for (final e in values.entries) {
      _initial[e.key] = e.value;
      _ctrl[e.key] = TextEditingController(text: e.value);
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

  String _text(_F f) => _ctrl[f]!.text.trim();
  bool _changed(_F f) => _text(f) != _initial[f];

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

  Future<void> _save() async {
    final lib = context.read<LibraryModel>();
    setState(() => _saving = true);
    String? changed(_F f) => _changed(f) ? _text(f) : null;
    // Title and author can't be emptied; narrator and series can ("" = none).
    String? required(_F f) {
      final v = changed(f);
      return (v == null || v.isEmpty) ? null : v;
    }

    final author = required(_F.author);
    final seriesText = changed(_F.seriesIndex);
    final patch = TrackEdit(
      album: required(_F.title),
      artist: author,
      albumArtist: author,
      narrator: changed(_F.narrator),
      series: changed(_F.series),
      seriesIndex: seriesText == null ? null : double.tryParse(seriesText.replaceAll(',', '.')),
      year: changed(_F.year) == null ? null : int.tryParse(_text(_F.year)),
      genre: required(_F.genre),
      art: _newCover,
    );
    if (_resetCover) await lib.resetCovers(_ids);
    if (!patch.isEmpty) await lib.editMany(_ids, patch);
    // A new genre could stop the files counting as a book: keep them in Books.
    if (patch.genre != null) await lib.setIsBook(_ids, true);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _resetAll() async {
    final lib = context.read<LibraryModel>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to file details?'),
        content: const Text('Your changes to this book will be removed and it will show the details from its files '
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
    final anyEdited = _book.parts.any((t) => lib.isEdited(t.id));
    final anyCustomCover = _book.parts.any((t) {
      final o = lib.originalById(t.id);
      return o != null && t.art != o.art;
    });

    Widget field(_F f, {bool number = false, bool decimal = false, bool online = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _ctrl[f],
            keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal) : TextInputType.text,
            inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.,]' : r'[0-9]'))] : null,
            textCapitalization: number ? TextCapitalization.none : TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _label(f),
              helperText: switch (f) {
                _F.narrator => 'Leave empty for none',
                _F.series => 'Leave empty if it isn\'t part of a series',
                _ => null,
              },
              suffixIcon: online && lib.onlineDetails
                  ? IconButton(
                      tooltip: 'Find ${_label(f).toLowerCase()} online',
                      icon: const Icon(Icons.travel_explore, size: 20),
                      onPressed: _saving ? null : () => _lookUp(f),
                    )
                  : null,
            ),
          ),
        );

    Widget preview;
    if (_newCover != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(File(_newCover!), width: 120, height: 120 * bookCoverRatio(context), fit: BoxFit.cover),
      );
    } else {
      preview = BookCover(book: _book, width: 120);
    }

    final form = ListView(
      shrinkWrap: !widget.fullScreen,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          preview,
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cover', style: TextStyle(fontWeight: FontWeight.w600)),
              Text('Applies to all ${_book.parts.length} files',
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickCover,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose image…'),
                ),
                if (lib.onlineCovers)
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
        const SizedBox(height: 16),
        field(_F.title, online: true),
        field(_F.author, online: true),
        field(_F.narrator),
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
        const Text(
          'Changes are saved in HomeTunes and apply to every file of the book. Title, author, year, genre and '
          'cover can also be written into the files from Settings › Your edits.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
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

    if (widget.fullScreen) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context, false)),
          title: const Text('Edit book'),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: saveButton)],
        ),
        body: form,
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
        child: Row(children: [
          const Expanded(child: Text('Edit book', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
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
