// Refactor phase 9 (9 Oct 2026): a settings change redraws only what watches that part of the
// settings. Before, every change (a theme, the sidebar's width while dragging it, a switch in
// Settings) also told everything that watches LibraryModel, which is most of the app. Folders and
// the server still go through LibraryModel, as they change what's in the library.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/settings/settings_groups.dart' as prefs;
import 'package:hometunes/ui/library_providers.dart';
import 'package:hometunes/ui/widgets/quick_links.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late LibraryModel lib;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_watch');
    lib = LibraryModel(Storage.at(dir));
    await lib.load();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50)); // saves finish
    dir.deleteSync(recursive: true);
  });

  test('a change in online, playback, listening, video, appearance or layout leaves LibraryModel quiet', () async {
    var library = 0;
    lib.addListener(() => library++);
    final heard = <String, int>{};
    for (final (name, g) in [
      ('online', lib.settings.online),
      ('playback', lib.settings.playback),
      ('listening', lib.settings.listening),
      ('video', lib.settings.video),
      ('appearance', lib.settings.appearance),
      ('layout', lib.settings.layout),
    ]) {
      g.addListener(() => heard[name] = (heard[name] ?? 0) + 1);
    }
    await lib.setOnlineCovers(false);
    await lib.updatePlaybackSettings(gaplessPlayback: false);
    await lib.updateListeningSettings(skipBackSeconds: 15);
    await lib.updateVideoSettings(skipForwardSeconds: 20);
    await lib.setLook(textSize: 1.2);
    await lib.setSidebar(width: 300);
    expect(library, 0);
    expect(heard, {'online': 1, 'playback': 1, 'listening': 1, 'video': 1, 'appearance': 1, 'layout': 1});
    // ...and the values are kept, as before.
    final again = LibraryModel(Storage.at(dir));
    await again.load();
    expect(again.settings.online.onlineCovers, isFalse);
    expect(again.settings.playback.gaplessPlayback, isFalse);
    expect(again.settings.listening.skipBackSeconds, 15);
    expect(again.settings.video.videoSkipForwardSeconds, 20);
    expect(again.settings.appearance.textSize, 1.2);
    expect(again.settings.layout.sidebarWidth, 300);
  });

  test('folder and server changes still reach LibraryModel (they change what is in the library)', () async {
    var library = 0;
    lib.addListener(() => library++);
    lib.settings.folders.changed();
    lib.settings.server.changed();
    expect(library, 2);
  });

  testWidgets('a widget watching its group redraws; one watching only LibraryModel does not', (tester) async {
    var builds = 0;
    await tester.pumpWidget(MultiProvider(
      providers: libraryProviders(lib),
      child: MaterialApp(
        home: Scaffold(
          body: Column(children: [
            Builder(builder: (context) {
              context.watch<LibraryModel>();
              builds++;
              return const SizedBox();
            }),
            Builder(builder: (context) => Text('${context.watch<prefs.LayoutSettings>().sidebarWidth.round()}')),
            const QuickLinkButton(link: QuickLink(QuickLinkKind.album, 'abba|gold', 'Gold')),
          ]),
        ),
      ),
    ));
    expect(builds, 1);
    // (Real file saves: outside the test's pretend clock.)
    await tester.runAsync(() async {
      await lib.setSidebar(width: 280);
      await lib.addQuickLink(const QuickLink(QuickLinkKind.album, 'abba|gold', 'Gold'));
    });
    await tester.pump();
    expect(find.text('280'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_added), findsOneWidget); // the page's bookmark button follows
    expect(builds, 1);
  });
}
