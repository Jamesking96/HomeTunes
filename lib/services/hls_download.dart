// Downloads a converted copy of a server video segment by segment (0.2.7).
//
// The user (1 Nov 2026): some Jellyfin videos "don't download or stream correctly" (The Lion King,
// an XviD .avi the TV can't play, so a converted copy is used) and "when we download a video it
// [should download] the whole thing [and show] the download progress". A converted copy used to
// come as one file sent while the server made it: no size (so no progress), no length or index in
// the file (the player guessed the length from what had arrived), and a connection that dropped
// part-way left a short file that looked finished.
//
// Now a converted copy comes from the server's HLS playlist (JellyfinClient.hlsUri): the playlist
// lists every segment of the whole video, so this fetches them one after another into one
// MPEG-TS file. It knows exactly how far it has got (segment 412 of 889), it's only done when every
// segment has arrived, and if it's stopped (paused, the app closed, the connection lost) it carries
// on from the last whole segment: `<file>.part` holds what's fetched so far and `<file>.hls.json`
// how many segments that is. A segment that fails is tried again a few times before giving up.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// How a segmented download got on.
enum HlsOutcome { done, paused, canceled, failed }

class HlsResult {
  final HlsOutcome outcome;

  /// For a failed one: the server's answer (401: the sign-in stopped working), or what went wrong.
  final int? httpStatus;
  final String? error;
  const HlsResult(this.outcome, {this.httpStatus, this.error});
}

/// What can stop a download that's under way.
class HlsControl {
  bool paused = false, canceled = false;
  bool get stop => paused || canceled;
}

/// The segments of the variant playlist at [playlist] (a master playlist's first variant is
/// followed), in order, as absolute addresses. Throws [HlsHttpException] or [FormatException].
Future<List<Uri>> hlsSegments(http.Client c, Uri playlist, Map<String, String> headers, {int depth = 0}) async {
  final text = await _getText(c, playlist, headers);
  final lines = const LineSplitter().convert(text).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  if (lines.isEmpty || lines.first != '#EXTM3U') throw const FormatException('Not a playlist');
  if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF'))) {
    if (depth > 2) throw const FormatException('Playlists point at each other');
    // A master playlist: its first variant.
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
        final next = lines.skip(i + 1).firstWhere((l) => !l.startsWith('#'), orElse: () => '');
        if (next.isEmpty) break;
        return hlsSegments(c, playlist.resolve(next), headers, depth: depth + 1);
      }
    }
    throw const FormatException('No variant in the playlist');
  }
  final out = <Uri>[];
  var expectSegment = false;
  for (final l in lines) {
    if (l.startsWith('#EXTINF')) {
      expectSegment = true;
    } else if (!l.startsWith('#') && expectSegment) {
      out.add(playlist.resolve(l));
      expectSegment = false;
    }
  }
  if (out.isEmpty) throw const FormatException('No segments in the playlist');
  return out;
}

class HlsHttpException implements Exception {
  final int status;
  const HlsHttpException(this.status);
  @override
  String toString() => 'The server answered $status';
}

Future<String> _getText(http.Client c, Uri u, Map<String, String> headers) async {
  final r = await c.get(u, headers: headers).timeout(const Duration(seconds: 60));
  if (r.statusCode != 200) throw HlsHttpException(r.statusCode);
  return utf8.decode(r.bodyBytes, allowMalformed: true);
}

