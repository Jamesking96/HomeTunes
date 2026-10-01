// 0.1.42: a video's page shows a loading page straight away, while the real page (and its player)
// starts behind it, so the app doesn't look frozen while a big file opens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/screens/video_player_screen.dart';

void main() {
  tearDown(() => VideoPlayerScreen.debugPage = null);

  testWidgets('the loading page shows first, then fades once the video is showing', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    VoidCallback? ready;
    var built = 0;
    VideoPlayerScreen.debugPage = (id, onReady) {
      built++;
      ready = onReady;
      return Scaffold(body: Text('Real page $id'));
    };
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const Scaffold(body: Text('Open'))));
    navigator.currentState!.push(MaterialPageRoute(builder: (_) => const VideoPlayerScreen(videoId: 'v1')));
    await tester.pump(); // the new page's first frame is offstage
    await tester.pump(const Duration(milliseconds: 50));

    // Straight away: the loading page, and the real page hasn't started yet.
    expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);
    expect(find.text('Opening the video…'), findsOneWidget);
    expect(built, 0);

    // After the slide-in: the real page starts behind the loading page.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(built, greaterThan(0));
    expect(find.text('Real page v1'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-loading')), findsOneWidget);

    // The video is showing: the loading page fades away and is gone.
    ready!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-loading')), findsNothing);
    expect(find.text('Real page v1'), findsOneWidget);
  });

  testWidgets('back works from the loading page', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    VideoPlayerScreen.debugPage = (id, onReady) => const Scaffold(body: Text('Real page'));
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const Scaffold(body: Text('Open'))));
    navigator.currentState!.push(MaterialPageRoute(builder: (_) => const VideoPlayerScreen(videoId: 'v1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(VideoPlayerScreen), findsNothing);
  });
}
