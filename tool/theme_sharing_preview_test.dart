// Draws the 0.1.29 changes off-screen and saves pictures to C:\Temp\ht\preview (nothing is
// shown on screen): the colour picker with a typed colour code, the Share dialog with its theme
// code, and the Import dialog showing a friend's theme before it's added. Uses Windows' Segoe UI
// so the text is readable. Invented theme names only.
//   flutter test tool/theme_sharing_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/appearance_settings.dart';
import 'package:hometunes/ui/screens/settings/theme_sharing.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('0.1.29 previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
      final mono = FontLoader('Consolas')
        ..addFont(Future.value(ByteData.sublistView(File(r'C:\Windows\Fonts\consola.ttf').readAsBytesSync())));
      await mono.load();
    });
    Directory(out).createSync(recursive: true);
    tester.view.physicalSize = const Size(900, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = freshPreviewFolder('hometunes_share_preview');
    final lib = LibraryModel(Storage.at(dir));
    final key = GlobalKey();
    BuildContext host() => tester.element(find.byKey(const ValueKey('host')));

    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: lib,
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const Scaffold(body: SizedBox.expand(key: ValueKey('host'))),
        ),
      ),
    ));
    await tester.pump();

    Future<void> shoot(String name) => tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final png = await (await b.toImage()).toByteData(format: ui.ImageByteFormat.png);
          File('$out\\$name.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
    Future<void> close() async {
      Navigator.of(host()).pop();
      await tester.pumpAndSettle();
    }

    // 1. The colour picker (Advanced) with a code typed in.
    showColourPicker(host(), title: 'Highlight', initial: const Color(0xFFFF7A59), mode: PickerMode.any);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('colour-code')), '#3CCFCF');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await shoot('share-colour-code');
    await close();

    // 2. Share a saved theme.
    final ocean = defaultPalette.copyWith(
        id: 'saved:o', name: 'Ocean', accent: const Color(0xFF3CCFCF), bg: const Color(0xFF0D1321),
        surface: const Color(0xFF141B2A), surfaceHigh: const Color(0xFF1C2436));
    showShareTheme(host(), ocean);
    await tester.pumpAndSettle();
    await shoot('share-dialog');
    await close();

    // 3. Import a friend's theme: the preview before adding it.
    showImportTheme(host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('import-theme-code')),
        themeCode(ocean.copyWith(name: 'Sam\'s sunset', accent: const Color(0xFFFFA23A), bg: const Color(0xFF1E1412),
            surface: const Color(0xFF281C19), surfaceHigh: const Color(0xFF33251F))));
    await tester.tap(find.byKey(const ValueKey('read-theme-code')));
    await tester.pumpAndSettle();
    await shoot('share-import');
    await close();
  });
}

// A fixed folder (emptied first), so the same path shows in the pictures every run and
// tool\compare_previews.ps1 can compare them byte for byte (8 Oct 2026).
Directory freshPreviewFolder(String name) {
  final d = Directory('C:\\Temp\\ht\\preview-data\\$name');
  if (d.existsSync()) d.deleteSync(recursive: true);
  return d..createSync(recursive: true);
}
