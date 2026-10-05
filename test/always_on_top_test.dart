// 0.1.60: the "Always on top" pin (widgets/always_on_top_button.dart, services/window_pin.dart).
// Tests can't move a real window, so WindowPin.debugAvailable shows the button (and stops the
// call to the Windows side); what's checked is the button, the setting and that it's saved.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/window_pin.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/widgets/always_on_top_button.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_pin_'));
  tearDown(() {
    WindowPin.debugAvailable = null;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // A save may still be finishing; the system tidies its temp folder.
    }
  });

  Future<LibraryModel> pump(WidgetTester tester, {bool round = false}) async {
    final lib = LibraryModel(Storage.at(dir));
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: lib,
      child: MaterialApp(home: Scaffold(body: Center(child: AlwaysOnTopButton(round: round)))),
    ));
    return lib;
  }

  testWidgets('the pin turns "always on top" on and off', (tester) async {
    WindowPin.debugAvailable = true;
    final lib = await pump(tester);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byTooltip(AlwaysOnTopButton.tooltipFor(false)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('always-on-top')));
    await tester.pump();
    expect(lib.alwaysOnTop, isTrue);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byTooltip(AlwaysOnTopButton.tooltipFor(true)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('always-on-top')));
    await tester.pump();
    expect(lib.alwaysOnTop, isFalse);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
  });

  // Saved with the other settings, so it's put back when the app opens.
  test('it is remembered', () async {
    WindowPin.debugAvailable = true;
    final lib = LibraryModel(Storage.at(dir));
    await lib.setAlwaysOnTop(true);
    final again = LibraryModel(Storage.at(dir));
    await again.load();
    expect(again.alwaysOnTop, isTrue);
  });

  testWidgets('the round one for over a video works the same', (tester) async {
    WindowPin.debugAvailable = true;
    final lib = await pump(tester, round: true);
    expect(find.byType(Material), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('always-on-top')));
    await tester.pump();
    expect(lib.alwaysOnTop, isTrue);
  });

  testWidgets('a phone has no pin (only a computer window can stay on top)', (tester) async {
    WindowPin.debugAvailable = false;
    await pump(tester);
    expect(find.byKey(const ValueKey('always-on-top')), findsNothing);
  });
}
