// Draws the bottom player bar while a video plays (30 Sep) off-screen and saves it to
// C:\Temp\ht\preview\video-bar.png. The video player is a stand-in (no engine).
//   flutter test tool/video_bar_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/state/now_watching.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';
import 'package:provider/provider.dart';

import '../test/now_watching_test.dart' show FakeMusic, FakeVideo;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('video bar preview', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    Directory(out).createSync(recursive: true);
    final music = FakeMusic();
    final w = NowWatching(music);
    final video = FakeVideo()..playing = true;
    w.attach(video);
    w.showing(
      const VideoItem(
          id: 'v', path: '/v/x.mkv', title: 'Holston\'s Pick', collection: 'Silo', season: 1, episode: 2),
      skipBack: 10,
      skipForward: 30,
    );
    tester.view.physicalSize = const Size(1280, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerModel>.value(value: music),
        ChangeNotifierProvider.value(value: w),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme().copyWith(visualDensity: VisualDensity.compact),
          home: const Scaffold(body: SizedBox(), bottomNavigationBar: DesktopPlayerBar()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('$out\\video-bar.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
