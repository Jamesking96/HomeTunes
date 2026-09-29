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
  tearDown(() {
    AppColors.current = defaultPalette;
    AppShape.scale = 1.0;
  });

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

  group('Advanced themes', () {
    test('a saved theme round-trips through settings, every colour included', () {
      final p = lightStarter.copyWith(id: 'saved:abc', name: 'Paper');
      final back = AppPalette.fromJson(p.toJson());
      expect(back, p);
      expect(back!.isLight, isTrue);
    });

    test('a damaged saved theme is skipped rather than half-read', () {
      final json = lightStarter.copyWith(id: 'saved:x').toJson()..remove('text');
      expect(AppPalette.fromJson(json), isNull);
      expect(AppPalette.fromJson({'id': 'saved:x'}), isNull);
      expect(AppPalette.fromJson('nope'), isNull);
    });

    test('the ready-made themes and the light starting point are all easy to read', () {
      for (final p in [...builtInPalettes, lightStarter]) {
        expect(p.readabilityProblems(), isEmpty, reason: p.name);
      }
    });

    test('hard-to-read colours are pointed out in plain words', () {
      final p = lightStarter.copyWith(text: const Color(0xFFEEEEEE), accent: const Color(0xFFF0F0F0));
      final problems = p.readabilityProblems();
      expect(problems, contains('Text is hard to read on the background.'));
      expect(problems, contains('The highlight colour is hard to see on the background.'));
    });

    test('contrast: black on white is 21, a colour on itself is 1', () {
      expect(contrast(Colors.black, Colors.white), closeTo(21, 0.01));
      expect(contrast(Colors.red, Colors.red), 1);
    });

    test('light themes pin every Material colour; the ready-made ones stay as they were', () {
      expect(buildTheme(lightStarter).brightness, Brightness.light);
      expect(buildTheme(lightStarter).colorScheme.onSurface, lightStarter.text);
      expect(buildTheme(defaultPalette).brightness, Brightness.dark);
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

    test('saved themes, text size and corners survive a restart', () async {
      final a = LibraryModel(Storage.at(dir));
      await a.saveTheme(lightStarter.copyWith(id: 'saved:one', name: 'Paper').toJson());
      await a.setLook(textSize: 1.15, cornerRoundness: 0.5);
      final b = LibraryModel(Storage.at(dir));
      await b.load();
      expect(b.themeId, 'saved:one');
      expect(paletteOfSettings(b).name, 'Paper');
      expect(b.textSize, 1.15);
      expect(b.cornerRoundness, 0.5);
      // Silly values from a hand-edited file are kept within range.
      await Storage.at(dir).write('settings.json', {'textSize': 9, 'cornerRoundness': -3, 'savedThemes': 'x'});
      await b.load();
      expect(b.textSize, 1.5);
      expect(b.cornerRoundness, 0);
      expect(b.savedThemes, isEmpty);
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
        child: Selector<LibraryModel, AppLook>(
          selector: (_, l) => lookOfSettings(l),
          builder: (context, look, _) {
            AppColors.current = look.palette;
            AppShape.scale = look.corners;
            return RedrawOnThemeChange(
              look: look,
              child: MaterialApp(
                theme: buildTheme(look.palette, look.corners),
                builder: (context, child) => withTextSize(context, look.textSize, child!),
                home: home,
              ),
            );
          },
        ),
      ));
      await tester.pump();
    }

    testWidgets('Advanced: a new light theme is saved, used, and recolours everything', (tester) async {
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
      await tester.ensureVisible(find.byKey(const ValueKey('new-light-theme')));
      await tester.tap(find.byKey(const ValueKey('new-light-theme')));
      await tester.pumpAndSettle();
      expect(find.text('Edit theme'), findsOneWidget);
      expect(find.byKey(const ValueKey('theme-problems')), findsNothing); // the light start is readable
      await tester.enterText(find.byKey(const ValueKey('theme-name')), 'Paper');
      await tester.tap(find.byKey(const ValueKey('save-theme')));
      await tester.pumpAndSettle();

      expect(lib.savedThemes, hasLength(1));
      expect(lib.themeId, startsWith('saved:'));
      expect(AppColors.current.name, 'Paper');
      expect(AppColors.current.isLight, isTrue);
      expect(probe(), lightStarter.surface);
      expect(find.text('Paper'), findsWidgets); // listed as a card and under Advanced

      // Deleting the theme in use goes back to Default.
      // The screen changes at once; the file save isn't waited for (it can't finish inside a
      // widget test's pretend clock, and a later save would queue behind it).
      lib.deleteTheme(lib.themeId);
      await tester.pumpAndSettle();
      expect(AppColors.current, defaultPalette);
      expect(probe(), defaultPalette.surface);
    });

    testWidgets('Advanced: text size and corners apply everywhere', (tester) async {
      late double scale;
      await pumpApp(
        tester,
        Scaffold(body: Builder(builder: (context) {
          scale = MediaQuery.textScalerOf(context).scale(10) / 10;
          return const SizedBox();
        })),
      );
      expect(scale, 1.0);
      lib.setLook(textSize: 1.3, cornerRoundness: 0);
      await tester.pumpAndSettle();
      expect(scale, closeTo(1.3, 0.001));
      expect(AppShape.scale, 0);
      expect(AppShape.circular(12), BorderRadius.zero);
      lib.setLook(textSize: 1.0, cornerRoundness: 1.0);
      await tester.pumpAndSettle();
    });

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
                  title: 'Background colour', initial: const Color(0xFFFFFFFF), mode: PickerMode.darkBackground),
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
