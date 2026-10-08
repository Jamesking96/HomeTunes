// Draws PosterPicture (a collection's picture) off-screen with a tall and a wide picture, into
// C:\Temp\ht\preview\poster-*.png (or the folder in --dart-define=OUT=...), to check the whole-picture-over-blur look.
//   flutter test tool/poster_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/screens/video_pictures.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');
  testWidgets('poster previews', (tester) async {
    final dir = freshPreviewFolder('poster_preview');
    addTearDown(() => dir.deleteSync(recursive: true));
    File make(String name, int w, int h) {
      final pic = img.Image(width: w, height: h);
      img.fillRect(pic, x1: 0, y1: 0, x2: w - 1, y2: h - 1, color: img.ColorRgb8(180, 60, 40));
      img.fillRect(pic, x1: w ~/ 10, y1: h ~/ 10, x2: w * 9 ~/ 10, y2: h ~/ 4, color: img.ColorRgb8(240, 230, 200));
      img.fillCircle(pic, x: w ~/ 2, y: h * 2 ~/ 3, radius: w ~/ 4, color: img.ColorRgb8(60, 140, 220));
      return File(p.join(dir.path, name))..writeAsBytesSync(img.encodeJpg(pic));
    }

    for (final (name, file) in [('tall', make('tall.jpg', 400, 600)), ('wide', make('wide.jpg', 1280, 720))]) {
      final key = GlobalKey();
      // Pictures only load in real time: load it first, from an empty page, so the widget finds
      // it ready (asking while it's drawn leaves it waiting on the test's pretend clock).
      final blank = GlobalKey();
      await tester.pumpWidget(MaterialApp(home: SizedBox(key: blank)));
      await tester.runAsync(() => precacheImage(
          ResizeImage(FileImage(file), width: 640, policy: ResizeImagePolicy.fit), blank.currentContext!));
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 480, height: 270, child: PosterPicture(file: file.path)),
          ),
        ),
      ));
      await tester.pump();
      await tester.runAsync(() async {
        final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
        Directory(out).createSync(recursive: true);
        File('$out\\poster-$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
  });
}

// A fixed folder (emptied first), so the same path shows in the pictures every run and
// tool\compare_previews.ps1 can compare them byte for byte (8 Oct 2026).
Directory freshPreviewFolder(String name) {
  final d = Directory('C:\\Temp\\ht\\preview-data\\$name');
  if (d.existsSync()) d.deleteSync(recursive: true);
  return d..createSync(recursive: true);
}
