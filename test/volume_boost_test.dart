// 0.1.61 / 0.1.62: volume boost (models/volume_boost.dart, Settings › Playback). The players
// themselves need the real engine, so the maths, the setting and the Settings page are checked.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/volume_boost.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/playback_settings.dart';
import 'package:hometunes/ui/widgets/player_controls.dart' show VolumeControl;
import 'package:hometunes/ui/library_providers.dart';
import 'package:provider/provider.dart';

void main() {
  // 0.1.62: the setting is the top of the volume sliders; the sliders choose how loud.
  test('the sliders top out at 100, or at the boost while it is on', () {
    expect(maxVolumeFor(on: false, percent: 400), 100);
    expect(maxVolumeFor(on: true, percent: 100), 100);
    expect(maxVolumeFor(on: true, percent: 250), 250);
    expect(maxVolumeFor(on: true, percent: 900), 500); // never past 500 %
  });

  test('up to 100 is the normal volume; above it is amplified (500 % = five times as loud)', () {
    expect(engineVolume(0), 0);
    expect(engineVolume(-5), 0);
    expect(engineVolume(100), 100);
    // 0.1.83: up to 100 the sound level is (slider / 100)² (the engine cubes its own number), so
    // the low end of the slider is still audible: 50 is a quarter as loud, 20 is 1/25 (-28 dB).
    double level(double slider) => math.pow(engineVolume(slider) / 100, 3).toDouble();
    expect(level(50), closeTo(0.25, 1e-9));
    expect(level(20), closeTo(0.04, 1e-9));
    expect(level(10), closeTo(0.01, 1e-9));
    // Louder all the way up, with no jump at 100 where the boost takes over.
    for (var s = 1.0; s <= 500; s++) {
      expect(level(s), greaterThan(level(s - 1)));
    }
    expect(level(100.0001), closeTo(1, 1e-5));
    // The engine's volume is cubic: (volume / 100)³ is how loud.
    expect(math.pow(engineVolume(500) / 100, 3), closeTo(5, 1e-9));
    expect(math.pow(engineVolume(200) / 100, 3), closeTo(2, 1e-9));
    expect(engineVolume(500), lessThan(engineVolumeMax)); // under the engine's raised limit
    // And back again, for the video player whose volume lives in the engine.
    for (final v in [0.0, 35.0, 100.0, 150.0, 325.0, 500.0]) {
      expect(sliderVolume(engineVolume(v)), closeTo(v, 1e-9));
    }
    // A wheel notch or ↑ ↓ moves 5 on the slider's scale, within 0 and the top.
    expect(sliderVolume(stepEngineVolume(engineVolume(150), 5, 300)), closeTo(155, 1e-9));
    expect(sliderVolume(stepEngineVolume(engineVolume(298), 5, 300)), closeTo(300, 1e-9));
    expect(stepEngineVolume(engineVolume(98), 5, 100), 100);
    expect(stepEngineVolume(2, -5, 100), 0);
  });

  test('off and 100 % by default, remembered, and kept within 100–500 %', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_boost_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final lib = LibraryModel(Storage.at(dir));
    expect(lib.settings.playback.volumeBoost, isFalse);
    expect(lib.settings.playback.volumeBoostPercent, 100);
    expect(lib.settings.playback.maxVolume, 100);
    await lib.setVolumeBoost(on: true, percent: 350);
    final again = LibraryModel(Storage.at(dir));
    await again.load();
    expect(again.settings.playback.volumeBoost, isTrue);
    expect(again.settings.playback.volumeBoostPercent, 350);
    expect(again.settings.playback.maxVolume, 350);
    await again.setVolumeBoost(percent: 9000);
    expect(again.settings.playback.volumeBoostPercent, 500);
    await again.setVolumeBoost(percent: 10);
    expect(again.settings.playback.volumeBoostPercent, 100);
  });

  testWidgets('Settings › Playback: the switch, and the amount only while it is on', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = LibraryModel(Storage.at(Directory.systemTemp));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ...libraryProviders(lib),
        ChangeNotifierProvider(create: (_) => EqualizerModel(Storage.at(Directory.systemTemp))),
      ],
      child: const MaterialApp(home: Scaffold(body: PlaybackSettings())),
    ));
    await tester.pump();
    expect(find.text('Volume boost'), findsOneWidget);
    Slider slider() => tester.widget<Slider>(find.byKey(const ValueKey('volume-boost-amount')));
    expect(slider().onChanged, isNull); // off: the amount can't be changed
    expect(slider().value, 100);

    await tester.tap(find.byKey(const ValueKey('volume-boost-switch')));
    await tester.pump();
    expect(lib.settings.playback.volumeBoost, isTrue);
    expect(slider().onChanged, isNotNull);
    slider().onChanged!(300);
    await tester.pump();
    expect(lib.settings.playback.volumeBoostPercent, 300);
    expect(find.textContaining('goes up to 300%'), findsOneWidget);
  });

  test('the mouse wheel over a volume slider goes past 100 only with the boost', () {
    expect(VolumeControl.afterWheel(98, -100), 100);
    expect(VolumeControl.afterWheel(98, -100, max: 300), 103);
    expect(VolumeControl.afterWheel(298, -100, max: 300), 300);
  });
}
