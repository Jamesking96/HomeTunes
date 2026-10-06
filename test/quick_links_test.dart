// Quick links in the sidebar (0.1.64): albums, artists, audiobooks, collections and videos added
// with "Add to sidebar" sit under Liked Songs and the favourites, are kept in settings.json, and
// come off again with the same button or a right-click on the link.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/quick_link.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/widgets/quick_links.dart' show QuickLinkButton;
import 'package:hometunes/ui/widgets/sidebar.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late AppNav nav;
  late PlaylistsModel playlists;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_quick_links');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    nav = AppNav();
    playlists = PlaylistsModel(storage);
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

  const album = QuickLink(QuickLinkKind.album, 'abba|gold', 'Gold');
  const book = QuickLink(QuickLinkKind.book, 'b1', 'The Hobbit');

  test('a link survives a round trip; damaged entries are skipped', () {
    final back = QuickLink.fromJson(album.toJson())!;
    expect((back.kind, back.id, back.label), (QuickLinkKind.album, 'abba|gold', 'Gold'));
    expect(QuickLink.fromJson({'kind': 'nope', 'id': 'x'}), isNull);
    expect(QuickLink.fromJson({'kind': 'book', 'id': ''}), isNull);
    expect(QuickLink.fromJson('junk'), isNull);
    expect(QuickLink.fromJson({'kind': 'artist', 'id': 'ABBA'})!.label, 'ABBA'); // no label: the id
  });

  test('add, toggle and remove; kept in settings.json in the order added', () async {
    await lib.addQuickLink(album);
    await lib.addQuickLink(book);
    await lib.addQuickLink(album); // already there: not twice
    expect([for (final l in lib.quickLinks) l.id], ['abba|gold', 'b1']);
    expect(lib.isQuickLink(QuickLinkKind.book, 'b1'), isTrue);
    expect(lib.isQuickLink(QuickLinkKind.album, 'b1'), isFalse); // the kind counts too

    final again = LibraryModel(storage);
    await again.load();
    expect([for (final l in again.quickLinks) l.label], ['Gold', 'The Hobbit']);

    await lib.toggleQuickLink(album);
    expect([for (final l in lib.quickLinks) l.id], ['b1']);
    await lib.toggleQuickLink(album);
    await lib.removeQuickLink(QuickLinkKind.book, 'b1');
    expect([for (final l in lib.quickLinks) l.id], ['abba|gold']);
  });

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: lib),
        ChangeNotifierProvider.value(value: nav),
        ChangeNotifierProvider.value(value: playlists),
      ],
      child: MaterialApp(home: Scaffold(body: body)),
    ));
    await tester.pumpAndSettle();
  }

  Widget sidebar() => const Row(children: [Sidebar(), Expanded(child: SizedBox())]);

  testWidgets('the sidebar shows a hint, then the links; right-click takes one off', (tester) async {
    await pump(tester, sidebar());
    expect(find.byKey(const ValueKey('sidebar-links-hint')), findsOneWidget);

    await tester.runAsync(() async {
      await lib.addQuickLink(album);
      await lib.addQuickLink(book);
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sidebar-links-hint')), findsNothing);
    expect(find.text('Gold'), findsOneWidget);
    expect(find.text('The Hobbit'), findsOneWidget);
    // Below the favourites.
    expect(tester.getTopLeft(find.text('Gold')).dy,
        greaterThan(tester.getTopLeft(find.text('Favourite videos')).dy));

    await tester.tap(find.text('Gold'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from sidebar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('Gold'), findsNothing);
    expect([for (final l in lib.quickLinks) l.id], ['b1']);

    // Something no longer in the library says so, and offers to take the link off.
    await tester.tap(find.text('The Hobbit'));
    await tester.pumpAndSettle();
    expect(find.textContaining('isn\'t in your library any more'), findsOneWidget);
    await tester.tap(find.text('Remove link'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(lib.quickLinks, isEmpty);
  });

  testWidgets('a playlist: right-click it in the sidebar to add it; a rename follows', (tester) async {
    final mix = playlists.create('Road trip');
    await pump(tester, sidebar());
    Finder link() => find.byKey(ValueKey('sidebar-link:Playlist:${mix.id}'));
    expect(link(), findsNothing);

    await tester.tap(find.byKey(ValueKey('sidebar-playlist:${mix.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to sidebar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(lib.isQuickLink(QuickLinkKind.playlist, mix.id), isTrue);
    expect(link(), findsOneWidget);
    // Above the playlists list.
    expect(tester.getTopLeft(link()).dy,
        lessThan(tester.getTopLeft(find.byKey(ValueKey('sidebar-playlist:${mix.id}'))).dy));

    playlists.rename(mix, 'Summer road trip');
    await tester.pumpAndSettle();
    expect(find.descendant(of: link(), matching: find.text('Summer road trip')), findsOneWidget);

    // Clicking it opens the playlist on the Library tab.
    await tester.tap(link());
    expect(nav.tab, AppNav.libraryTab);

    // The same menu on the playlist row now takes it off.
    await tester.tap(find.byKey(ValueKey('sidebar-playlist:${mix.id}')), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from sidebar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(link(), findsNothing);
  });

  testWidgets('folded down to icons, a link is an icon with its name as the tooltip', (tester) async {
    await tester.runAsync(() => lib.addQuickLink(book));
    await tester.runAsync(() => lib.setSidebar(folded: true));
    await pump(tester, sidebar());
    expect(find.byTooltip('The Hobbit'), findsOneWidget);
    expect(find.byKey(const ValueKey('sidebar-links-hint')), findsNothing);
  });

  testWidgets('the bookmark button on a page adds and removes', (tester) async {
    await pump(tester, const Center(child: QuickLinkButton(link: album)));
    expect(find.byTooltip('Add to sidebar'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-link-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(lib.isQuickLink(QuickLinkKind.album, 'abba|gold'), isTrue);
    expect(find.byTooltip('In the sidebar (click to remove)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-link-button')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(lib.quickLinks, isEmpty);
  });
}
