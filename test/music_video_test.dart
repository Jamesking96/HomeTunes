// Tests for music videos (0.1.40): pairing a song with the video of the same name beside it
// (services/music_video.dart), telling an .mp4 with pictures from a sound-only one (mp4HasVideo),
// the scanner giving songs their videos and hiding paired videos from the song list, the video
// being saved with the song, and when the video display moves the video to keep in step.
// The MP4s here are built by hand (just the boxes mp4HasVideo reads), so no real video is needed.
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/local_scanner.dart';
import 'package:hometunes/services/music_video.dart';
import 'package:hometunes/ui/widgets/music_video_view.dart'
    show learnSeekLead, maxSeekLead, videoSeekTarget, videoSyncRate, videoSyncTolerance, videoVisible;
import 'package:path/path.dart' as p;

/// One MP4 box: 4-byte size, 4-letter type, then the body.
List<int> _box(String type, List<int> body) {
  final size = 8 + body.length;
  return [(size >> 24) & 255, (size >> 16) & 255, (size >> 8) & 255, size & 255, ...type.codeUnits, ...body];
}

/// A track (trak) with the given handler ('vide' or 'soun') and sample format ('avc1', 'mp4a'…).
List<int> _trak(String handler, String format) {
  final hdlr = _box('hdlr', [0, 0, 0, 0, 0, 0, 0, 0, ...handler.codeUnits, ...List.filled(12, 0), 0]);
  final stsd = _box('stsd', [0, 0, 0, 0, 0, 0, 0, 1, ..._box(format, List.filled(8, 0))]);
  return _box('trak', _box('mdia', [...hdlr, ..._box('minf', _box('stbl', stsd))]));
}

/// A tiny MP4: ftyp, some media data, then moov (at the end, as downloaders often write it).
List<int> fakeMp4({String? videoFormat = 'avc1'}) => [
      ..._box('ftyp', [...'isom'.codeUnits, 0, 0, 0, 0]),
      ..._box('mdat', List.filled(64, 7)),
      ..._box('moov', [
        ..._box('mvhd', List.filled(20, 0)),
        ..._trak('soun', 'mp4a'),
        if (videoFormat != null) ..._trak('vide', videoFormat),
      ]),
    ];

