// Probe (0.1.40): shows how the Videos tab will read a video folder: each collection (with its
// category, year and videos per season / part / extras), then a sample of videos with their
// season, episode and title. Uses the real rules (services/video_names.dart). Changes nothing.
//   dart run tool/probe_video_names.dart <video folder> [videos to list, default 40]
import 'dart:io';

import 'package:hometunes/services/video_names.dart';
import 'package:hometunes/services/video_scanner.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_video_names.dart <video folder> [videos to list]');
    exit(64);
  }
  final root = args.first;
  final sample = args.length > 1 ? int.parse(args[1]) : 40;
  final files = [
    for (final e in Directory(root).listSync(recursive: true, followLinks: false))
      if (e is File && videoFileExtensions.contains(p.extension(e.path).toLowerCase())) e.path
  ]..sort();
  final infos = [for (final f in files) (f, describeVideoPath(root, f))];
  final byCollection = <String, List<VideoPathInfo>>{};
  for (final (_, i) in infos) {
    (byCollection['${i.category ?? '-'} | ${i.collection}${i.year != null ? ' (${i.year})' : ''}'] ??= []).add(i);
  }
  stdout.writeln('${files.length} videos in ${byCollection.length} collections\n');
  for (final e in byCollection.entries) {
    final groups = <String, int>{};
    for (final i in e.value) {
      final g = i.extra ? 'Extras' : i.season == 0 ? 'Specials' : i.season != null ? 'S${i.season}' : (i.part ?? '-');
      groups[g] = (groups[g] ?? 0) + 1;
    }
    final noEp = e.value.where((i) => !i.extra && i.episode == null).length;
    stdout.writeln('${e.key}: ${e.value.length}  [${groups.entries.map((g) => '${g.key}:${g.value}').join(' ')}]'
        '${noEp > 0 ? '  no episode no.: $noEp' : ''}');
  }
  stdout.writeln('\nSample:');
  final step = (infos.length / sample).ceil().clamp(1, 1 << 30);
  for (var k = 0; k < infos.length; k += step) {
    final (f, i) = infos[k];
    final se = i.extra ? 'extra' : '${i.season != null ? 'S${i.season}' : ''}${i.episode != null ? 'E${i.episode}' : ''}${i.part != null ? ' [${i.part}]' : ''}';
    stdout.writeln('  ${i.collection} | $se | ${i.title}   <- ${p.basename(f)}');
  }
}
