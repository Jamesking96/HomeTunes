// 0.1.70: the volume sliders follow the volume boost straight away. Changing it in Settings ›
// Playback moves the top of every slider at once; before, the video's bottom-bar slider (and
// the video player's own) kept the old top until the volume itself moved.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/now_watching.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/widgets/player_controls.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'now_watching_test.dart' show FakeMusic, FakeVideo;

/// A video player whose slider top is the boost's, like the real one (MediaKitTransport).
class _BoostVideo extends FakeVideo implements VolumeTop {
  _BoostVideo(this.lib);
  final LibraryModel lib;
  @override
  double get maxVolume => lib.maxVolume;
}

const _episode = VideoItem(id: 'video:/v/a.mkv', path: '/v/a.mkv', title: 'Pilot', collection: 'Show');

void main() {
  late Directory dir;
  late LibraryModel lib;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_volume_top');
    lib = LibraryModel(Storage.at(Directory(p.join(dir.path, 'data'))..createSync()));
  });
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // a settings write still finishing
      }
    }
  });

  double top(WidgetTester tester, String key) => tester.widget<Slider>(find.byKey(ValueKey(key))).max;

  testWidgets('the video bottom bar\'s slider follows the boost at once', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final music = FakeMusic();
    final w = NowWatching(music);
    final video = _BoostVideo(lib)..playing = true;
    w.attach(video);
    w.showing(_episode);

    Widget bar() => SizedBox(height: 88, child: DesktopPlayerBar());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerModel>.value(value: music),
        ChangeNotifierProvider.value(value: w),
        ChangeNotifierProvider.value(value: lib),
      ],
      child: MaterialApp(
        theme: ThemeData(visualDensity: VisualDensity.compact),
        home: Scaffold(bottomNavigationBar: bar()),
      ),
    ));
    expect(top(tester, 'video-bottom-volume'), 100);

    await tester.runAsync(() => lib.setVolumeBoost(on: true, percent: 300));
    await tester.pump();
    expect(top(tester, 'video-bottom-volume'), 300);

    await tester.runAsync(() => lib.setVolumeBoost(percent: 150));
    await tester.pump();
    expect(top(tester, 'video-bottom-volume'), 150);

    await tester.runAsync(() => lib.setVolumeBoost(on: false));
    await tester.pump();
    expect(top(tester, 'video-bottom-volume'), 100);
  });
}
