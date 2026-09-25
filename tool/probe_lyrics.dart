// Checks the LRCLIB look-up against the real service (needs internet):
//   dart run tool/probe_lyrics.dart "Title" "Artist" [seconds]
// Prints what was found (not the lyrics themselves).
import 'dart:io';

import 'package:hometunes/services/lrclib_client.dart';

Future<void> main(List<String> args) async {
  final title = args.isNotEmpty ? args[0] : 'Bohemian Rhapsody';
  final artist = args.length > 1 ? args[1] : 'Queen';
  final secs = args.length > 2 ? int.tryParse(args[2]) : 355;
  final c = LrclibClient();
  try {
    final m = await c.find(title: title, artist: artist, duration: secs == null ? null : Duration(seconds: secs));
    if (m == null) {
      stdout.writeln('find: nothing');
    } else {
      final lines = (m.bestLyrics ?? '').split('\n').length;
      stdout.writeln('find: #${m.id} "${m.title}" by ${m.artist}, ${m.duration.inSeconds}s, '
          '${m.timed ? 'timed' : 'plain'}, $lines lines');
    }
    final all = await c.search(title: title, artist: artist, duration: secs == null ? null : Duration(seconds: secs));
    stdout.writeln('search: ${all.length} results; first 3: '
        '${all.take(3).map((x) => '${x.duration.inSeconds}s ${x.timed ? 'timed' : 'plain'}').join(', ')}');
  } finally {
    c.close();
  }
}