void main() {
  group('pairMusicVideos', () {
    const exts = audioExtensions;

    test('an audio file and a video with the same name: one song, with the video', () {
      final r = pairMusicVideos([
        p.join('m', 'Flowers.m4a'),
        p.join('m', 'Flowers.mp4'),
      ], songExtensions: exts);
      expect(r.songs, [p.join('m', 'Flowers.m4a')]);
      expect(r.videos, {p.join('m', 'Flowers.m4a'): p.join('m', 'Flowers.mp4')});
    });

    test('an .mp4 on its own is still a song', () {
      final r = pairMusicVideos([p.join('m', 'Hurt.mp4')], songExtensions: exts);
      expect(r.songs, [p.join('m', 'Hurt.mp4')]);
      expect(r.videos, isEmpty);
    });

    test('names match ignoring case; other folders and other names don\'t pair', () {
      final r = pairMusicVideos([
        p.join('a', 'Song.MP3'),
        p.join('a', 'song.mp4'),
        p.join('b', 'Song.mp4'), // another folder: its own song
        p.join('a', 'Other.flac'),
      ], songExtensions: exts);
      expect(r.songs, [p.join('a', 'Song.MP3'), p.join('b', 'Song.mp4'), p.join('a', 'Other.flac')]);
      expect(r.videos, {p.join('a', 'Song.MP3'): p.join('a', 'song.mp4')});
    });

    test('.mkv / .webm only count as a song\'s video, and .mp4 wins when there are several', () {
      final r = pairMusicVideos([
        p.join('m', 'A.opus'),
        p.join('m', 'A.webm'),
        p.join('m', 'A.mp4'),
        p.join('m', 'B.mkv'), // no song beside it: ignored
      ], songExtensions: exts);
      expect(r.songs, [p.join('m', 'A.opus')]);
      expect(r.videos[p.join('m', 'A.opus')], p.join('m', 'A.mp4'));
    });
  });

  group('mp4HasVideo', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_mp4'));
    tearDown(() => dir.deleteSync(recursive: true));

    File write(String name, List<int> bytes) => File(p.join(dir.path, name))..writeAsBytesSync(bytes);

    test('an H.264 video track counts', () {
      expect(mp4HasVideo(write('v.mp4', fakeMp4()).path), isTrue);
    });

    test('sound only doesn\'t', () {
      expect(mp4HasVideo(write('a.mp4', fakeMp4(videoFormat: null)).path), isFalse);
    });

    test('a still-picture track (audiobook chapter pictures) doesn\'t', () {
      expect(mp4HasVideo(write('c.mp4', fakeMp4(videoFormat: 'jpeg')).path), isFalse);
    });

    test('damaged or not an MP4 at all: false, no error', () {
      expect(mp4HasVideo(write('x.mp4', [0, 0, 0, 99, 1, 2, 3]).path), isFalse);
      expect(mp4HasVideo(write('y.mp4', fakeMp4().sublist(0, 40)).path), isFalse);
      expect(mp4HasVideo(p.join(dir.path, 'missing.mp4')), isFalse);
    });
  });

  group('scanning', () {
    late Directory dir, music, art;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_videos');
      music = Directory(p.join(dir.path, 'music'))..createSync();
      art = Directory(p.join(dir.path, 'art'))..createSync();
    });
    tearDown(() => dir.deleteSync(recursive: true));

    test('a song gets the video beside it, and the video isn\'t listed as a song', () async {
      File('test/fixtures/tagged.m4a').copySync(p.join(music.path, 'Flowers.m4a'));
      File(p.join(music.path, 'Flowers.mp4')).writeAsBytesSync(fakeMp4());
      final tracks = await LocalScanner(art.path).scan([music.path]);
      expect(tracks, hasLength(1));
      expect(tracks.single.path, p.join(music.path, 'Flowers.m4a'));
      expect(tracks.single.video, p.join(music.path, 'Flowers.mp4'));
    });

    test('an .mp4 on its own: its own video if it has pictures, none if it\'s just sound', () async {
      File(p.join(music.path, 'Clip.mp4')).writeAsBytesSync(fakeMp4());
      File(p.join(music.path, 'Sound.mp4')).writeAsBytesSync(fakeMp4(videoFormat: null));
      final tracks = await LocalScanner(art.path).scan([music.path]);
      final byName = {for (final t in tracks) p.basename(t.path!): t};
      expect(byName.keys, unorderedEquals(['Clip.mp4', 'Sound.mp4']));
      expect(byName['Clip.mp4']!.video, byName['Clip.mp4']!.path);
      expect(byName['Sound.mp4']!.video, isNull);
    });

    test('a video added or removed beside an unchanged song is noticed on the next scan', () async {
      final song = p.join(music.path, 'Ghost.m4a');
      File('test/fixtures/tagged.m4a').copySync(song);
      final scanner = LocalScanner(art.path);
      var tracks = await scanner.scan([music.path]);
      expect(tracks.single.video, isNull);

      final video = File(p.join(music.path, 'Ghost.mp4'))..writeAsBytesSync(fakeMp4());
      tracks = await scanner.scan([music.path], previous: {for (final t in tracks) t.id: t});
      expect(tracks.single.video, video.path);

      video.deleteSync();
      tracks = await scanner.scan([music.path], previous: {for (final t in tracks) t.id: t});
      expect(tracks.single.video, isNull);
    });
  });

  test('the video is saved with the song and kept through edits', () {
    const t = Track(
      id: 'local:/m/Flowers.m4a',
      source: TrackSource.local,
      title: 'Flowers',
      artist: 'Miley Cyrus',
      album: 'Endless Summer Vacation',
      albumArtist: 'Miley Cyrus',
      path: '/m/Flowers.m4a',
      video: '/m/Flowers.mp4',
    );
    expect(Track.fromJson(t.toJson()).video, '/m/Flowers.mp4');
    expect(t.copyWith(art: '/a.jpg').video, '/m/Flowers.mp4');
    expect(const TrackEdit(title: 'Flowers (Video)').applyTo(t).video, '/m/Flowers.mp4');
    // Songs saved before 0.1.40 have no video.
    final old = t.toJson()..remove('video');
    expect(Track.fromJson(old).video, isNull);
  });

  group('keeping the video in step', () {
    test('close enough: left alone', () {
      expect(videoSeekTarget(song: const Duration(seconds: 30), video: const Duration(milliseconds: 29800)), isNull);
    });

    // 0.1.56: on the phone the video jumped every few seconds (each jump freezes the picture for
    // a moment). Small drifts are now caught up with a slightly different speed instead.
    test('a small drift is caught up with speed, not a jump', () {
      const song = Duration(seconds: 30);
      expect(videoSeekTarget(song: song, video: song - const Duration(milliseconds: 800)), isNull);
      // In step (within 0.1 s): the song's own speed.
      expect(videoSyncRate(song: song, video: song + const Duration(milliseconds: 80)), 1.0);
      expect(videoSyncRate(song: song, video: song, songSpeed: 1.25), 1.25);
      // Behind: a little faster; ahead: a little slower; never more than 20 % (0.1.57).
      expect(videoSyncRate(song: song, video: song - const Duration(milliseconds: 200)), closeTo(1.1, 0.001));
      expect(videoSyncRate(song: song, video: song - const Duration(milliseconds: 150)), closeTo(1.075, 0.001));
      expect(videoSyncRate(song: song, video: song + const Duration(milliseconds: 150)), closeTo(0.925, 0.001));
      expect(videoSyncRate(song: song, video: song - const Duration(milliseconds: 1400)), closeTo(1.2, 0.001));
      expect(videoSyncRate(song: song, video: song + const Duration(milliseconds: 1400)), closeTo(0.8, 0.001));
      // 1.8 s out is still caught up with speed (0.1.57: jumps only past 2 s).
      expect(videoSeekTarget(song: song, video: song - const Duration(milliseconds: 1800)), isNull);
    });

    test('drifted, or the song was moved: jump to the song', () {
      final far = videoSyncTolerance + const Duration(milliseconds: 1);
      expect(videoSeekTarget(song: const Duration(seconds: 30), video: const Duration(seconds: 30) - far),
          const Duration(seconds: 30));
      // Repeat-one starting again, or pressing back to the start.
      expect(videoSeekTarget(song: Duration.zero, video: const Duration(minutes: 3)), Duration.zero);
    });

    // 0.1.57: on the phone a jump landed behind the song (decoding from the last keyframe takes
    // a while) and soon needed another. Each jump now aims ahead by what the last ones lacked.
    test('a jump aims ahead by what the last jumps lacked', () {
      const song = Duration(seconds: 30);
      expect(
          videoSeekTarget(song: song, video: const Duration(seconds: 20), lead: const Duration(milliseconds: 1500)),
          const Duration(milliseconds: 31500));
      // Never past the end of the video.
      expect(
          videoSeekTarget(
              song: song,
              video: const Duration(seconds: 20),
              videoLength: const Duration(seconds: 31),
              lead: const Duration(seconds: 2)),
          const Duration(seconds: 31));
      // Landed 1.2 s behind: aim 1.2 s further ahead next time.
      expect(learnSeekLead(Duration.zero, song: const Duration(seconds: 33), video: const Duration(milliseconds: 31800)),
          const Duration(milliseconds: 1200));
      // Landed 0.5 s ahead: aim a little less far.
      expect(
          learnSeekLead(const Duration(seconds: 1),
              song: const Duration(seconds: 33), video: const Duration(milliseconds: 33500)),
          const Duration(milliseconds: 500));
      // Never below nothing or over 2 s (0.1.58).
      expect(learnSeekLead(Duration.zero, song: song, video: song + const Duration(seconds: 2)), Duration.zero);
      expect(
          learnSeekLead(const Duration(milliseconds: 1500), song: song, video: song - const Duration(seconds: 1)),
          maxSeekLead);
      // 0.1.58: a jump that landed far off (the video was stuck) teaches nothing.
      expect(learnSeekLead(const Duration(seconds: 1), song: song, video: song - const Duration(seconds: 13)),
          const Duration(seconds: 1));
      expect(learnSeekLead(const Duration(seconds: 1), song: song, video: song + const Duration(seconds: 50)),
          const Duration(seconds: 1));
    });

    // The stutter when the window wasn't focused: Windows calls that 'inactive', and the video
    // used to pause then (and be jumped along behind the song every 2 s).
    test('an unfocused window keeps playing; only a hidden one pauses', () {
      expect(videoVisible(AppLifecycleState.resumed), isTrue);
      expect(videoVisible(AppLifecycleState.inactive), isTrue);
      expect(videoVisible(null), isTrue);
      expect(videoVisible(AppLifecycleState.hidden), isFalse);
      expect(videoVisible(AppLifecycleState.paused), isFalse);
      expect(videoVisible(AppLifecycleState.detached), isFalse);
    });

    test('a video shorter than the song stays on its last picture', () {
      expect(
        videoSeekTarget(
          song: const Duration(minutes: 3, seconds: 40),
          video: const Duration(minutes: 3, seconds: 30),
          videoLength: const Duration(minutes: 3, seconds: 30),
        ),
        isNull,
      );
    });
  });
}
