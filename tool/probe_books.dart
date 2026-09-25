// Prints what HomeTunes can read from audiobook files: tags, length and chapters.
// Usage: dart run tool/probe_books.dart <folder or file> [max files]
//
// A developer tool that talks straight to the audio_metadata_reader package (not the app's
// scanner), so it shows the raw tag data before HomeTunes does anything with it. Useful when a
// book shows odd titles or no chapters. Prints up to [max files] files (default 12).
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_books.dart <folder or file> [max files]');
    exit(64);
  }
  final max = args.length > 1 ? int.parse(args[1]) : 12;
  final target = args.first;
  // A folder: every audio file inside it (sub-folders too), sorted by path, first `max` only.
  // A single file: just that file.
  final files = FileSystemEntity.isDirectorySync(target)
      ? (Directory(target)
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => RegExp(r'\.(mp3|m4b|m4a|mp4|aac|flac|ogg|opus|wav)$', caseSensitive: false).hasMatch(f.path))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path)))
          .take(max)
      : [File(target)];
  for (final f in files) {
    stdout.writeln('== ${f.path}');
    try {
      // getImage: true also reads embedded pictures, so the picture count can be shown.
      final m = readMetadata(f, getImage: true);
      stdout.writeln('  title="${m.title}" artist="${m.artist}" album="${m.album}" albumArtist="${m.albumArtist}"');
      stdout.writeln('  track=${m.trackNumber}/${m.trackTotal} disc=${m.discNumber} year=${m.year?.year} '
          'genres=${m.genres} duration=${m.duration} pictures=${m.pictures.length}');
      final chapters = m.chapters;
      stdout.writeln('  chapters=${chapters.length}');
      // Only the first few chapters, to keep the output short.
      for (final c in chapters.take(5)) {
        stdout.writeln('    ${c.start}  ${c.title}');
      }
    // One unreadable file shouldn't stop the rest from being printed.
    } catch (e) {
      stdout.writeln('  ERROR $e');
    }
  }
}
