// 0.2.0: HomeTunes' own folder browser (ui/widgets/folder_browser.dart), for "Add folder" where
// there's no system folder picker (Google TV: the user, 22 Oct, "nothing happens").
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage_volumes.dart';
import 'package:hometunes/ui/widgets/folder_browser.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String own, usb;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('hometunes_folders_');
    own = p.join(temp.path, 'emulated', '0');
    usb = p.join(temp.path, 'ABCD-1234');
    for (final d in ['Music/Albums', 'Music/Singles', 'Movies', '.thumbnails']) {
      Directory(p.join(own, d)).createSync(recursive: true);
    }
    Directory(p.join(usb, 'Films')).createSync(recursive: true);
  });
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<List<StorageRoot>> twoRoots() async =>
      [StorageRoot(own, 'Internal shared storage'), StorageRoot(usb, 'SanDisk USB drive', removable: true)];

  /// A page with one button that runs [pick] and keeps what it returned.
  Future<List<String?>> page(WidgetTester tester, Future<String?> Function(BuildContext) pick) async {
    final got = <String?>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(onPressed: () async => got.add(await pick(context)), child: const Text('Add')),
        ),
      ),
    ));
    return got;
  }

  /// Taps and lets the folder listing (real files, so real time) finish, and the dialog open.
  Future<void> tapAndList(WidgetTester tester, Finder f) async {
    await tester.tap(f);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      if (i > 3 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the TV\'s storage and a USB drive, then folder by folder, then "Use this folder"', (tester) async {
    final got = await page(tester, (c) => pickFolder(c, 'Choose a video folder', inApp: true, roots: twoRoots));
    await tapAndList(tester, find.text('Add'));
    expect(find.text('Choose a video folder'), findsOneWidget);
    expect(find.text('Internal shared storage'), findsOneWidget);
    expect(find.text('SanDisk USB drive'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('folder-use'))).onPressed, isNull); // nothing chosen yet

    await tapAndList(tester, find.text('Internal shared storage'));
    expect(find.byKey(const ValueKey('folder:Movies')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder:Music')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder:.thumbnails')), findsNothing); // hidden folders left out

    await tapAndList(tester, find.byKey(const ValueKey('folder:Music')));
    expect(find.text('Internal shared storage › Music'), findsOneWidget);
    expect(find.byKey(const ValueKey('folder:Albums')), findsOneWidget);
    await tapAndList(tester, find.byKey(const ValueKey('folder-use')));
    expect(got, [p.join(own, 'Music')]);
  });

  testWidgets('Up goes back a folder, and from the top back to the list of storage', (tester) async {
    final got = await page(tester, (c) => pickFolder(c, 'Choose your music folder', inApp: true, roots: twoRoots));
    await tapAndList(tester, find.text('Add'));
    await tapAndList(tester, find.text('SanDisk USB drive'));
    await tapAndList(tester, find.byKey(const ValueKey('folder:Films')));
    expect(find.text('No folders inside this one.'), findsOneWidget);
    expect(find.text('Up to SanDisk USB drive'), findsOneWidget);
    await tapAndList(tester, find.byKey(const ValueKey('folder-up')));
    expect(find.byKey(const ValueKey('folder:Films')), findsOneWidget);
    await tapAndList(tester, find.byKey(const ValueKey('folder-up')));
    expect(find.text('Internal shared storage'), findsOneWidget);
    await tapAndList(tester, find.text('Cancel'));
    expect(got, [null]);
  });

  testWidgets('with one storage it opens straight into it', (tester) async {
    await page(tester,
        (c) => pickFolder(c, 'Choose a folder', inApp: true, roots: () async => [StorageRoot(own, 'Internal shared storage')]));
    await tapAndList(tester, find.text('Add'));
    expect(find.byKey(const ValueKey('folder:Music')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-up')), findsNothing); // nowhere further up
  });

  testWidgets('with the system picker missing, HomeTunes\' own opens instead of nothing', (tester) async {
    var asked = 0;
    Future<String?> missing(String _) async {
      asked++;
      throw PlatformException(code: 'explorer_not_found');
    }

    await page(tester, (c) => pickFolder(c, 'Choose a folder', inApp: false, systemPicker: missing, roots: twoRoots));
    await tapAndList(tester, find.text('Add'));
    expect(asked, 1);
    expect(find.text('SanDisk USB drive'), findsOneWidget);
  });

  testWidgets('where the system picker works, it\'s used', (tester) async {
    final got = await page(tester, (c) => pickFolder(c, 'Choose a folder', inApp: false, systemPicker: (_) async => 'C:/Music'));
    await tapAndList(tester, find.text('Add'));
    expect(got, ['C:/Music']);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
