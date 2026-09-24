// Prints what HomeTunes can read from audiobook files: tags, length and chapters.
// Usage: dart run tool/probe_books.dart <folder or file> [max files]
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_books.dart <folder or file> [max files]');
    exit(64);
  }
  final max = args.length > 1 ? int.parse(args[1]) : 12;
  final target = args.first;
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
      final m = readMetadata(f, getImage: true);
      stdout.writeln('  title="${m.title}" artist="${m.artist}" album="${m.album}" albumArtist="${m.albumArtist}"');
      stdout.writeln('  track=${m.trackNumber}/${m.trackTotal} disc=${m.discNumber} year=${m.year?.year} '
          'genres=${m.genres} duration=${m.duration} pictures=${m.pictures.length}');
      final chapters = m.chapters;
      stdout.writeln('  chapters=${chapters.length}');
      for (final c in chapters.take(5)) {
        stdout.writeln('    ${c.start}  ${c.title}');
      }
    } catch (e) {
      stdout.writeln('  ERROR $e');
    }
  }
}
