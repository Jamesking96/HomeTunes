// 1 Oct: the computer's sidebar can be dragged wider / narrower and folded down to its icons
// (button, double-click on its edge, or a drag); under Liked Songs are Favourite audiobooks and
// Favourite videos.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/widgets/sidebar.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late AppNav nav;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_sidebar');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    nav = AppNav();
  });
  tearDown(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      try {
        dir.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        // try again
      }
    }
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider(create: (_) => PlaylistsModel(storage)),
      ],
      child: const MaterialApp(home: Scaffold(body: Row(children: [Sidebar(), Expanded(child: SizedBox())]))),
    ));
    await tester.pumpAndSettle();
  }

  /// Lets the settings.json write finish (real time).
  Future<void> saved(WidgetTester tester) =>
      tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));

  double width(WidgetTester tester) => tester.getSize(find.byKey(const ValueKey('sidebar'))).width;

  testWidgets('drag the edge to resize; kept between 180 and 420 and saved', (tester) async {
    await pump(tester);
    expect(width(tester), 250);
    await tester.drag(find.byKey(const ValueKey('sidebar-edge')), const Offset(80, 0));
    await tester.pumpAndSettle();
    await saved(tester);
    expect(width(tester), 330);
    expect(lib.sidebarWidth, 330);
    await tester.drag(find.byKey(const ValueKey('sidebar-edge')), const Offset(300, 0));
    await tester.pumpAndSettle();
    await saved(tester);
    expect((width(tester), lib.sidebarWidth), (420, 420));
  });

  test('the width and folding are kept in settings.json', () async {
    await lib.setSidebar(width: 999, folded: true);
    expect(lib.sidebarWidth, LibraryModel.sidebarMaxWidth);
    final again = LibraryModel(storage);
    await again.load();
    expect((again.sidebarWidth, again.sidebarFolded), (LibraryModel.sidebarMaxWidth, true));
  });

  testWidgets('fold to icons with the button, a double-click or a drag; open again', (tester) async {
    await pump(tester);
    expect(find.text('Favourite audiobooks'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-fold')));
    await tester.pumpAndSettle();
    await saved(tester);
    expect(width(tester), Sidebar.foldedWidth);
    expect(lib.sidebarFolded, isTrue);
    expect(find.text('Home'), findsNothing); // icons only
    expect(find.byTooltip('Home'), findsOneWidget);
    expect(find.byTooltip('Favourite videos'), findsOneWidget);

    // Open again with the same button; the width it had is kept.
    await tester.tap(find.byKey(const ValueKey('sidebar-fold')));
    await tester.pumpAndSettle();
    await saved(tester);
    expect(width(tester), 250);

    // Dragged very narrow: folds.
    await tester.drag(find.byKey(const ValueKey('sidebar-edge')), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await saved(tester);
    expect(lib.sidebarFolded, isTrue);
    expect(width(tester), Sidebar.foldedWidth);

    // A tap on a tab's icon still goes there.
    await tester.tap(find.byTooltip('Audiobooks'));
    expect(nav.tab, AppNav.booksTab);
  });

  testWidgets('Favourite audiobooks and Favourite videos ask their tabs for the favourites', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Favourite audiobooks'));
    expect((nav.tab, nav.viewRequest), (AppNav.booksTab, AppNav.favouriteBooksView));
    expect(nav.takeView(AppNav.favouriteBooksView), isTrue);
    expect(nav.takeView(AppNav.favouriteBooksView), isFalse); // only once

    await tester.tap(find.text('Favourite videos'));
    expect((nav.tab, nav.viewRequest), (AppNav.videosTab, AppNav.favouriteVideosView));
  });
}