/// Fetches the segments of [playlist] into [path] (via `<path>.part`), carrying on from where an
/// earlier run stopped. [onProgress] gets (segments done, segments in all, bytes so far).
Future<HlsResult> downloadHls({
  required http.Client client,
  required Uri playlist,
  required Map<String, String> headers,
  required String path,
  required HlsControl control,
  void Function(int done, int total, int bytes)? onProgress,
  int retries = 5,
  Duration Function(int attempt) backoff = _backoff,
}) async {
  final part = File('$path.part'), state = File('$path.hls.json');
  List<Uri> segments;
  try {
    segments = await hlsSegments(client, playlist, headers);
  } on HlsHttpException catch (e) {
    return HlsResult(HlsOutcome.failed, httpStatus: e.status, error: e.toString());
  } catch (e) {
    return HlsResult(HlsOutcome.failed, error: 'The server\'s playlist couldn\'t be read ($e)');
  }
  final total = segments.length;
  // Where an earlier run got to: that many whole segments, that many bytes (anything after them,
  // a segment cut off part-way, is dropped).
  var done = 0, bytes = 0;
  try {
    if (await state.exists() && await part.exists()) {
      final j = jsonDecode(await state.readAsString());
      if (j is Map && j['total'] == total && j['done'] is int && j['bytes'] is int) {
        final len = await part.length();
        if (len >= (j['bytes'] as int)) {
          done = j['done'] as int;
          bytes = j['bytes'] as int;
        }
      }
    }
  } catch (_) {}
  if (done == 0) bytes = 0;
  RandomAccessFile out;
  try {
    await part.parent.create(recursive: true);
    out = await part.open(mode: done == 0 ? FileMode.write : FileMode.append);
    if (done > 0) await out.truncate(bytes);
    await out.setPosition(bytes);
  } catch (e) {
    return HlsResult(HlsOutcome.failed, error: 'The file couldn\'t be written ($e)');
  }
  onProgress?.call(done, total, bytes);
  try {
    while (done < total) {
      if (control.canceled) return const HlsResult(HlsOutcome.canceled);
      if (control.paused) return const HlsResult(HlsOutcome.paused);
      List<int>? data;
      HlsResult? failure;
      for (var attempt = 0; attempt <= retries; attempt++) {
        if (control.stop) break;
        try {
          final r = await client.get(segments[done], headers: headers).timeout(const Duration(minutes: 3));
          if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
            data = r.bodyBytes;
            break;
          }
          failure = HlsResult(HlsOutcome.failed, httpStatus: r.statusCode, error: 'The server answered ${r.statusCode}');
          // A sign-in that stopped working won't start working by asking again.
          if (r.statusCode == 401 || r.statusCode == 403 || r.statusCode == 404) break;
        } catch (e) {
          failure = HlsResult(HlsOutcome.failed, error: 'The connection to the server was lost');
        }
        if (attempt < retries && !control.stop) await Future<void>.delayed(backoff(attempt));
      }
      if (data == null) {
        if (control.canceled) return const HlsResult(HlsOutcome.canceled);
        if (control.paused) return const HlsResult(HlsOutcome.paused);
        return failure ?? const HlsResult(HlsOutcome.failed, error: 'The connection to the server was lost');
      }
      await out.writeFrom(data);
      bytes += data.length;
      done++;
      // Remember the whole segments so far (every few, and at the end).
      if (done % 5 == 0 || done == total) {
        await out.flush();
        await state.writeAsString(jsonEncode({'total': total, 'done': done, 'bytes': bytes}));
      }
      onProgress?.call(done, total, bytes);
    }
    await out.flush();
  } catch (e) {
    return HlsResult(HlsOutcome.failed, error: 'The file couldn\'t be written ($e)');
  } finally {
    try {
      await out.close();
    } catch (_) {}
    if (control.canceled) {
      for (final f in [part, state]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }
  // Every segment is here: it's the finished file.
  try {
    final dest = File(path);
    if (await dest.exists()) await dest.delete();
    await part.rename(path);
    if (await state.exists()) await state.delete();
  } catch (e) {
    return HlsResult(HlsOutcome.failed, error: 'The file couldn\'t be written ($e)');
  }
  return const HlsResult(HlsOutcome.done);
}

Duration _backoff(int attempt) => Duration(seconds: const [2, 4, 8, 16, 30, 30][attempt.clamp(0, 5)]);
