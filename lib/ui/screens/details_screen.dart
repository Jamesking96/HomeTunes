// The Details page: where a song, album or audiobook comes from. It shows the folder and
// files, why it's in Music or Books, every detail HomeTunes shows with where that detail came
// from (the file's tags, a book details file, the folder name, your edit…), what the file
// itself contains, and the other files beside it that HomeTunes uses.
//
// Opened from "Details" in a song's ⋮ menu, an album or book's right-click / press-and-hold
// menu, and the ⓘ buttons on album and book pages. It only reads; nothing is changed.
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../models/book.dart';
import '../../models/track.dart';
import '../../services/media_details.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Opens the Details page for [tracks]: one song, an album's songs, or a book's files.
Future<void> openDetails(BuildContext context,
        {required String kind, required String title, required List<Track> tracks, Book? book}) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => DetailsScreen(kind: kind, title: title, tracks: tracks, book: book),
    ));

class DetailsScreen extends StatelessWidget {
  final String kind; // "Song", "Album", "Book", "3 albums"…
  final String title;
  final List<Track> tracks;
  final Book? book;
  const DetailsScreen({super.key, required this.kind, required this.title, required this.tracks, this.book});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final first = tracks.first;
    final paths = [for (final t in tracks) if (t.path != null) t.path!];
    final folders = {for (final path in paths) p.dirname(path)}.toList()..sort();
    final (isBook, why) = lib.bookRules.why(lib.originalById(first.id) ?? first);
    final many = tracks.length > 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Details')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            Text(kind.toUpperCase(),
                style: TextStyle(
                    fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 4),
            SelectableText(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),

            // ---- Where it is ----
            _Card(title: 'Where it is', children: [
              if (paths.isEmpty)
                const _Line(Icons.cloud_outlined, 'Streams from your music server')
              else ...[
                for (final f in folders) _FolderLine(folder: f, firstFile: paths.firstWhere((x) => p.dirname(x) == f)),
                _FilesSummary(paths: paths),
              ],
              _Line(isBook ? Icons.menu_book_outlined : Icons.library_music_outlined,
                  '${isBook ? 'In Books' : 'In Music'}: $why${many ? ' (first file)' : ''}'),
              if (book != null) ..._bookGuesses(book!),
            ]),
            const SizedBox(height: 16),

            // ---- One file, or the first file plus a list ----
            if (!many)
              _TrackDetails(track: first)
            else ...[
              _Card(
                title: 'Details and where they come from',
                subtitle: 'From the first file. Open a file below to see its own.',
                children: [_TrackDetails(track: first, rowsOnly: true)],
              ),
              const SizedBox(height: 16),
              _Card(title: '${tracks.length} files', children: [
                for (final t in tracks)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    title: Text(t.path == null ? t.title : p.basename(t.path!), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                    children: [_TrackDetails(track: t, flat: true)],
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  /// Book details that weren't in any file but worked out from folder names.
  static List<Widget> _bookGuesses(Book b) {
    final fromFiles = b.parts.first;
    return [
      if (b.series != null && fromFiles.series == null)
        _Line(Icons.lightbulb_outline, 'Series "${b.series}" was worked out from the folder names'),
      if (b.narrator != null && fromFiles.narrator == null)
        _Line(Icons.lightbulb_outline, 'Narrator "${b.narrator}" was worked out from the folder names'),
    ];
  }
}

/// A section with a heading.
class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Card({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          ...children,
        ]),
      );
}

class _Line extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Line(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(text)),
        ]),
      );
}

/// A folder, with "Show in folder" on Windows.
class _FolderLine extends StatelessWidget {
  final String folder;
  final String firstFile;
  const _FolderLine({required this.folder, required this.firstFile});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          const Icon(Icons.folder_outlined, size: 18, color: AppColors.textDim),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(folder)),
          if (Platform.isWindows)
            TextButton(
              onPressed: () => Process.run('explorer', ['/select,', firstFile]),
              child: const Text('Show in folder'),
            ),
        ]),
      );
}

/// "12 files · MP3 · 84.2 MB", worked out in the background.
class _FilesSummary extends StatelessWidget {
  final List<String> paths;
  const _FilesSummary({required this.paths});

