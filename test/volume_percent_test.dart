// The volume percentage bubble (0.1.65): over the volume sliders while the volume changes, gone
// a second later, and off with Settings › Playback › Show the volume percentage.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/widgets/volume_slider.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_volume_percent');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
  });
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // a settings write still finishing
      }
    }
  });

  /// A slider holding its own volume, like the players do.
  Future<ValueNotifier<double>> pump(WidgetTester tester) async {
    final volume = ValueNotifier<double>(50);
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: lib,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: ValueListenableBuilder<double>(
                valueListenable: volume,
                builder: (_, v, _) => VolumeSlider(
                  sliderKey: const ValueKey('volume-slider'),
                  value: v,
                  max: 100,
                  onChanged: (n) => volume.value = n,
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    return volume;
  }

  Finder bubble() => find.byKey(const ValueKey('volume-percent'));

  testWidgets('shows while dragged, then goes a second after letting go', (tester) async {
    final volume = await pump(tester);
    expect(bubble(), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('volume-slider'))));
    await tester.pump();
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    expect(bubble(), findsOneWidget);
    expect(find.text('${volume.value.round()}%'), findsOneWidget);
    // Above the slider.
    expect(tester.getBottomLeft(bubble()).dy,
        lessThan(tester.getCenter(find.byKey(const ValueKey('volume-slider'))).dy));

    // Held: stays.
    await tester.pump(const Duration(seconds: 2));
    expect(bubble(), findsOneWidget);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    expect(bubble(), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(bubble(), findsNothing);
  });

  testWidgets('a change from elsewhere (wheel, mute) shows it too', (tester) async {
    final volume = await pump(tester);
    volume.value = 80;
    await tester.pump();
    await tester.pump();
    expect(find.text('80%'), findsOneWidget);
    await tester.pump(VolumeSlider.showFor + const Duration(milliseconds: 50));
    expect(bubble(), findsNothing);
  });

  testWidgets('turned off in Settings: no bubble', (tester) async {
    await tester.runAsync(() => lib.setShowVolumePercent(false));
    final volume = await pump(tester);
    volume.value = 20;
    await tester.pump();
    await tester.pump();
    expect(bubble(), findsNothing);
    await tester.drag(find.byKey(const ValueKey('volume-slider')), const Offset(30, 0));
    await tester.pump();
    expect(bubble(), findsNothing);
  });

  test('on unless turned off, and kept in settings.json', () async {
    expect(lib.showVolumePercent, isTrue);
    await lib.setShowVolumePercent(false);
    final again = LibraryModel(storage);
    await again.load();
    expect(again.showVolumePercent, isFalse);
  });
}
