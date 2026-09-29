// Tests for colour themes (0.1.24): the ready-made themes, "Your own" staying readable, saving
// the choice in settings.json, the Appearance page, the colour picker, and the whole app being
// redrawn in the new colours when the theme changes (RedrawOnThemeChange).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/appearance_settings.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  tearDown(() => AppColors.current = defaultPalette);

  group('Themes', () {
    test('Default is exactly the original look', () {
      expect(defaultPalette.accent, const Color(0xFFFF7A59));
      expect(defaultPalette.bg, const Color(0xFF101114));
      expect(defaultPalette.surface, const Color(0xFF1A1C21));
      expect(defaultPalette.textDim, const Color(0xFFA3A8B3));
      expect(builtInPalettes.map((p) => p.id), ['default', 'midnight', 'forest']);
    });

    test('your own: a light background is darkened, a dark highlight brightened', () {
      final p = AppPalette.fromColours(accent: const Color(0xFF200000), background: const Color(0xFFFFFFFF));
      expect(HSLColor.fromColor(p.bg).lightness, lessThanOrEqualTo(AppPalette.maxBackgroundLightness + 0.01));
      expect(HSLColor.fromColor(p.accent).lightness, greaterThanOrEqualTo(AppPalette.minAccentLightness - 0.01));
      // Panels step up from the background, and grey text is well above it.
      expect(p.surface.computeLuminance(), greaterThan(p.bg.computeLuminance()));
      expect(p.surfaceHigh.computeLuminance(), greaterThan(p.surface.computeLuminance()));
      expect(p.textDim.computeLuminance(), greaterThan(p.surfaceHigh.computeLuminance()));
    });

    test('colours already in range are used as picked', () {
      final p = AppPalette.fromColours(accent: const Color(0xFF4CC38A), background: const Color(0xFF0D1321));
      expect(p.accent, const Color(0xFF4CC38A));
      expect(p.bg, const Color(0xFF0D1321));
    });

    test('text on a filled button is black on bright highlights, white on deep ones', () {
      expect(AppPalette.fromColours(accent: const Color(0xFFF2C84B), background: Colors.black).onAccent, Colors.black);
      expect(AppPalette.fromColours(accent: const Color(0xFF6F3BFF), background: Colors.black).onAccent, Colors.white);
    });

    test('saved values', () {
      expect(colourToHex(const Color(0xFF0a0b0c)), '#0A0B0C');
      expect(colourFromHex('#0A0B0C'), const Color(0xFF0A0B0C));
      expect(colourFromHex('nope'), isNull);
      expect(colourFromHex(12), isNull);
      final a = const Color(0xFF4CC38A), b = const Color(0xFF0D1321);
      expect(paletteFor('midnight', customAccent: a, customBackground: b).name, 'Midnight');
      expect(paletteFor('custom', customAccent: a, customBackground: b).accent, a);
      expect(paletteFor('something old', customAccent: a, customBackground: b), defaultPalette);
    });
  });

  group('Saving', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_theme'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    test('the theme and your own colours survive a restart', () async {
      final a = LibraryModel(Storage.at(dir));
      await a.setTheme(id: 'custom', accent: '#4cc38a', background: '#0D1321');
      final b = LibraryModel(Storage.at(dir));
      await b.load();
      expect(b.themeId, 'custom');
      expect(b.customAccent, '#4CC38A');
      expect(paletteOfSettings(b).bg, const Color(0xFF0D1321));
    });

    test('a hand-edited settings file with bad colours falls back', () async {
      await Storage.at(dir).write('settings.json', {'theme': 'custom', 'customAccent': 'orange', 'customBackground': 5});
      final lib = LibraryModel(Storage.at(dir));
      await lib.load();
      expect(lib.customAccent, isNull);
      final p = paletteOfSettings(lib);
      expect(p.accent, defaultPalette.accent);
      expect(p.bg, defaultPalette.bg);
    });
  });

  group('On screen', () {
    late LibraryModel lib;
    setUp(() => lib = LibraryModel(Storage.at(Directory(Directory.systemTemp.path))));

    /// The same wiring as HomeTunesApp: the theme comes from the settings, and a change redraws
    /// everything. [probe] reads AppColors directly, like many of the app's widgets.
    Future<void> pumpApp(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: lib,
        child: Selector<LibraryModel, AppPalette>(
          selector: (_, l) => paletteOfSettings(l),
          builder: (context, palette, _) {
            AppColors.current = palette;
            return RedrawOnThemeChange(
              palette: palette,
              child: MaterialApp(theme: buildTheme(palette), home: home),
            );
          },
        ),
      ));
      await tester.pump();
    }

    testWidgets('picking a theme recolours the whole app, even colours read directly', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Column(children: [
            const _Probe(),
            const Expanded(child: AppearanceSettings()),
          ]),
        ),
      );
      Color probe() => tester.widget<ColoredBox>(find.byKey(const ValueKey('probe'))).color;
      expect(probe(), defaultPalette.surface);
      expect(find.byKey(const ValueKey('theme:custom')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('theme:midnight')));
      await tester.pumpAndSettle();
      expect(lib.themeId, 'midnight');
      expect(AppColors.current.id, 'midnight');
      expect(probe(), builtInPalettes[1].surface); // redrawn although nothing it watches changed

      await tester.tap(find.byKey(const ValueKey('theme:default')));
      await tester.pumpAndSettle();
      expect(probe(), defaultPalette.surface);
    });

    testWidgets('the colour picker: a suggestion, then "Use this colour"', (tester) async {
      Color? picked;
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => picked = await showColourPicker(context,
                  title: 'Background colour', initial: const Color(0xFFFFFFFF), background: true),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Shade'), findsOneWidget);
      await tester.tap(find.text('Use this colour'));
      await tester.pumpAndSettle();
      // White isn't allowed as a background: it comes back dark.
      expect(HSLColor.fromColor(picked!).lightness, lessThanOrEqualTo(AppPalette.maxBackgroundLightness + 0.01));
    });
  });
}

/// Reads AppColors at build time without watching anything.
class _Probe extends StatelessWidget {
  const _Probe();
  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: const ValueKey('probe'), color: AppColors.surface, child: const SizedBox(height: 10));
}