  static Future<String> _summary(List<String> paths) => Isolate.run(() {
        var size = 0, missing = 0;
        for (final x in paths) {
          final f = File(x);
          if (f.existsSync()) {
            size += f.lengthSync();
          } else {
            missing++;
          }
        }
        final formats = {for (final x in paths) p.extension(x).replaceFirst('.', '').toUpperCase()}.toList()..sort();
        final n = paths.length;
        return '$n file${n == 1 ? '' : 's'} · ${formats.join(', ')} · ${fileSize(size)}'
            '${missing > 0 ? ' · $missing not found' : ''}';
      });

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
        future: _summary(paths),
        builder: (_, s) => _Line(Icons.insert_drive_file_outlined, s.data ?? '${paths.length} files'),
      );
}

/// One file's details: the table of details and their sources, what's in the file, and
/// the files beside it. [rowsOnly] shows just the table; [flat] leaves out the cards.
class _TrackDetails extends StatefulWidget {
  final Track track;
  final bool rowsOnly;
  final bool flat;
  const _TrackDetails({required this.track, this.rowsOnly = false, this.flat = false});

  @override
  State<_TrackDetails> createState() => _TrackDetailsState();
}

class _TrackDetailsState extends State<_TrackDetails> {
  late final Future<FileDetails> _details;

  @override
  void initState() {
    super.initState();
    final lib = context.read<LibraryModel>();
    final shown = lib.byId(widget.track.id) ?? widget.track;
    final scanned = lib.originalById(widget.track.id) ?? widget.track;
    _details = inspectTrack(shown: shown, scanned: scanned, artDir: lib.storage.artDir);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<FileDetails>(
        future: _details,
        builder: (context, snap) {
          if (snap.hasError) return Text('Couldn\'t read the details: ${snap.error}');
          final d = snap.data;
          if (d == null) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
            );
          }
          final table = _Table(details: d);
          if (widget.rowsOnly) return table;
          final parts = <Widget>[
            if (d.problem != null) _Line(Icons.warning_amber_outlined, d.problem!),
            if (!d.isServer)
              _Line(Icons.insert_drive_file_outlined,
                  '${d.fileName} · ${d.format}${d.sizeBytes != null ? ' · ${fileSize(d.sizeBytes!)}' : ''}'
                  '${d.modified != null ? ' · changed ${_date(d.modified!)}' : ''}'),
          ];
          final inFile = [
            for (final (k, v) in d.inFile) _Pair(k, v),
          ];
          final beside = [
            for (final (name, use) in d.besideIt) _Pair(use, name),
          ];
          if (widget.flat) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...parts,
              const SizedBox(height: 8),
              table,
              if (inFile.isNotEmpty) ...[const _Heading('What the file\'s tags say'), ...inFile],
              if (beside.isNotEmpty) ...[const _Heading('Files beside it that HomeTunes uses'), ...beside],
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (parts.isNotEmpty) ...[_Card(title: 'The file', children: parts), const SizedBox(height: 16)],
            _Card(title: 'Details and where they come from', children: [table]),
            if (inFile.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Card(
                title: 'What the file\'s tags say',
                subtitle: 'Read from the file just now, before any of your edits.',
                children: inFile,
              ),
            ],
            if (beside.isNotEmpty) ...[
              const SizedBox(height: 16),
              _Card(title: 'Files beside it that HomeTunes uses', children: beside),
            ],
          ]);
        },
      );

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
      );
}

class _Pair extends StatelessWidget {
  final String label;
  final String value;
  const _Pair(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(label, style: const TextStyle(color: AppColors.textDim))),
          Expanded(child: SelectableText(value)),
        ]),
      );
}

/// Detail · what's shown · where it came from.
class _Table extends StatelessWidget {
  final FileDetails details;
  const _Table({required this.details});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(builder: (context, c) {
      final narrow = c.maxWidth < 520;
      Widget source(DetailRow r) {
        final edited = r.source == DetailSource.edit;
        return Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: edited ? accent.withValues(alpha: 0.18) : AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(r.source.label,
                style: TextStyle(fontSize: 12, color: edited ? accent : AppColors.textDim, fontWeight: FontWeight.w600)),
          ),
          if (r.from != null) Text(r.from!, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
          if (r.inFile != null) Text('File says: ${r.inFile}', style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
        ]);
      }

      return Column(children: [
        for (final r in details.rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: narrow
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.label, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
                    SelectableText(r.shown),
                    const SizedBox(height: 4),
                    source(r),
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 140, child: Text(r.label, style: const TextStyle(color: AppColors.textDim))),
                    Expanded(flex: 3, child: SelectableText(r.shown)),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: source(r)),
                  ]),
          ),
      ]);
    });
  }
}
