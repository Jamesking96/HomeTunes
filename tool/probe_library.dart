// Shows how HomeTunes would group a folder into audiobooks, using the app's
// own scanner and book rules. Usage: dart run tool/probe_library.dart <folder>
//
// A developer tool: like probe_book_extras.dart but focused on the grouping itself (author,
// narrator, series, chapter count, first/last chapter titles). The whole folder is treated as
// a books folder. Covers go to a temp folder that is deleted at the end.
import 'dart:io';

import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/state/book_index.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_library.dart <folder>');
    exit(64);
  }
  final art = Directory.systemTemp.createTempSync('hometunes_probe');
  final scanner = LocalScanner(art.path);
  final tracks = await scanner.scan([args.first]);
  // Every file under the given folder counts as a book file.
  final rules = BookRules(bookFolders: [args.first]);
  final books = groupBooks(tracks.where(rules.isBook));
  stdout.writeln('${tracks.length} files, ${books.length} books');
  for (final b in books) {
    stdout.writeln('- ${b.title}');
    stdout.writeln('    author: ${b.author} | narrator: ${b.narrator} | series: ${b.seriesLabel} | year: ${b.year}');
    final ch = b.chapters;
    stdout.writeln('    ${b.parts.length} files, ${ch.length} chapters, ${b.duration}, cover: ${b.artTrack?.art != null}');
    // (Assumes every book has at least one chapter, which groupBooks gives it.)
    stdout.writeln('    first: ${ch.first.title} | last: ${ch.last.title}');
  }
  art.deleteSync(recursive: true);
}
