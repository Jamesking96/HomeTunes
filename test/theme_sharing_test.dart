// Tests for 0.1.29: typing or pasting a colour code in the colour picker, and sharing themes
// (the theme code and file, reading them back safely, adding an imported theme without
// clashing with the user's own, and the Share / Import dialogs on screen).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/appearance_settings.dart';
import 'package:hometunes/ui/screens/settings/theme_sharing.dart';
import 'package:hometunes/ui/theme.dart';
import 'package:provider/provider.dart';

final sunset = defaultPalette.copyWith(
  id: 'saved:x',
  name: 'Sunset',
  accent: const Color(0xFFFFA23A),
  bg: const Color(0xFF1E1412),
);

void main() {
  group('Colour codes', () {
    test('the usual ways of writing one', () {
      const orange = Color(0xFFFF7A59);
      expect(parseColourCode('#FF7A59'), orange);
      expect(parseColourCode('ff7a59'), orange);
      expect(parseColourCode('  #ff7a59  '), orange);
      expect(parseColourCode('"#FF7A59";'), orange);
      expect(parseColourCode('0xFF7A59'), orange);
      expect(parseColourCode('#F75'), const Color(0xFFFF7755)); // short form
    });

    test('anything else is refused', () {
      for (final s in ['', '#', 'orange', '#FF7A5', '#FF7A599', '#GG7A59', '#FF 7A 59', 'rgb(1,2,3)']) {
        expect(parseColourCode(s), isNull, reason: s);
      }
    });
  });

  group('Theme codes and files', () {
    test('a code comes back as the same theme', () {
      final code = themeCode(sunset);
      expect(code, startsWith(themeCodePrefix));
      expect(code, isNot(contains('='))); // no padding for chat apps to mangle
      final back = readSharedTheme(code);
      expect(back.name, 'Sunset');
      expect(back.toJson()..remove('id'), sunset.toJson()..remove('id'));
    });

    test('a code pasted with the rest of the message still works', () {
      final msg = 'Try my theme!\n${themeCode(sunset)}\nlet me know what you think';
      expect(readSharedTheme(msg).accent, sunset.accent);
    });

    test('a theme file is readable JSON and comes back the same', () {
      final text = themeFileText(sunset);
      final json = jsonDecode(text) as Map;
      expect(json['hometunesTheme'], themeFormatVersion);
      expect(json['background'], '#1E1412');
      expect(json.containsKey('id'), isFalse); // this device's id isn't shared
      expect(readSharedTheme(text).bg, sunset.bg);
      expect(themeFileName(sunset), 'Sunset.hometunes-theme');
      expect(themeFileName(sunset.copyWith(name: 'a/b:c?')), 'abc.hometunes-theme');
    });

    test('broken, partial or odd input gives a plain message', () {
      String message(String s) {
        try {
          readSharedTheme(s);
          return 'no error';
        } on FormatException catch (e) {
          return e.message;
        }
      }

      expect(message(''), contains('Paste'));
      expect(message('hello'), contains('start with'));
      final code = themeCode(sunset);
      expect(message(code.substring(0, 40)), anyOf(contains('incomplete'), contains('missing')));
      final noText = {...sharedThemeJson(sunset)}..remove('text');
      expect(message(jsonEncode(noText)), contains('missing'));
      expect(message(jsonEncode({...noText, 'hometunesTheme': 2})), contains('newer version'));
      expect(message('x' * (maxSharedThemeLength + 1)), contains('too long'));
      expect(message(jsonEncode({...sharedThemeJson(sunset), 'accent': 'orange'})), contains('missing'));
    });

    test('shared names are tidied', () {
      final long = readSharedTheme(jsonEncode({...sharedThemeJson(sunset), 'name': 'A\u0000B\n  C${'x' * 80}'}));
      expect(long.name, startsWith('A B C'));
      expect(long.name.length, lessThanOrEqualTo(maxThemeNameLength));
      expect(readSharedTheme(jsonEncode({...sharedThemeJson(sunset), 'name': '   '})).name, 'Shared theme');
    });

    test('names that are taken get a number', () {
      expect(uniqueThemeName('Sunset', ['Night']), 'Sunset');
      expect(uniqueThemeName('Sunset', ['sunset', 'Sunset (2)']), 'Sunset (3)');
    });
  });

  group('Adding an imported theme', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_themeshare'));
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('gets its own id and name, and is used; the same colours again aren\'t added twice', () async {
      final lib = LibraryModel(Storage.at(dir));
      await lib.saveTheme(sunset.toJson(), use: false); // the user's own "Sunset"
      final shared = readSharedTheme(themeCode(sunset.copyWith(accent: const Color(0xFF5AB4FF))));

      final (added, isNew) = await addSharedTheme(lib, shared);
      expect(isNew, isTrue);
      expect(added.name, 'Sunset (2)');
      expect(added.id, isNot('saved:x'));
      expect(lib.themeId, added.id);
      expect(lib.savedThemes, hasLength(2));

      final (again, isNewAgain) = await addSharedTheme(lib, shared);
      expect(isNewAgain, isFalse);
      expect(again.id, added.id);
      expect(lib.savedThemes, hasLength(2));

      // Saved to disk like any other theme.
      final reread = LibraryModel(Storage.at(dir));
      await reread.load();
      expect(reread.savedThemes.map((t) => t['name']), containsAll(['Sunset', 'Sunset (2)']));
    });
  });

  group('On screen', () {
    late Directory dir;
    late LibraryModel lib;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_themeshare_ui');
      lib = LibraryModel(Storage.at(dir));
    });

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
            return RedrawOnThemeChange(
              look: look,
              child: MaterialApp(theme: buildTheme(look.palette, look.corners), home: home),
            );
          },
        ),
      ));
      await tester.pump();
    }

    Future<Color?> pick(WidgetTester tester, PickerMode mode, String code) async {
      Color? picked;
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  picked = await showColourPicker(context, title: 'Colour', initial: const Color(0xFF808080), mode: mode),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('colour-code')), code);
      await tester.pump();
      await tester.tap(find.text('Use this colour'));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('a typed colour code is used exactly', (tester) async {
      expect(await pick(tester, PickerMode.any, '#3a7bd5'), const Color(0xFF3A7BD5));
    });

    testWidgets('a code that isn\'t one says so, and the sliders update the code', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showColourPicker(context, title: 'Colour', initial: const Color(0xFF101114), mode: PickerMode.any),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      TextField field() => tester.widget<TextField>(find.byKey(const ValueKey('colour-code')));
      expect(field().controller!.text, '#101114');
      await tester.enterText(find.byKey(const ValueKey('colour-code')), '#12');
      await tester.pump();
      expect(find.text('Type a colour code like #FF7A59'), findsOneWidget);
      await tester.tap(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle && (w.decoration as BoxDecoration).color == const Color(0xFFFFFFFF)));
      await tester.pump();
      expect(find.text('Type a colour code like #FF7A59'), findsNothing);
      expect(field().controller!.text, '#FFFFFF');
    });

    testWidgets('Your own: a code too light for a background is darkened, and it says so', (tester) async {
      await pumpApp(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showColourPicker(context,
                  title: 'Background colour', initial: const Color(0xFF101114), mode: PickerMode.darkBackground),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('colour-code')), '#FFFFFF');
      await tester.pump();
      expect(find.textContaining('#FFFFFF changed to'), findsOneWidget);
    });

    testWidgets('Share shows the code; Import reads it back and adds the theme', (tester) async {
      await pumpApp(tester, const Scaffold(body: AppearanceSettings()));
      lib.saveTheme(sunset.toJson(), use: false);
      await tester.pumpAndSettle();

      // Share… from the theme's ⋮ menu.
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('saved-theme:saved:x')), matching: find.byTooltip('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('menu-share-theme')));
      await tester.pumpAndSettle();
      expect(find.text('Share "Sunset"'), findsOneWidget);
      final code = tester.widget<SelectableText>(find.byKey(const ValueKey('theme-code'))).data!;
      expect(readSharedTheme(code).name, 'Sunset');
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Import a theme: a mistake first, then the code.
      await tester.ensureVisible(find.byKey(const ValueKey('import-theme')));
      await tester.tap(find.byKey(const ValueKey('import-theme')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('import-theme-code')), 'not a theme');
      await tester.tap(find.byKey(const ValueKey('read-theme-code')));
      await tester.pump();
      expect(find.textContaining('start with'), findsOneWidget);

      final friends = themeCode(sunset.copyWith(name: 'Ocean', accent: const Color(0xFF3CCFCF)));
      await tester.enterText(find.byKey(const ValueKey('import-theme-code')), friends);
      await tester.tap(find.byKey(const ValueKey('read-theme-code')));
      await tester.pumpAndSettle();
      expect(find.text('Add "Ocean"?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('add-imported-theme')));
      await tester.pumpAndSettle();

      expect(lib.savedThemes, hasLength(2));
      expect(AppColors.current.name, 'Ocean');
      expect(AppColors.current.accent, const Color(0xFF3CCFCF));
      expect(find.text('Ocean'), findsWidgets);
      lib.setTheme(id: 'default');
      await tester.pumpAndSettle();
    });
  });
}
