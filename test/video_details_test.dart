// 0.1.44: the Details page for videos and collections ("Music and audio books allow for viewing
// the file details, I'd like this for the videos too"): where each detail comes from, what the
// video engine finds inside the file (in plain words), and the pages themselves.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/media_details.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/video_details.dart';
import 'package:hometunes/services/video_probe.dart';
import 'package:hometunes/services/video_scanner.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/screens/video_details_screen.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// What the engine said about a real file (Black Lagoon, checked with
/// tool/bench/video_probe_engine_test.dart on 1 Oct), trimmed.
const _trackList =
    '[{"id":1,"type":"video","image":false,"albumart":false,"default":true,"forced":false,'
    '"codec":"hevc","demux-w":1920,"demux-h":1080,"demux-fps":23.976024},'
    '{"id":1,"type":"audio","default":true,"codec":"ac3","lang":"eng","title":"English",'
    '"demux-channel-count":6,"demux-samplerate":48000},'
    '{"id":2,"type":"audio","default":false,"codec":"ac3","lang":"jpn","title":"Japanese",'
    '"demux-channel-count":2,"demux-samplerate":48000},'
    '{"id":1,"type":"sub","default":true,"codec":"ass","lang":"eng","title":"Signs & Songs"},'
    '{"id":2,"type":"sub","default":false,"forced":true,"codec":"subrip","lang":"eng"},'
    '{"id":3,"type":"video","image":true,"albumart":true,"codec":"mjpeg"}]';

final _probe = parseVideoProbe(format: 'mkv', duration: '1408.512', trackList: _trackList, chapters: '5');

