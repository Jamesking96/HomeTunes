import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/book_info.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Searches Open Library for a book cover and lets the user pick one.
/// Returns the saved image's path, or null.
Future<String?> showBookCoverSearch(BuildContext context, {String? title, String? author}) async {
  final r = await showDialog<Object>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _BookLookupDialog(title: title ?? '', author: author ?? '', covers: true),
  );
  return r is String ? r : null;
}

/// Searches Open Library for a book and returns the one the user picked, so
/// its title, author or year can be used.
Future<BookMatch?> showBookLookup(BuildContext context, {String? title, String? author}) async {
  final r = await showDialog<Object>(
    context: context,
    useRootNavigator: true,
    builder: (_) => _BookLookupDialog(title: title ?? '', author: author ?? '', covers: false),
  );
  return r is BookMatch ? r : null;
}

class _BookLookupDialog extends StatefulWidget {
  final String title, author;
  final bool covers;
  const _BookLookupDialog({required this.title, required this.author, required this.covers});

  @override
  State<_BookLookupDialog> createState() => _BookLookupDialogState();
}

class _BookLookupDialogState extends State<_BookLookupDialog> {
  final _search = BookInfoSearch();
  late final _title = TextEditingController(text: widget.title);
  late final _author = TextEditingController(text: widget.author);
  List<BookMatch>? _results;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _search.close();
    super.dispose();
  }

  Future<void> _run() async {
    final t = _title.text.trim();
    final a = _author.text.trim();
    if (t.isEmpty && a.isEmpty) {
      setState(() => _error = 'Enter a title or author to search.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = widget.covers ? await _search.searchCovers(title: t, author: a) : await _search.search(title: t, author: a);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Couldn\'t search online. Check your internet connection.\n($e)';
      });
    }
  }

  Future<void> _chooseCover(BookMatch b) async {
    final lib = context.read<LibraryModel>();
    setState(() => _saving = true);
    try {
      final bytes = await _search.downloadCover(b);
      final path = await lib.importCoverBytes(bytes);
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Couldn\'t download that cover. ($e)';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    Widget body;
    if (_loading || _saving) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_saving ? 'Saving cover…' : 'Searching…', style: const TextStyle(color: AppColors.textDim)),
        ]),
      );
    } else if (_error != null) {
      body = Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textDim)));
    } else if (results == null || results.isEmpty) {
      body = Center(
        child: Text(
          widget.covers ? 'No covers found. Try adjusting the title or author.' : 'No books found. Try adjusting the title or author.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textDim),
        ),
      );
    } else if (widget.covers) {
      body = GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: 0.55,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
        ),
        itemCount: results.length,
        itemBuilder: (_, i) {
          final b = results[i];
          return InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _chooseCover(b),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.memory(b.thumbnail!, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              ),
              const SizedBox(height: 4),
              Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              Text([b.author, if (b.year != null) '${b.year}'].join(' · '),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            ]),
          );
        },
      );
    } else {
      body = ListView.builder(
        itemCount: results.length,
        itemBuilder: (_, i) {
          final b = results[i];
          return ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(b.title),
            subtitle: Text([if (b.author.isNotEmpty) b.author, if (b.year != null) 'first published ${b.year}'].join(' · ')),
            onTap: () => Navigator.pop(context, b),
          );
        },
      );
    }

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 660),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(widget.covers ? 'Find book cover online' : 'Find book details online',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: 'Title', isDense: true),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _author,
                  decoration: const InputDecoration(labelText: 'Author', isDense: true),
                  onSubmitted: (_) => _run(),
                ),
              ),
              IconButton(tooltip: 'Search', icon: const Icon(Icons.search), onPressed: _loading ? null : _run),
            ]),
            const SizedBox(height: 12),
            Expanded(child: body),
            const SizedBox(height: 8),
            Text(
              widget.covers ? 'Tap a cover to use it. Covers and details from Open Library.' : 'Tap a book to use its details. From Open Library.',
              style: const TextStyle(color: AppColors.textDim, fontSize: 11),
            ),
          ]),
        ),
      ),
    );
  }
}
