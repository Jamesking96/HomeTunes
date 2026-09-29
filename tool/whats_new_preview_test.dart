// Draws the 0.1.28 "What's new" pop-up off-screen and saves a picture to C:\Temp\ht\preview
// (nothing is shown on screen), as it would look after updating from 0.1.22 to 0.1.24, using
// the real notes from those two release pages. Uses Windows' Segoe UI so the text is readable.
//   flutter test tool/whats_new_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/update_checker.dart';
import 'package:hometunes/ui/screens/settings/whats_new_ui.dart';
import 'package:hometunes/ui/theme.dart';

ReleaseInfo _release(String version, String notes) => ReleaseInfo.fromJson({
      'tag_name': 'v$version',
      'html_url': 'https://github.com/$releasesRepo/releases/tag/v$version',
      'body': "## What's new in $version\n\n$notes\n\n---\n\n# Guide",
      'assets': <Object>[],
    })!;

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('What\'s new preview', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    Directory(out).createSync(recursive: true);
    tester.view.physicalSize = const Size(1100, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    final releases = [
      _release('0.1.24', '''- **Colour themes.** New **Settings > Appearance** page. Pick **Default** (the look you know), **Midnight** (navy with a sky-blue highlight) or **Forest** (dark green-grey with a green highlight). The whole app changes as soon as you tap one.
- **Make your own.** Choose **Your own** and pick a highlight colour and a background colour, from suggested colours or with sliders. HomeTunes works out the rest and keeps text easy to read.
- Your theme is saved in backups, so it comes across when you restore on another device.'''),
      _release('0.1.23', '''- **Volume everywhere.** Now Playing has a volume slider under the play buttons, so you can change the volume with the cover or the lyrics showing. On the phone, the mini player has a speaker button that opens a small volume slider.
- **Check for updates.** Go to **Settings > About > Check for updates** to see if there's a newer version.
- **Windows updates itself.** On a PC where HomeTunes was installed with the installer, saying **Update** downloads the new version, checks it, then closes HomeTunes, updates it and opens it again.'''),
    ];

    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: WhatsNewDialog(version: '0.1.24', from: '0.1.22', afterUpdate: true, releases: releases),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
      File('$out\\whats-new.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
