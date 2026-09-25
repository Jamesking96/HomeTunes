// Scans a folder like HomeTunes does and prints each audiobook with what came
// from the files beside it (metadata file, cover, description, PDFs).
//   dart run tool/probe_book_extras.dart <folder>
import 'dart:io';

import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/state/book_index.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_book_extras.dart <folder>');
    exit(64);
  }
  final art = Directory.systemTemp.createTempSync('ht_probe_art');
  try {
    final watch = Stopwatch()..start();
    final tracks = await LocalScanner(art.path).scan([args.first]);
    final books = groupBooks(tracks.where(BookRules(bookFolders: [args.first]).isBook));
    stdout.writeln('${tracks.length} files, ${books.length} books, ${watch.elapsedMilliseconds} ms\n');
    for (final b in books) {
      final first = b.parts.first;
      final cover = first.art == null
          ? 'none'
          : (p.isWithin(art.path, first.art!) ? 'inside the file' : 'file ${p.basename(first.art!)}');
      stdout.writeln('${b.title}');
      stdout.writeln('   by ${b.author}${b.narrator == null ? '' : ' · read by ${b.narrator}'}'
          '${b.seriesLabel == null ? '' : ' · ${b.seriesLabel}'}${b.year == null ? '' : ' · ${b.year}'}');
      stdout.writeln('   ${b.parts.length} file(s), ${b.chapters.length} chapters · cover: $cover'
          ' · metadata file: ${b.parts.any((t) => t.hasBookInfo) ? 'yes' : 'no'}'
          ' · description: ${b.description == null ? 'no' : '${b.description!.length} chars'}'
          '${b.companions.isEmpty ? '' : ' · extras: ${b.companions.map(p.basename).join(', ')}'}');
    }
  } finally {
    art.deleteSync(recursive: true);
  }
}
