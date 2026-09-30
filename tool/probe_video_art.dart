// Live check of "Search online" for video pictures (services/video_art_search.dart): asks
// TVmaze, AniList and Wikipedia and prints what each found. Downloads nothing.
//   dart run tool/probe_video_art.dart "Silo" [season episode]
// ignore_for_file: avoid_print
import 'package:hometunes/services/video_art_search.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run tool/probe_video_art.dart "<name>" [season episode]');
    return;
  }
  final search = VideoArtSearch();
  final season = args.length > 2 ? int.tryParse(args[1]) : null;
  final episode = args.length > 2 ? int.tryParse(args[2]) : null;
  final sw = Stopwatch()..start();
  final r = await search.search(args[0], season: season, episode: episode);
  print('${r.found.length} pictures in ${sw.elapsedMilliseconds} ms${r.failed.isEmpty ? '' : '; failed: ${r.failed.join(', ')}'}');
  for (final c in r.found) {
    print('${c.source.padRight(9)} ${c.kind.padRight(10)} ${c.aspect?.toStringAsFixed(2) ?? '?'}  ${c.title}\n    ${c.fullUrl}');
  }
  search.close();
}