/// A season of Silo with .nfo files, a poster and a subtitle file.
String _makeSilo(Directory dir) {
  final root = p.join(dir.path, 'vids');
  final show = Directory(p.join(root, 'TV', 'Silo'));
  final season = Directory(p.join(show.path, 'Season 1 - Offline News'))..createSync(recursive: true);
  File(p.join(show.path, 'tvshow.nfo')).writeAsStringSync(
    '<tvshow><title>Silo</title><genre>Drama</genre><plot>A last town under the ground.</plot></tvshow>',
  );
  File(p.join(show.path, 'poster.jpg')).writeAsBytesSync([1, 2, 3]);
  final video = File(p.join(season.path, 'Silo S01E02.mkv'))..writeAsBytesSync(List.filled(2048, 1));
  File(
    p.join(season.path, 'Silo S01E02.nfo'),
  ).writeAsStringSync('<episodedetails><title>Holston\'s Pick</title></episodedetails>');
  File(p.join(season.path, 'Silo S01E02.en.srt')).writeAsStringSync('1\n00:00:01,000 --> 00:00:02,000\nHi\n');
  File(p.join(season.path, 'Silo S01E03.mkv')).writeAsBytesSync([1]);
  return video.path;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_video_details'));
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  });

  test('each detail says where it came from', () async {
    final path = _makeSilo(dir);
    final root = p.join(dir.path, 'vids');
    final scanned = (await VideoScanner().scan([root])).firstWhere((v) => v.path == path);
    final shown = const VideoEdit(year: 2023).applyTo(scanned);
    final d = inspectVideoNow(shown: shown, scanned: scanned, roots: [root]);
    DetailRow row(String label) => d.rows.firstWhere((r) => r.label == label);

    expect(row('Title').shown, 'Holston\'s Pick');
    expect(row('Title').source, DetailSource.nfoFile);
    expect(row('Title').from, 'Silo S01E02.nfo');
    expect(row('Collection').source, DetailSource.showNfo);
    expect(row('Category').source, DetailSource.folderName);
    expect(row('Season').source, DetailSource.fileName);
    expect(row('Episode').shown, '2');
    expect(row('Season title').shown, 'Offline News');
    expect(row('Season title').source, DetailSource.folderName);
    expect(row('Season title').from, 'Season 1 - Offline News');
    expect(row('Year').source, DetailSource.edit);
    expect(row('Year').inFile, '–');
    expect(row('Genre').source, DetailSource.showNfo);
    expect(row('Length').source, DetailSource.notSet);
    expect(d.videoFolder, root);
    expect(d.format, 'MKV');
    expect(d.sizeBytes, 2048);
    expect(d.nfoSays, contains(('Title', 'Holston\'s Pick')));
    final uses = {for (final (name, use) in d.besideIt) use: name};
    expect(uses['Details (.nfo file)'], 'Silo S01E02.nfo');
    expect(uses['The series\' details (.nfo file)'], p.join('Silo', 'tvshow.nfo'));
    expect(uses['The collection\'s poster'], p.join('Silo', 'poster.jpg'));
    expect(uses['Subtitles: en'], 'Silo S01E02.en.srt');
  });

  test('what the engine finds, in plain words', () {
    expect(_probe.container, 'mkv');
    expect(_probe.duration, const Duration(milliseconds: 1408512));
    expect(_probe.chapters, 5);
    expect(_probe.video, hasLength(1)); // the cover picture isn't a video track
    expect(_probe.audio, hasLength(2));
    expect(_probe.subtitles, hasLength(2));
    expect(trackLine(_probe.video.single), 'H.265 (HEVC) · 1920×1080 · 23.976 frames a second');
    expect(trackLine(_probe.audio.first), 'English · Dolby Digital (AC3) · 5.1 · 48 kHz · plays first');
    expect(trackLine(_probe.audio.last), 'Japanese · Dolby Digital (AC3) · Stereo · 48 kHz');
    expect(trackLine(_probe.subtitles.first), 'English · "Signs & Songs" · Styled text (ASS) · shown first');
    expect(trackLine(_probe.subtitles.last), 'English · Text (SRT) · forced');
    expect(containerName('mov,mp4,m4a,3gp,3g2,mj2', 'MP4'), 'MP4 / QuickTime');
    expect(containerName(null, 'AVI'), 'AVI');
    expect(codecName('pcm_s16le'), 'Uncompressed (PCM)');
    expect(overallBitRate(1000000, const Duration(seconds: 8)), 'about 1.0 Mbit/s');
    expect(parseVideoProbe(trackList: 'not json').tracks, isEmpty);
  });

  group('the pages', () {
    late Storage storage;
    late LibraryModel lib;
    late VideoLibraryModel videos;
    late String path;

    setUp(() async {
      path = _makeSilo(dir);
      storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
      lib = LibraryModel(storage);
      videos = VideoLibraryModel(storage, lib);
      videoProbe = (_) async => _probe;
    });
    tearDown(() async {
      videoProbe = probeVideo;
      await videos.settle();
    });

    Widget app(Widget home) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: videos),
      ],
      child: MaterialApp(home: home),
    );

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
      }
    }

    testWidgets('a video\'s Details page', (tester) async {
      await tester.runAsync(() async {
        await lib.addVideoFolder(p.join(dir.path, 'vids'));
        await videos.scan();
      });
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(VideoDetailsScreen(videoId: VideoItem.idFor(path))));
      await settle(tester);

      expect(find.text('Holston\'s Pick'), findsWidgets);
      expect(find.text('Details and where they come from'), findsOneWidget);
      expect(find.text('Details file (.nfo)'), findsOneWidget);
      expect(find.text('Series details file (tvshow.nfo)'), findsWidgets);
      expect(find.text('What\'s inside the file'), findsOneWidget);
      expect(find.text('Matroska (MKV)'), findsOneWidget);
      expect(find.text('H.265 (HEVC) · 1920×1080 · 23.976 frames a second'), findsOneWidget);
      expect(find.text('English · Dolby Digital (AC3) · 5.1 · 48 kHz · plays first'), findsOneWidget);
      expect(find.text('Sound 2'), findsOneWidget);
      expect(find.text('What its .nfo file says'), findsOneWidget);
      expect(find.text('Files beside it that HomeTunes uses'), findsOneWidget);
    });

    testWidgets('a collection\'s Details page', (tester) async {
      await tester.runAsync(() async {
        await lib.addVideoFolder(p.join(dir.path, 'vids'));
        await videos.scan();
      });
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const CollectionDetailsScreen(name: 'Silo')));
      await settle(tester);

      expect(find.text('COLLECTION'), findsOneWidget);
      expect(find.textContaining('2 videos · MKV'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Poster'), findsOneWidget);
      expect(find.text('poster.jpg'), findsOneWidget);
      // Open one video to see its own details.
      await tester.tap(find.text('S1 E2 · Holston\'s Pick'));
      await settle(tester);
      expect(find.text('Details file (.nfo)'), findsWidgets);
      expect(find.text('Matroska (MKV)'), findsOneWidget);
    });
  });
}
