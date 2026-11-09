// The server progress notice (9 Nov 2026; the user: "When servers are scanning, add a
// notification that shows the process and only goes away when closed or once the server work
// is completed").
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/server_videos.dart';
import 'package:hometunes/state/servers_model.dart';
import 'package:hometunes/ui/widgets/server_progress_notice.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

/// Stands in for ServerVideosModel: says which server is being read and how far it's got.
class _FakeReader extends ChangeNotifier implements ServerVideosModel {
  final Map<String, String> reading = {};

  void set(ServerEntry s, String? doing) {
    doing == null ? reading.remove(s.id) : reading[s.id] = doing;
    notifyListeners();
  }

  @override
  MediaKind get readsKind => MediaKind.videos;
  @override
  bool reads(ServerEntry s) => s.type == ServerType.jellyfin;
  @override
  bool isSyncing(ServerEntry s) => reading.containsKey(s.id);
  @override
  String statusFor(ServerEntry s) => (reading[s.id] ?? '').isEmpty ? 'Signed in · read just now' : reading[s.id]!;
  // '' stands for "between steps": no status line, so the usual green dot.
  @override
  bool? okFor(ServerEntry s) => reading[s.id] == '' ? true : null;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late Directory dir;
  late LibraryModel lib;
  late ServersModel servers;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_server_progress');
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    servers = ServersModel(storage, lib);
  });
  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('how far it has got, from "120 / 480"', () {
    expect(progressIn('Reading Films 120 / 480'), 0.25);
    expect(progressIn('Signing in…'), isNull);
    expect(progressIn('Getting pictures 9 / 0'), isNull);
  });

  Future<void> show(WidgetTester tester, _FakeReader reader, {bool tv = false}) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryModel>.value(value: lib),
        ChangeNotifierProvider<ServersModel?>.value(value: servers),
        ChangeNotifierProvider<ServerVideosModel?>.value(value: reader),
      ],
      child: MaterialApp(
        builder: (context, child) => Stack(fit: StackFit.expand, children: [child!, ServerProgressNotice(tv: tv)]),
        home: const Scaffold(body: Text('page')),
      ),
    ));
  }

  testWidgets('shows while servers are read, goes when they finish; closing lasts until the next read', (tester) async {
    final den = await tester.runAsync(() => servers.add(type: ServerType.jellyfin, name: 'Den', url: 'http://den:8096', uses: {MediaKind.videos}));
    final reader = _FakeReader();
    await show(tester, reader);
    expect(find.byKey(const ValueKey('server-progress')), findsNothing);

    reader.set(den!, 'Reading Films 120 / 480');
    lib.serverSync.value = 'Albums 3 / 10';
    await tester.pump();
    expect(find.text('Reading 2 servers'), findsOneWidget);
    expect(find.text('Den · Videos'), findsOneWidget);
    expect(find.text('Reading Films 120 / 480'), findsOneWidget);
    expect(find.text('Music server'), findsOneWidget);
    final bars = tester.widgetList<LinearProgressIndicator>(find.byType(LinearProgressIndicator)).map((b) => b.value);
    expect(bars, [0.3, 0.25]);

    // The music server finishes: still there for Den.
    lib.serverSync.value = null;
    await tester.pump();
    expect(find.text('Reading a server'), findsOneWidget);
    expect(find.text('Music server'), findsNothing);

    // Closed: gone, though Den is still being read.
    await tester.tap(find.byKey(const ValueKey('server-progress-close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('server-progress')), findsNothing);
    reader.set(den, 'Getting pictures 4 / 40');
    await tester.pump();
    expect(find.byKey(const ValueKey('server-progress')), findsNothing);

    // Done, then the next read: it shows again.
    reader.set(den, null);
    await tester.pump();
    reader.set(den, 'Signing in…');
    await tester.pump();
    expect(find.text('Signing in…'), findsOneWidget);
    // Between steps: "Finishing…", not the usual "Signed in · read just now".
    reader.set(den, '');
    await tester.pump();
    expect(find.text('Finishing…'), findsOneWidget);
    expect(find.textContaining('read just now'), findsNothing);
    // Finished: gone by itself.
    reader.set(den, null);
    await tester.pump();
    expect(find.byKey(const ValueKey('server-progress')), findsNothing);
    expect(find.text('page'), findsOneWidget);
  });

  testWidgets('TV: top right, never takes the remote\'s focus, goes when done', (tester) async {
    final den = await tester.runAsync(() => servers.add(type: ServerType.jellyfin, name: 'Den', url: 'http://den:8096', uses: {MediaKind.videos}));
    final reader = _FakeReader()..set(den!, 'Reading TV 1 / 2');
    await show(tester, reader, tv: true);
    expect(find.byKey(const ValueKey('server-progress')), findsOneWidget);
    expect(find.byKey(const ValueKey('server-progress-close')), findsNothing);
    expect(find.ancestor(of: find.byKey(const ValueKey('server-progress')), matching: find.byType(ExcludeFocus)), findsOneWidget);
    reader.set(den, null);
    await tester.pump();
    expect(find.byKey(const ValueKey('server-progress')), findsNothing);
  });
}
