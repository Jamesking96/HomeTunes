// 0.1.59: video buttons. The video page and a full-screen music video need the real video
// engine, which tests can't open, so this checks the pieces they're built from: the top
// button row media_kit shows in full screen ("Leave full screen") and the white skip icons
// over a full-screen music video.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_player_look.dart';
import 'package:hometunes/ui/widgets/listening_controls.dart' show SkipIcon;
import 'package:hometunes/ui/widgets/video_controls_look.dart';

void main() {
  test('full screen gets buttons along the top; the page keeps none', () {
    const leave = SizedBox(key: ValueKey('leave'));
    final full = desktopControlsTheme(VideoPlayerLook.standard, Colors.blue, bar: const [], top: const [leave]);
    expect(full.topButtonBar, hasLength(1));
    expect(desktopControlsTheme(VideoPlayerLook.standard, Colors.blue, bar: const []).topButtonBar, isEmpty);
    final phone = phoneControlsTheme(VideoPlayerLook.standard, Colors.blue,
        bar: const [], skipBack: const Duration(seconds: 10), skipForward: const Duration(seconds: 10), top: const [leave]);
    expect(phone.topButtonBar, hasLength(1));
  });

  testWidgets('skip icons can be white over a video', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Row(children: [
        SkipIcon(key: ValueKey('white'), seconds: 10, forward: false, color: Colors.white),
        SkipIcon(key: ValueKey('usual'), seconds: 30, forward: true),
      ]),
    ));
    final white = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('white')), matching: find.text('10')));
    expect(white.style?.color, Colors.white);
    final arrow = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('white')), matching: find.byType(Icon)));
    expect(arrow.color, Colors.white);
    final usual = tester.widget<Text>(find.descendant(of: find.byKey(const ValueKey('usual')), matching: find.text('30')));
    expect(usual.style?.color, isNull);
  });
}
