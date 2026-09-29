// Draws the real Settings screen (open on Appearance) in each colour theme, off-screen, and
// saves the pictures to C:\Temp\ht\preview (or the folder in --dart-define=OUT=...). Nothing
// is shown on screen and nothing is saved in the app's data. Uses Windows' Segoe UI so the text
// is readable in the pictures.
//   flutter test tool/theme_preview_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/update_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/ui/screens/settings/appearance_settings.dart';
import 'package:hometunes/ui/screens/settings/settings_screen.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

void main() {
  const out = String.fromEnvironment('OUT', defaultValue: r'C:\Temp\ht\preview');

  testWidgets('theme previews', (tester) async {
    await tester.runAsync(() async {
      for (final f in [r'C:\Windows\Fonts\segoeui.ttf', r'C:\Windows\Fonts\segoeuib.ttf']) {
        final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
        await loader.load();
      }
    });
    PackageInfo.setMockInitialValues(
        appName: 'HomeTunes', packageName: 'x', version: '0.1.24', buildNumber: '24', buildSignature: '');
    Directory(out).createSync(recursive: true);
    final dir = Directory.systemTemp.createTempSync('hometunes_preview');
    final lib = LibraryModel(Storage.at(dir));
    final nav = AppNav();
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey();

    for (final t in [
      ('default', null, null),
      ('midnight', null, null),
      ('forest', null, null),
      ('custom', '#E35BD8', '#1A1020'),
    ]) {
      await tester.runAsync(() => lib.setTheme(id: t.$1, accent: t.$2, background: t.$3));
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: lib),
          ChangeNotifierProvider.value(value: nav),
          ChangeNotifierProvider(create: (_) => EqualizerModel(Storage.at(dir))),
          ChangeNotifierProvider(create: (_) => UpdateModel(Storage.at(dir), readVersion: () async => '0.1.24')),
        ],
        child: Selector<LibraryModel, AppPalette>(
          selector: (_, l) => paletteOfSettings(l),
          builder: (context, palette, _) {
            AppColors.current = palette;
            return RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(palette),
                home: const SettingsScreen(),
              ),
            );
          },
        ),
      ));
      await tester.pumpAndSettle();
      nav.openSettings('appearance');
      await tester.pumpAndSettle();
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out\\theme-${t.$1}.png').writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    AppColors.current = defaultPalette;
  });
}
