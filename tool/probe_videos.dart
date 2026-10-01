// Probe (0.1.40): shows how a folder's songs pair up with music videos, using the real scanner
// code (services/music_video.dart and LocalScanner.findFiles). Changes nothing.
//   dart run tool/probe_videos.dart <folder>
import 'dart:io';

import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/music_video.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/probe_videos.dart <folder>');
    exit(64);
  }
  final found = await LocalScanner(Directory.systemTemp.path).findFiles([args.first]);
  for (final song in found.songs) {
    final paired = found.videos[song];
    final own = paired == null && videoExtensions.contains(p.extension(song).toLowerCase()) && mp4HasVideo(song);
    final video = paired != null
        ? 'video: ${p.basename(paired)}${mp4HasVideo(paired) ? '' : ' (no moving pictures found in it)'}'
        : (own ? 'video: itself' : 'no video');
    stdout.writeln('${p.basename(song)}  ->  $video');
  }
  stdout.writeln('${found.songs.length} songs, ${found.videos.length} with a video beside them');
}
