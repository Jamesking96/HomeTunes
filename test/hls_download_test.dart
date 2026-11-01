// 0.2.7: a converted copy of a server video downloads segment by segment (services/hls_download.dart),
// against a pretend Jellyfin HLS playlist: every segment in order into one file, exact progress,
// carrying on after a failure from the last whole segments, stopping when paused or cancelled.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/hls_download.dart';
import 'package:hometunes/services/jellyfin_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

/// A pretend server: a master playlist, its variant and [count] segments of [size] bytes each
/// (segment i is filled with the byte i).
class FakeHls {
  FakeHls(this.count, {this.size = 100});
  final int count, size;
  final List<String> requests = [];

  /// Segments that fail with a server error, or a dropped connection, so many times each before
  /// they're sent.
  final Map<int, int> failTimes = {}, dropTimes = {};

  late final MockClient client = MockClient((r) async {
    requests.add(r.url.path);
    if (r.headers['Authorization'] != 'Bearer ok') return http.Response('', 401);
    if (r.url.path.endsWith('/master.m3u8')) {
      return http.Response('#EXTM3U\n#EXT-X-STREAM-INF:PROGRAM-ID=1,BANDWIDTH=1500000\nmain.m3u8?MediaSourceId=x&DeviceId=d\n', 200);
    }
    if (r.url.path.endsWith('/main.m3u8')) {
      final b = StringBuffer('#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:6\n#EXT-X-MEDIA-SEQUENCE:0\n');
      for (var i = 0; i < count; i++) {
        b.write('#EXTINF:6.0, nodesc\nhls1/main/$i.ts?MediaSourceId=x&runtimeTicks=${i * 60000000}\n');
      }
      b.write('#EXT-X-ENDLIST\n');
      return http.Response(b.toString(), 200);
    }
    final m = RegExp(r'/hls1/main/(\d+)\.ts$').firstMatch(r.url.path);
    if (m != null) {
      final i = int.parse(m.group(1)!);
      final drop = dropTimes[i] ?? 0;
      if (drop > 0) {
        dropTimes[i] = drop - 1;
        throw const SocketException('connection reset');
      }
      final left = failTimes[i] ?? 0;
      if (left > 0) {
        failTimes[i] = left - 1;
        return http.Response('', 500);
      }
      return http.Response.bytes(List.filled(size, i), 200, headers: {'content-type': 'video/mp2t'});
    }
    return http.Response('', 404);
  });
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_hls'));
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  final playlist = Uri.parse('http://192.168.0.10:8096/Videos/lion/master.m3u8?MediaSourceId=lion');
  const headers = {'Authorization': 'Bearer ok'};
  Duration none(int _) => Duration.zero;

  test('the playlist: the master\'s variant, then its segments in order as full addresses', () async {
    final s = FakeHls(3);
    final segs = await hlsSegments(s.client, playlist, headers);
    expect(segs.map((u) => u.path), ['/Videos/lion/hls1/main/0.ts', '/Videos/lion/hls1/main/1.ts', '/Videos/lion/hls1/main/2.ts']);
    expect(segs.first.queryParameters['MediaSourceId'], 'x');
  });

  test('every segment, in order, into one file, with exact progress; only then is it the file', () async {
    final s = FakeHls(12);
    final path = p.join(dir.path, 'lion.ts');
    final seen = <(int, int, int)>[];
    var sawFinalFileEarly = false;
    final r = await downloadHls(
      client: s.client,
      playlist: playlist,
      headers: headers,
      path: path,
      control: HlsControl(),
      onProgress: (d, t, b) {
        seen.add((d, t, b));
        if (File(path).existsSync()) sawFinalFileEarly = true;
      },
      backoff: none,
    );
    expect(r.outcome, HlsOutcome.done);
    expect(seen.first, (0, 12, 0));
    expect(seen.last, (12, 12, 1200));
    expect(sawFinalFileEarly, isFalse);
    final bytes = File(path).readAsBytesSync();
    expect(bytes.length, 1200);
    for (var i = 0; i < 12; i++) {
      expect(bytes[i * 100], i);
    }
    expect(File('$path.part').existsSync(), isFalse);
    expect(File('$path.hls.json').existsSync(), isFalse);
  });

