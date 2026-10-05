// 0.1.61: volume boost (models/volume_boost.dart, Settings › Playback).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/volume_boost.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/screens/settings/playback_settings.dart';
import 'package:provider/provider.dart';

void main() {
  test('how loud: off is normal, 500 % is five times', () {
    expect(boostFactor(on: false, percent: 400), 1.0);
    expect(boostFactor(on: true, percent: 100), 1.0);
    expect(boostFactor(on: true, percent: 250), 2.5);
    expect(boostFactor(on: true, percent: 900), 5.0); // never past 500 %
    // The engine's volume is cubic, so its volume goes up by the cube root…
    final scale = boostVolumeScale(5);
    expect(math.pow(scale, 3), closeTo(5, 1e-9));
    expect(100 * scale, lessThan(engineVolumeMax)); // …and stays under its raised limit.
    expect(boostVolumeScale(1), 1.0);
    // Videos get it in decibels.
    expect(boostDb(5), closeTo(13.98, 0.01));
    expect(boostDb(2), closeTo(6.02, 0.01));
    expect(boostDb(1), 0);
  });

  test('off and 100 % by default, remembered, and kept within 100–500 %', () async {
    final dir = Directory.systemTemp.createTempSync('hometunes_boost_');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final lib = LibraryModel(Storage.at(dir));
    expect(lib.volumeBoost, isFalse);
    expect(lib.volumeBoostPercent, 100);
    await lib.setVolumeBoost(on: true, percent: 350);
    final again = LibraryModel(Storage.at(dir));
    await again.load();
    expect(again.volumeBoost, isTrue);
    expect(again.volumeBoostPercent, 350);
    await again.setVolumeBoost(percent: 9000);
    expect(again.volumeBoostPercent, 500);
    await again.setVolumeBoost(percent: 10);
    expect(again.volumeBoostPercent, 100);
  });

  testWidgets('Settings › Playback: the switch, and the amount only while it is on', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final lib = LibraryModel(Storage.at(Directory.systemTemp));
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
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
    expect(lib.volumeBoost, isTrue);
    expect(slider().onChanged, isNotNull);
    slider().onChanged!(300);
    await tester.pump();
    expect(lib.volumeBoostPercent, 300);
    expect(find.textContaining('300% of their normal loudness'), findsOneWidget);
  });
}
