// 1 Oct (after 0.1.42): the bottom bar and the video player's volume came apart again. These tests
// open a video page the way the app does (VideoPlayerScreen, with its loading page) and check the
// bar follows the video's player: it switches to the video, and its volume follows the player's.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/state/now_watching.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/ui/screens/video_player_screen.dart';
import 'package:hometunes/ui/widgets/video_now_playing.dart';
import 'package:provider/provider.dart';

import 'now_watching_test.dart' show FakeMusic, FakeVideo;
import 'package:hometunes/models/video_item.dart';

const _episode = VideoItem(id: 'v1', path: '/v/Silo S01E02.mkv', title: 'Holston', collection: 'Silo');

/// Stands in for the real video page: attaches its player as the real one does.
class _FakePage extends StatefulWidget {
  const _FakePage(this.w, this.video, this.onReady);
  final NowWatching w;
  final FakeVideo video;
  final VoidCallback onReady;
  @override
  State<_FakePage> createState() => _FakePageState();
}

class _FakePageState extends State<_FakePage> {
  @override
  void initState() {
    super.initState();
    widget.w.attach(widget.video);
    widget.w.showing(_episode);
  }

  @override
  void dispose() {
    widget.w.detach(widget.video);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('Video page'));
}

void main() {
  tearDown(() => VideoPlayerScreen.debugPage = null);

  testWidgets('the bar follows a video opened through its loading page', (tester) async {
    final music = FakeMusic();
    final w = NowWatching(music);
    final video = FakeVideo();
    VideoPlayerScreen.debugPage = (id, onReady) => _FakePage(w, video, onReady);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PlayerModel>.value(value: music),
          ChangeNotifierProvider.value(value: w),
        ],
        child: MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(visualDensity: VisualDensity.compact),
          // The bar sits outside the pages, as in the app (its tooltips need an Overlay here).
          builder: (context, child) => Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Scaffold(
                  body: child,
                  // As DesktopPlayerBar chooses (the fake music can't draw the music bar).
                  bottomNavigationBar: SizedBox(
                    height: 88,
                    child: Builder(
                      builder: (context) =>
                          context.watch<NowWatching>().inFront ? const VideoPlayerBar() : const Text('Music bar'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          home: const Text('Home'),
        ),
      ),
    );
    navigator.currentState!.push(MaterialPageRoute(builder: (_) => const VideoPlayerScreen(videoId: 'v1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Video page'), findsOneWidget);

    // The video starts: the bar shows it.
    await tester.runAsync(() async {
      await video.play();
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(find.byKey(const ValueKey('video-player-bar')), findsOneWidget);

    // The player's own volume bar: the bottom bar's follows.
    await tester.runAsync(() async {
      await video.setVolume(40);
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    final slider = tester.widgetList<Slider>(find.byType(Slider)).last;
    expect(slider.value, 40);
  });
}
