// Draws the TV players off-screen at the TV's size (960 x 540) and saves pictures to
// C:\Temp\ht\tv-preview (or OUT): the video player with its controls, moving through it, its
// Audio & subtitles panel and Up next; and Now Playing for a song. A pretend engine plays; the
// "picture" is a plain colour. Uses Windows' Segoe UI so the text is readable. Invented titles.
//   flutter test tool/tv_player_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/engine/video_engine.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/sleep_timer.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_session.dart';
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/tv/tv_focus.dart';
import 'package:hometunes/ui/tv/tv_now_playing.dart';
import 'package:hometunes/ui/tv/tv_video_player.dart';
import 'package:provider/provider.dart';

import '../test/fake_audio_engine.dart';
import '../test/fake_video_engine.dart';

class _Videos extends VideoLibraryModel {
  _Videos(super.storage, super.library) {
    final list = [
      for (final e in [1, 2, 3, 4])
        VideoItem(
          id: 'local:/v/Coastline S02E0$e.mkv',
          path: '/v/Coastline S02E0$e.mkv',
          title: ['The Harbour', 'Low Water', 'The Lighthouse', 'Night Crossing'][e - 1],
          collection: 'Coastline',
          season: 2,
          episode: e,
          duration: const Duration(minutes: 41, seconds: 12),
        ),
    ];
    videos = list;
    collections = [VideoCollection(name: 'Coastline', videos: list)];
  }

  @override
  VideoItem? byId(String id) => videos.where((v) => v.id == id).firstOrNull;
  @override
  VideoCollection? collectionNamed(String name) => collections.where((c) => c.name == name).firstOrNull;
  @override
  String? playableFile(VideoItem v) => v.path;
}

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\tv-preview');

  testWidgets('TV player previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf', r'C:\Windows\Fonts\seguisb.ttf']) {
        if (!File(f).existsSync()) continue;
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    Directory(out).createSync(recursive: true);
    final dir = Directory(r'C:\Temp\ht\preview-data\tv-player')..createSync(recursive: true);
    final storage = Storage.at(dir);
    final lib = LibraryModel(storage);
    final videos = _Videos(storage, lib);
    final music = PlayerModel(lib, engine: FakeAudioEngine());
    final engine = FakeVideoEngine();
    final session = VideoSession(
      engine: engine,
      videos: videos,
      music: music,
      videoId: 'local:/v/Coastline S02E03.mkv',
      upNextTick: const Duration(seconds: 1),
      tracksSettle: Duration.zero,
    );
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider<VideoLibraryModel>.value(value: videos),
        ChangeNotifierProvider(create: (_) => AppNav()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: TvVideoView(
            session: session,
            // A stand-in for the video's picture: a dusky sky over the sea.
            picture: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF6B7FA8), Color(0xFFC9A27E), Color(0xFF23415A)],
                  stops: [0, 0.55, 0.56],
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    engine.loaded(
      length: const Duration(minutes: 41, seconds: 12),
      audio: const [MediaTrack('1', language: 'eng', channels: '5.1', codec: 'ac3'), MediaTrack('2', language: 'jpn', channels: 'stereo', codec: 'aac')],
      subtitles: const [MediaTrack('3', language: 'eng', title: 'Full')],
    );
    engine.moveTo(const Duration(minutes: 18, seconds: 40));
    session.shown();
    await tester.pump(const Duration(milliseconds: 500));

    Future<void> shoot(String name) async {
      // Three frames: a focus request lands in the first, fades and rings start in the second
      // and finish by the third.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
        File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    Future<void> press(LogicalKeyboardKey k, [int times = 1]) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(k);
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await shoot('tv-video-controls');
    await press(LogicalKeyboardKey.arrowRight, 6);
    await shoot('tv-video-moving');
    await press(LogicalKeyboardKey.escape);
    await press(LogicalKeyboardKey.arrowDown);
    await shoot('tv-video-buttons');
    await press(LogicalKeyboardKey.select); // Audio & subtitles has focus
    await shoot('tv-video-tracks');
    await press(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 1));
    await shoot('tv-video-after-panel');
    engine.finish();
    await shoot('tv-video-up-next');

    await tester.pumpWidget(const SizedBox());
    session.dispose();
    music.dispose();
    await tester.pump(const Duration(seconds: 15));
  });

  testWidgets('TV Now Playing preview', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf', r'C:\Windows\Fonts\seguisb.ttf']) {
        if (!File(f).existsSync()) continue;
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    final dir = Directory(r'C:\Temp\ht\preview-data\tv-np')..createSync(recursive: true);
    final storage = Storage.at(dir);
    final lib = LibraryModel(storage);
    final audio = FakeAudioEngine();
    final player = PlayerModel(lib, engine: audio);
    final songs = [
      for (final (i, t) in ['Paper Lanterns', 'Harbour Wall', 'Salt Road'].indexed)
        Track(
          id: 'local:/m/$t.mp3',
          source: TrackSource.local,
          title: t,
          artist: 'Harbour Lights',
          album: 'Paper Lanterns',
          albumArtist: 'Harbour Lights',
          trackNumber: i + 1,
          duration: const Duration(minutes: 4, seconds: 5),
        ),
    ];
    await tester.runAsync(() => player.playTracks(songs, start: 1, label: 'Album · Paper Lanterns'));
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider<PlayerModel>.value(value: player),
        ChangeNotifierProvider(create: (_) => PlaylistsModel(storage)),
        ChangeNotifierProvider(create: (_) => SleepTimer(player, lib)),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: tvTheme(buildTheme(), AppColors.accent),
          builder: (context, child) => TvFocus(enabled: true, child: child!),
          home: const TvNowPlayingPage(),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('$out\\tv-now-playing.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    await tester.pump(const Duration(seconds: 5));
  });
}
