// The equaliser: presets and their filter text, editing and restoring
// built-in presets, your own presets, music vs audiobook presets, saving,
// and the Equaliser screen.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/eq_preset.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/ui/screens/equalizer_screen.dart';
import 'package:provider/provider.dart';

void main() {
  group('Presets', () {
    test('there are ten bands and every built-in preset has a value for each', () {
      expect(eqBands.length, 10);
      for (final p in builtInEqPresets) {
        expect(p.gains.length, 10, reason: p.name);
        expect(p.builtIn, isTrue);
      }
      expect([for (final p in builtInEqPresets) p.name],
          ['Flat', 'Bass boost', 'Treble boost', 'Vocal', 'Rock', 'Pop', 'Classical', 'Spoken word', 'Headphones']);
    });

    test('presets that boost turn the overall level down at least as far as their biggest boost minus 1 dB', () {
      for (final p in builtInEqPresets) {
        final boost = p.gains.reduce((a, b) => a > b ? a : b);
        if (boost > 0) expect(-p.level, greaterThanOrEqualTo(boost - 1), reason: p.name);
      }
    });

    test('the filter has one peaking filter per band that isn\'t at 0', () {
      expect(eqFilter(null), '');
      expect(eqFilter(builtInEqPresets.first), '');
      final bass = builtInEqPreset('bass')!;
      expect(
        eqFilter(bass),
        'lavfi=[equalizer=f=31:t=o:w=1:g=6.0,equalizer=f=62:t=o:w=1:g=5.0,'
        'equalizer=f=125:t=o:w=1:g=4.0,equalizer=f=250:t=o:w=1:g=2.0]',
      );
    });

    test('the overall level scales the volume', () {
      expect(eqLevelFactor(null), 1.0);
      expect(eqLevelFactor(builtInEqPresets.first), 1.0);
      expect(eqLevelFactor(builtInEqPreset('bass')), closeTo(0.501, 0.001)); // −6 dB ≈ half
    });

    test('saved values out of range are brought back into range', () {
      final p = EqPreset.fromJson({'id': 'x', 'gains': [40, -40, 1.26], 'level': 5});
      expect(p.gains.take(3), [12, -12, 1.5]);
      expect(p.gains.length, 10);
      expect(p.level, 0);
    });
  });

  group('Equaliser settings', () {
    late Directory dir;
    late EqualizerModel eq;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_eq');
      eq = EqualizerModel(Storage.at(dir));
      await eq.load();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    Future<EqualizerModel> reloaded() async {
      await eq.flush();
      final again = EqualizerModel(Storage.at(dir));
      await again.load();
      return again;
    }

    test('starts off, with Flat for music and Spoken word for books', () {
      expect(eq.enabled, isFalse);
      expect(eq.activeFor(book: false), isNull);
      expect(eq.musicPreset.id, 'flat');
      expect(eq.bookPreset.id, 'spoken');
      expect(eq.separateBooks, isTrue);
    });

    test('choosing a preset switches it on; books and music keep their own', () async {
      await eq.choose('rock', forBooks: false);
      expect(eq.enabled, isTrue);
      expect(eq.activeFor(book: false)!.id, 'rock');
      expect(eq.activeFor(book: true)!.id, 'spoken');
      await eq.setSeparateBooks(false);
      expect(eq.activeFor(book: true)!.id, 'rock');
      final again = await reloaded();
      expect(again.enabled, isTrue);
      expect(again.musicPresetId, 'rock');
      expect(again.separateBooks, isFalse);
    });

    test('a built-in preset can be edited, shows as edited, and restored', () async {
      final g = List.of(eq.presetById('rock').gains)..[0] = -3;
      eq.adjust('rock', gains: g, level: -2);
      expect(eq.isEdited('rock'), isTrue);
      expect(eq.presetById('rock').gains.first, -3);
      expect(eq.presetById('rock').level, -2);
      expect(eq.presetById('rock').name, 'Rock');
      expect((await reloaded()).presetById('rock').gains.first, -3);

      await eq.restoreDefault('rock');
      expect(eq.isEdited('rock'), isFalse);
      expect(eq.presetById('rock').soundsLike(builtInEqPreset('rock')!), isTrue);
    });

    test('moving a slider back to where it was counts as not edited', () {
      final original = List.of(eq.presetById('pop').gains);
      eq.adjust('pop', gains: List.of(original)..[3] = 0);
      expect(eq.isEdited('pop'), isTrue);
      eq.adjust('pop', gains: original);
      expect(eq.isEdited('pop'), isFalse);
    });

    test('Restore all puts every built-in back and keeps your own presets', () async {
      eq.adjust('bass', level: 0);
      eq.adjust('vocal', level: -12);
      final mine = await eq.addCustom('Car', from: eq.presetById('bass'));
      await eq.restoreAll();
      expect(eq.isEdited('bass'), isFalse);
      expect(eq.isEdited('vocal'), isFalse);
      expect(eq.presetById(mine).name, 'Car');
    });

    test('your own presets can be made, edited, renamed and deleted', () async {
      final id = await eq.addCustom('  Car stereo ', from: eq.presetById('treble'));
      final p = eq.presetById(id);
      expect(p.name, 'Car stereo');
      expect(p.builtIn, isFalse);
      expect(p.gains, builtInEqPreset('treble')!.gains);
      eq.adjust(id, level: -1);
      await eq.rename(id, 'Car');
      await eq.choose(id, forBooks: false);
      await eq.choose(id, forBooks: true);
      final again = await reloaded();
      expect(again.presetById(id).name, 'Car');
      expect(again.presetById(id).level, -1);

      await eq.delete(id);
      expect(eq.presets.any((x) => x.id == id), isFalse);
      expect(eq.musicPresetId, 'flat');
      expect(eq.bookPresetId, 'spoken');
    });

    test('built-in presets can\'t be deleted or renamed', () async {
      await eq.delete('rock');
      await eq.rename('rock', 'Mine');
      expect(eq.presetById('rock').name, 'Rock');
    });
  });

  group('Equaliser screen', () {
    late EqualizerModel eq;
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('hometunes_eq_ui');
      eq = EqualizerModel(Storage.at(dir));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<void> pump(WidgetTester tester, {bool? forBooks}) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: eq,
        child: MaterialApp(home: EqualizerScreen(forBooks: forBooks)),
      ));
    }

    testWidgets('picking a preset switches the equaliser on and uses it for music', (tester) async {
      await pump(tester);
      expect(find.textContaining('The equaliser is off'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('eq-preset-bass')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(eq.enabled, isTrue);
      expect(eq.musicPresetId, 'bass');
      expect(find.textContaining('The equaliser is off'), findsNothing);
    });

    testWidgets('opened from a book, it sets the audiobook preset', (tester) async {
      await pump(tester, forBooks: true);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('eq-preset-classical')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(eq.bookPresetId, 'classical');
      expect(eq.musicPresetId, 'flat');
    });

    testWidgets('Edit shows ten band sliders; changing one marks the preset edited, and Restore default undoes it',
        (tester) async {
      await pump(tester);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('eq-preset-rock')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('eq-edit')));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        expect(find.byKey(ValueKey('eq-band-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('eq-level')), findsOneWidget);
      expect(find.text('Restore default'), findsNothing);

      await tester.drag(find.byKey(const ValueKey('eq-band-0')), const Offset(0, 60)); // down = less bass
      await tester.pump();
      expect(eq.isEdited('rock'), isTrue);
      expect(eq.presetById('rock').gains.first, lessThan(5));
      expect(find.text('Rock · edited'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Restore default'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(eq.isEdited('rock'), isFalse);
      await tester.runAsync(() => eq.flush());
    });

    testWidgets('says so when the device can\'t use the equaliser', (tester) async {
      eq.reportUnavailable(true);
      await pump(tester);
      expect(find.textContaining('isn\'t available on this device'), findsOneWidget);
    });
  });
}
