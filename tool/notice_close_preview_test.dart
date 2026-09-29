// Draws the 0.1.30 change off-screen and saves a picture to C:\Temp\ht\preview (nothing is shown
// on screen): a notice at the bottom of a page with its Undo button and the new ✕ to close it.
// Uses Windows' Segoe UI for text and Flutter's own icon font so the ✕ shows.
//   flutter test tool/notice_close_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/theme.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('0.1.30 preview', (tester) async {
    await tester.runAsync(() async {
      Future<void> load(String family, String path) async {
        final l = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
        await l.load();
      }

      await load('Roboto', r'C:\Windows\Fonts\segoeui.ttf');
      await load('MaterialIcons',
          '${Platform.environment['USERPROFILE']}\\flutter\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf');
    });
    Directory(out).createSync(recursive: true);
    tester.view.physicalSize = const Size(700, 260);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('"Your own" is back to its default colours'),
                  duration: const Duration(minutes: 1),
                  action: SnackBarAction(label: 'Undo', onPressed: () {}),
                )),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('$out\\notice-close.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
