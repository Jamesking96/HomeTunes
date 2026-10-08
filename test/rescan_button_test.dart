// 0.1.73: the quick Rescan button on Your Library and Audiobooks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/ui/widgets/rescan_button.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_rescan_button'));
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<LibraryModel> pump(WidgetTester tester, {List<String> folders = const []}) async {
    final lib = LibraryModel(Storage.at(dir))..folders = [...folders];
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: lib,
      child: MaterialApp(
        home: Scaffold(appBar: AppBar(actions: const [RescanButton(tooltip: 'Rescan music folders')])),
      ),
    ));
    return lib;
  }

  IconButton button(WidgetTester tester) => tester.widget<IconButton>(find.byKey(const ValueKey('rescan-library')));

  testWidgets('no folders yet: greyed out, and says to add some', (tester) async {
    await pump(tester);
    expect(button(tester).onPressed, isNull);
    expect(button(tester).tooltip, 'Add folders in Settings first');
  });

  testWidgets('with folders: ready to rescan; a spinner while it works', (tester) async {
    final lib = await pump(tester, folders: [dir.path]);
    expect(button(tester).onPressed, isNotNull);
    expect(button(tester).tooltip, 'Rescan music folders');

    lib.busy = true;
    lib.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('rescan-library')), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    lib.busy = false;
    lib.notifyListeners();
    await tester.pump();
    expect(find.byKey(const ValueKey('rescan-library')), findsOneWidget);
  });
}
