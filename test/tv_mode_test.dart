// Tests for Settings › Appearance › TV mode (Android TV phase, 0.2.0): Automatic / On / Off, how
// it's saved in settings.json, and when the TV layout is in use.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/device_kind.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/settings/settings_groups.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_tv_mode'));
  tearDown(() async {
    DeviceKind.debugIsTv = false;
    await Future<void>.delayed(const Duration(milliseconds: 100)); // saves run in the background
    dir.deleteSync(recursive: true);
  });

  test('Automatic by default, and not written to settings.json until changed', () async {
    final storage = Storage.at(dir);
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.settings.appearance.tvMode, TvMode.automatic);
    await lib.setScaleWithWindow(false); // any save
    final saved = await storage.read('settings.json');
    expect(saved, isA<Map>());
    expect((saved as Map).containsKey('tvMode'), isFalse);
  });

  test('On and Off are saved and come back', () async {
    final storage = Storage.at(dir);
    final lib = LibraryModel(storage);
    await lib.load();
    await lib.setTvMode(TvMode.on);
    final again = LibraryModel(storage);
    await again.load();
    expect(again.settings.appearance.tvMode, TvMode.on);
    await again.setTvMode(TvMode.off);
    final third = LibraryModel(storage);
    await third.load();
    expect(third.settings.appearance.tvMode, TvMode.off);
  });

  test('an unknown saved value falls back to Automatic', () async {
    await Storage.at(dir).write('settings.json', {'tvMode': 'sideways'});
    final lib = LibraryModel(Storage.at(dir));
    await lib.load();
    expect(lib.settings.appearance.tvMode, TvMode.automatic);
  });

  test('the TV layout: Automatic follows the device, On and Off override it', () {
    final a = AppearanceSettings();
    DeviceKind.debugIsTv = false;
    expect(a.tvLayout, isFalse);
    DeviceKind.debugIsTv = true;
    expect(a.tvLayout, isTrue);
    a.tvMode = TvMode.off;
    expect(a.tvLayout, isFalse);
    DeviceKind.debugIsTv = false;
    a.tvMode = TvMode.on;
    expect(a.tvLayout, isTrue);
  });
}