  test('a segment that keeps failing: it stops, and next time carries on from the whole segments it has', () async {
    final s = FakeHls(12)..failTimes[8] = 1000;
    final path = p.join(dir.path, 'lion.ts');
    final r1 = await downloadHls(
        client: s.client, playlist: playlist, headers: headers, path: path, control: HlsControl(), retries: 2, backoff: none);
    expect(r1.outcome, HlsOutcome.failed);
    expect(File(path).existsSync(), isFalse); // not a finished file
    expect(jsonDecode(File('$path.hls.json').readAsStringSync())['done'], 5);
    // A dropped connection (not a server error) is tried again too.
    s
      ..failTimes[8] = 0
      ..dropTimes[8] = 1;
    s.requests.clear();
    final r2 = await downloadHls(
        client: s.client, playlist: playlist, headers: headers, path: path, control: HlsControl(), retries: 2, backoff: none);
    expect(r2.outcome, HlsOutcome.done);
    // Carried on from segment 5 (not from the start).
    expect(s.requests.where((x) => x.endsWith('.ts')).first, '/Videos/lion/hls1/main/5.ts');
    final bytes = File(path).readAsBytesSync();
    expect(bytes.length, 1200);
    for (var i = 0; i < 12; i++) {
      expect(bytes[i * 100], i, reason: 'segment $i');
    }
  });

  test('a sign-in that stopped working says 401 at once (no retries)', () async {
    final s = FakeHls(3);
    final r = await downloadHls(
        client: s.client,
        playlist: playlist,
        headers: const {'Authorization': 'Bearer old'},
        path: p.join(dir.path, 'x.ts'),
        control: HlsControl(),
        backoff: none);
    expect(r.outcome, HlsOutcome.failed);
    expect(r.httpStatus, 401);
  });

  test('paused: stops after the segment it\'s on; cancelled: its part file goes', () async {
    final s = FakeHls(12);
    final path = p.join(dir.path, 'lion.ts');
    final c = HlsControl();
    final r = await downloadHls(
      client: s.client,
      playlist: playlist,
      headers: headers,
      path: path,
      control: c,
      onProgress: (d, _, _) {
        if (d == 6) c.paused = true;
      },
      backoff: none,
    );
    expect(r.outcome, HlsOutcome.paused);
    expect(File('$path.part').existsSync(), isTrue);
    final c2 = HlsControl();
    final r2 = await downloadHls(
      client: s.client,
      playlist: playlist,
      headers: headers,
      path: path,
      control: c2,
      onProgress: (d, _, _) {
        if (d == 7) c2.canceled = true;
      },
      backoff: none,
    );
    expect(r2.outcome, HlsOutcome.canceled);
    expect(File('$path.part').existsSync(), isFalse);
    expect(File('$path.hls.json').existsSync(), isFalse);
  });

  test('Jellyfin\'s segmented address: H.264 and AAC in TS segments, no sign-in in it', () {
    final c = JellyfinClient(baseUrl: 'http://x:8096', deviceId: 'dev', token: 'tok', userId: 'u');
    final u = c.hlsUri('lion', maxHeight: 720, playSessionId: 'ps1');
    expect(u.path, '/Videos/lion/master.m3u8');
    expect(u.queryParameters['MediaSourceId'], 'lion');
    expect(u.queryParameters['SegmentContainer'], 'ts');
    expect(u.queryParameters['VideoCodec'], 'h264');
    expect(u.queryParameters['MaxHeight'], '720');
    expect(u.queryParameters['PlaySessionId'], 'ps1');
    expect(u.toString(), isNot(contains('tok')));
    c.close();
  });
}
