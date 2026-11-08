// Draws the opening screen (lib/ui/start_screen.dart, 0.2.13) off-screen as PNGs: a TV-shaped
// screen and a phone held upright, with "Loading your library…" showing. Not part of the normal
// test run (it lives in tool/). Run on the PC:
//   flutter test tool/start_screen_shot_test.dart --dart-define=OUT=C:\Temp\ht\preview
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/start_screen.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  for (final (name, size) in [('start_tv', const Size(1920, 1080)), ('start_phone', const Size(1080, 2400))]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(key: key, child: const StartScreen()));
      // Let the picture load and decode for real, then show the words.
      await tester.runAsync(() async {
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    });
  }
}
