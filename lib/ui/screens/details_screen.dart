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
import '../../services/path_safety.dart';
import '../../state/library_model.dart';
import '../theme.dart';
import '../widgets/always_on_top_button.dart';

/// Opens the Details page for [tracks]: one song, an album's songs, or a book's files.
Future<void> openDetails(
  BuildContext context, {
  required String kind,
  required String title,
  required List<Track> tracks,
  Book? book,
}) => Navigator.of(context, rootNavigator: true).push(
  MaterialPageRoute(
    builder: (_) => DetailsScreen(kind: kind, title: title, tracks: tracks, book: book),
  ),
);

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
    final paths = [
      for (final t in tracks)
        if (t.path != null) t.path!,
    ];
    final folders = {for (final path in paths) p.dirname(path)}.toList()..sort();
    final (isBook, why) = lib.bookRules.why(lib.originalById(first.id) ?? first);
    final many = tracks.length > 1;

    return Scaffold(
      // The pin (0.1.60): this page covers the player bar, where it usually is.
      appBar: AppBar(title: const Text('Details'), actions: const [AlwaysOnTopButton()]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Text(
                kind.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),

              // ---- Where it is ----
              DetailsCard(
                title: 'Where it is',
                children: [
                  if (paths.isEmpty)
                    const DetailsLine(Icons.cloud_outlined, 'Streams from your music server')
                  else ...[
                    for (final f in folders)
                      DetailsFolderLine(folder: f, firstFile: paths.firstWhere((x) => p.dirname(x) == f)),
                    _FilesSummary(paths: paths),
                  ],
                  DetailsLine(
                    isBook ? Icons.menu_book_outlined : Icons.library_music_outlined,
                    '${isBook ? 'In Books' : 'In Music'}: $why${many ? ' (first file)' : ''}',
                  ),
                  if (book != null) ..._bookGuesses(book!),
                ],
              ),
              const SizedBox(height: 16),

              // ---- One file, or the first file plus a list ----
              if (!many)
                _TrackDetails(track: first)
              else ...[
                DetailsCard(
                  title: 'Details and where they come from',
                  subtitle: 'From the first file. Open a file below to see its own.',
                  children: [_TrackDetails(track: first, rowsOnly: true)],
                ),
                const SizedBox(height: 16),
                DetailsCard(
                  title: '${tracks.length} files',
                  children: [
                    for (final t in tracks)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: const EdgeInsets.only(bottom: 12),
                        title: Text(
                          t.path == null ? t.title : p.basename(t.path!),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.textDim, fontSize: 12),
                        ),
                        children: [_TrackDetails(track: t, flat: true)],
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Book details that weren't in any file but worked out from folder names.
  static List<Widget> _bookGuesses(Book b) {
    final fromFiles = b.parts.first;
    return [
      if (b.series != null && fromFiles.series == null)
        DetailsLine(Icons.lightbulb_outline, 'Series "${b.series}" was worked out from the folder names'),
      if (b.narrator != null && fromFiles.narrator == null)
        DetailsLine(Icons.lightbulb_outline, 'Narrator "${b.narrator}" was worked out from the folder names'),
    ];
  }
}

/// A section with a heading.
class DetailsCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const DetailsCard({super.key, required this.title, this.subtitle, required this.children});

  // A Material (not a coloured box), so the rows that open inside it show their tap ripple.
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    borderRadius: AppShape.circular(12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(subtitle!, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}

class DetailsLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const DetailsLine(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(text)),
      ],
    ),
  );
}

/// A folder, with "Show in folder" on Windows.
class DetailsFolderLine extends StatelessWidget {
  final String folder;
  final String firstFile;

  /// The folders "Show in folder" may open files in: the music folders unless given (the video
  /// Details page passes the video folders).
  final List<String>? roots;
  const DetailsFolderLine({super.key, required this.folder, required this.firstFile, this.roots});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.folder_outlined, size: 18, color: AppColors.textDim),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(folder)),
        if (Platform.isWindows)
          TextButton(
            onPressed: () {
              // 0.1.21 (security review #3): only files inside the library folders.
              final allowed = roots ?? context.read<LibraryModel>().libraryFolders;
              if (!isUsableLocalFile(firstFile, roots: allowed)) return;
              Process.run('explorer', ['/select,', p.normalize(firstFile)]);
            },
            child: const Text('Show in folder'),
          ),
      ],
    ),
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
    builder: (_, s) => DetailsLine(Icons.insert_drive_file_outlined, s.data ?? '${paths.length} files'),
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
      final table = DetailsTable(rows: d.rows);
      if (widget.rowsOnly) return table;
      final parts = <Widget>[
        if (d.problem != null) DetailsLine(Icons.warning_amber_outlined, d.problem!),
        if (!d.isServer)
          DetailsLine(
            Icons.insert_drive_file_outlined,
            '${d.fileName} · ${d.format}${d.sizeBytes != null ? ' · ${fileSize(d.sizeBytes!)}' : ''}'
            '${d.modified != null ? ' · changed ${_date(d.modified!)}' : ''}',
          ),
      ];
      final inFile = [for (final (k, v) in d.inFile) DetailsPair(k, v)];
      final beside = [for (final (name, use) in d.besideIt) DetailsPair(use, name)];
      if (widget.flat) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...parts,
            const SizedBox(height: 8),
            table,
            if (inFile.isNotEmpty) ...[const DetailsHeading('What the file\'s tags say'), ...inFile],
            if (beside.isNotEmpty) ...[const DetailsHeading('Files beside it that HomeTunes uses'), ...beside],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (parts.isNotEmpty) ...[DetailsCard(title: 'The file', children: parts), const SizedBox(height: 16)],
          DetailsCard(title: 'Details and where they come from', children: [table]),
          if (inFile.isNotEmpty) ...[
            const SizedBox(height: 16),
            DetailsCard(
              title: 'What the file\'s tags say',
              subtitle: 'Read from the file just now, before any of your edits.',
              children: inFile,
            ),
          ],
          if (beside.isNotEmpty) ...[
            const SizedBox(height: 16),
            DetailsCard(title: 'Files beside it that HomeTunes uses', children: beside),
          ],
        ],
      );
    },
  );

  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class DetailsHeading extends StatelessWidget {
  final String text;
  const DetailsHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
  );
}

class DetailsPair extends StatelessWidget {
  final String label;
  final String value;
  const DetailsPair(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: TextStyle(color: AppColors.textDim)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

/// Detail · what's shown · where it came from.
class DetailsTable extends StatelessWidget {
  final List<DetailRow> rows;
  const DetailsTable({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 520;
        Widget source(DetailRow r) {
          final edited = r.source == DetailSource.edit;
          return Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: edited ? accent.withValues(alpha: 0.18) : AppColors.surfaceHigh,
                  borderRadius: AppShape.circular(999),
                ),
                child: Text(
                  r.source.label,
                  style: TextStyle(
                    fontSize: 12,
                    color: edited ? accent : AppColors.textDim,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (r.from != null) Text(r.from!, style: TextStyle(fontSize: 12, color: AppColors.textDim)),
              if (r.inFile != null)
                Text('File says: ${r.inFile}', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          );
        }

        return Column(
          children: [
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.label, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
                          SelectableText(r.shown),
                          const SizedBox(height: 4),
                          source(r),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 140,
                            child: Text(r.label, style: TextStyle(color: AppColors.textDim)),
                          ),
                          Expanded(flex: 3, child: SelectableText(r.shown)),
                          const SizedBox(width: 12),
                          Expanded(flex: 3, child: source(r)),
                        ],
                      ),
              ),
          ],
        );
      },
    );
  }
}
