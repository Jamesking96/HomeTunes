// 0.2.3: downloads from the servers (step 3 of the Servers & Downloads plan). A pretend engine
// stands in for background_downloader and pretend sources for the servers, so these check
// DownloadsModel itself: downloading a server video into the downloads folder, playing the copy,
// removing it, Keep offline (and what's skipped after removing one), the space limit, the
// sign-in being tried again once, episodes downloaded ahead and tidied once watched, what's
// saved and loaded, backups (the list of files never goes in one), and the video menu's
// Download… with its "which copy" question.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/download.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/downloads_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/screens/settings/download_settings.dart' show DownloadSettings;
import 'package:hometunes/ui/screens/downloads_screen.dart' show DownloadQueueScreen;
import 'package:hometunes/ui/widgets/download_ui.dart' show showDownloadHelp;
import 'package:hometunes/ui/widgets/video_card.dart' show showVideoMenu, VideoCard;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fake_download_engine.dart';

VideoItem episode(String id, int s, int e, {String collection = 'Silo'}) => VideoItem(
      id: 'jf:den:$id',
      path: 'jellyfin://den/$id.mkv',
      title: 'Episode $e',
      collection: collection,
      category: 'TV',
      season: s,
      episode: e,
      duration: const Duration(minutes: 50),
      sizeBytes: 1500000000,
    );

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late PlaylistsModel playlists;
  late VideoLibraryModel videos;
  late FakeEngine engine;
  late FakeSources sources;
  late DownloadsModel dl;

  final eps = [episode('ep1', 1, 1), episode('ep2', 1, 2), episode('ep3', 1, 3), episode('ep4', 2, 1)];

  Future<DownloadsModel> makeModel({bool android = false}) async {
    final m = DownloadsModel(
      storage: storage,
      library: lib,
      playlists: playlists,
      videos: videos,
      engine: engine,
      sources: sources,
      android: android,
    );
    await m.load();
    return m;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_downloads');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    playlists = PlaylistsModel(storage);
    videos = VideoLibraryModel(storage, lib);
    videos.setServerVideos('den', eps);
    engine = FakeEngine();
    sources = FakeSources();
    dl = await makeModel();
    await dl.start();
  });

  tearDown(() async {
    dl.dispose();
    engine.close();
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  VideoItem v(String id) => videos.byId('jf:den:$id')!;

  test('a server video downloads into the downloads folder and then plays from there', () async {
    expect(dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original()), 1);
    await pumpEvents();
    expect(engine.jobs, hasLength(1));
    final job = engine.jobs.single;
    expect(p.isWithin(p.join(dl.defaultFolder, 'videos'), job.path), isTrue);
    expect(job.large, isTrue);
    expect(job.headers['Authorization'], contains('secret'));
    expect(dl.isPending(v('ep1').id), isTrue);
    expect(dl.entryOf(v('ep1').id)!.quality.video, isTrue, reason: 'a video\'s original stays a video quality');

    await engine.finish(v('ep1').id, bytes: 2048);
    expect(dl.isDownloaded(v('ep1').id), isTrue);
    final e = dl.entryOf(v('ep1').id)!;
    expect(e.bytes, 2048);
    expect(File(e.file!).existsSync(), isTrue);
    expect(dl.usedBytes, 2048);
    // The video plays from the copy.
    expect(videos.downloadedCopy!(v('ep1'))!.uri, e.file);
    expect(dl.statusOf(e), '2 KB · Original file');
  });

  test('only things from a server download; one already there is left alone', () async {
    final local = VideoItem(id: VideoItem.idFor('C:/films/a.mp4'), path: 'C:/films/a.mp4', title: 'A', collection: 'A');
    expect(dl.download([DownloadItem.video(local)], const DownloadQuality.original()), 0);
    expect(dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original()), 1);
    expect(dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original()), 0);
    await pumpEvents();
    expect(engine.jobs, hasLength(1));
  });

  test('a smaller copy asks the server for that size', () async {
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.videoHeight(720));
    await pumpEvents();
    expect(sources.asked.single, 'jf:den:ep1@v720');
    // A music quality asked for a video becomes a video one.
    dl.download([DownloadItem.video(v('ep2'))], const DownloadQuality.audioBitrate(192));
    await pumpEvents();
    expect(dl.entryOf(v('ep2').id)!.quality.code, 'v720');
  });

  test('removing a download deletes its file, and stopping one cancels it', () async {
    dl.download([DownloadItem.video(v('ep1')), DownloadItem.video(v('ep2'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.finish(v('ep1').id);
    final file = dl.entryOf(v('ep1').id)!.file!;
    await dl.remove([v('ep1').id, v('ep2').id]);
    expect(File(file).existsSync(), isFalse);
    expect(dl.entries, isEmpty);
    expect(engine.cancelled, [DownloadsModel.taskIdFor(v('ep2').id)]);
    expect(videos.downloadedCopy!(v('ep1')), isNull);
  });

  test('keep offline downloads the whole collection; a download removed from it is skipped', () async {
    await dl.setKept(KeepKind.collection, 'silo', 'Silo', true, quality: const DownloadQuality.videoHeight(480));
    await pumpEvents();
    expect(dl.isKept(KeepKind.collection, 'silo'), isTrue);
    expect({for (final j in engine.jobs) j.taskId}, {for (final e in eps) DownloadsModel.taskIdFor(e.id)});
    expect(dl.entryOf(v('ep3').id)!.origin, DownloadOrigin.keep);
    expect(engine.jobs.every((j) => j.automatic), isTrue);

    await dl.remove([v('ep3').id]);
    final saved = await storage.read(DownloadsModel.fileName) as Map;
    expect((saved['skipped'] as Map)['collection:silo'], [v('ep3').id]);

    // Stop keeping it, keeping what was downloaded: it stays, as if asked for.
    await dl.setKept(KeepKind.collection, 'silo', 'Silo', false);
    expect(dl.isKept(KeepKind.collection, 'silo'), isFalse);
    expect(dl.entryOf(v('ep1').id)!.origin, DownloadOrigin.manual);

    // A season can be kept on its own.
    final c = videos.collectionNamed('Silo')!;
    await dl.setKept(KeepKind.season, DownloadsModel.seasonKey(c, VideoCollection.groupOf(v('ep4'))), 'Silo – Season 2', true);
    expect(dl.isKept(KeepKind.season, DownloadsModel.seasonKey(c, VideoCollection.groupOf(v('ep4')))), isTrue);

    // Stopping, with its downloads removed.
    await dl.setKept(KeepKind.collection, 'silo', 'Silo', true);
    await pumpEvents();
    await dl.setKept(KeepKind.collection, 'silo', 'Silo', false, removeDownloads: true);
    expect([for (final e in dl.entries) e.id], [v('ep4').id], reason: 'the kept season keeps its episode');
  });

  test('when the space for downloads is full, a download waits for room', () async {
    await dl.setLimitGb(1);
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original()); // 1.5 GB
    await pumpEvents();
    expect(engine.jobs, isEmpty);
    expect(dl.entryOf(v('ep1').id)!.state, DownloadState.noRoom);
    expect(dl.statusOf(dl.entryOf(v('ep1').id)!), contains('room'));
    await dl.setLimitGb(5);
    await pumpEvents();
    expect(engine.jobs, hasLength(1));
  });

  test('a sign-in that stopped working is tried again once, then it fails', () async {
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.fail(v('ep1').id, http: 401);
    expect(engine.jobs, hasLength(2), reason: 'asked for a new address and started again');
    await engine.fail(v('ep1').id, http: 401);
    final e = dl.entryOf(v('ep1').id)!;
    expect(e.state, DownloadState.failed);
    expect(dl.statusOf(e), contains('401'));
    await dl.retry(e.id);
    await pumpEvents();
    expect(engine.jobs, hasLength(3));
  });

  test('the server being off fails the download with a plain reason', () async {
    sources.up = false;
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original());
    await pumpEvents();
    expect(dl.entryOf(v('ep1').id)!.state, DownloadState.failed);
    expect(dl.entryOf(v('ep1').id)!.error, 'The server isn\'t on.');
  });

  test('watching a server episode downloads the next ones, which go once watched', () async {
    expect(dl.ahead, 2);
    videos.onServerVideoStarted!(v('ep1'));
    await pumpEvents();
    expect([for (final j in engine.jobs) j.taskId],
        [DownloadsModel.taskIdFor(v('ep2').id), DownloadsModel.taskIdFor(v('ep3').id)]);
    expect(dl.entryOf(v('ep2').id)!.origin, DownloadOrigin.ahead);
    await engine.finish(v('ep2').id);
    await engine.finish(v('ep3').id);
    await videos.setWatched([v('ep2').id], true);
    // Tidied a moment after the videos change.
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(dl.entryOf(v('ep2').id), isNull);
    expect(dl.isDownloaded(v('ep3').id), isTrue);

    // Off: nothing more.
    await dl.setAhead(0);
    videos.onServerVideoStarted!(v('ep3'));
    await pumpEvents();
    expect(dl.entryOf(v('ep4').id), isNull);
  });

  test('Remove downloaded videos once watched: off to start with; on, one watched since it was downloaded goes', () async {
    // ep3 was watched before it was downloaded (to watch again).
    await videos.setWatched([v('ep3').id], true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    dl.download([for (final id in ['ep1', 'ep2', 'ep3']) DownloadItem.video(v(id))], const DownloadQuality.original());
    await pumpEvents();
    for (final id in ['ep1', 'ep2', 'ep3']) {
      await engine.finish(v(id).id);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(dl.removeWatched, isFalse);
    await videos.setWatched([v('ep1').id], true);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(dl.isDownloaded(v('ep1').id), isTrue, reason: 'off: watched downloads stay');

    await dl.setRemoveWatched(true);
    await pumpEvents();
    expect(dl.entryOf(v('ep1').id), isNull, reason: 'watched since it was downloaded');
    expect(dl.isDownloaded(v('ep3').id), isTrue, reason: 'watched before it was downloaded');
    final file2 = dl.entryOf(v('ep2').id)!.file!;
    await videos.setWatched([v('ep2').id], true);
    await Future<void>.delayed(const Duration(milliseconds: 2300));
    expect(dl.entryOf(v('ep2').id), isNull);
    expect(File(file2).existsSync(), isFalse);

    // Kept with the other settings.
    final again = await makeModel();
    expect(again.removeWatched, isTrue);
    again.dispose();
  });

  testWidgets('the Download folder row picks a folder, and won\'t take one HomeTunes can\'t save in', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    final good = p.join(dir.path, 'elsewhere');
    // A "folder" inside a file can't be made.
    final blocker = File(p.join(dir.path, 'a-file'))..writeAsStringSync('x');
    final bad = p.join(blocker.path, 'inside');
    await tester.runAsync(() async {
      await DownloadSettings.chooseFolder(ctx, dl, picker: (_, _) async => bad);
    });
    await tester.pump();
    expect(dl.customFolder, isNull);
    expect(find.textContaining('can\'t save files in'), findsOneWidget);
    await tester.runAsync(() async {
      await DownloadSettings.chooseFolder(ctx, dl, picker: (_, _) async => good);
    });
    await tester.pump();
    expect(dl.customFolder, good);
    expect(Directory(good).existsSync(), isTrue);
    await tester.pump(const Duration(seconds: 10)); // the message goes
  });

  test('what was downloading carries on after a restart; a lost file downloads again', () async {
    dl.download([DownloadItem.video(v('ep1')), DownloadItem.video(v('ep2'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.finish(v('ep1').id);
    await dl.setWifiOnly(false);
    await dl.setLimitGb(20);
    final file = dl.entryOf(v('ep1').id)!.file!;
    File(file).deleteSync();

    final again = await makeModel();
    addTearDown(again.dispose);
    expect(again.entryOf(v('ep1').id)!.state, DownloadState.queued, reason: 'its file went');
    expect(again.entryOf(v('ep2').id)!.state, DownloadState.queued);
    expect(again.wifiOnly, isFalse);
    expect(again.limitGb, 20);
  });

  test('phones: Wi-Fi only goes to the engine, and kept downloads wait in the background when that\'s off', () async {
    final phone = await makeModel(android: true);
    addTearDown(phone.dispose);
    await phone.start();
    expect(engine.wifiOnly, isTrue);
    await phone.setWifiOnly(false);
    expect(engine.wifiOnly, isFalse);

    String? notice;
    phone.onNotice = (m) => notice = m;
    await phone.setKept(KeepKind.collection, 'silo', 'Silo', true);
    await pumpEvents();
    expect(notice, contains('background'), reason: 'said once that they carry on in the background');

    await phone.setBackground(false);
    await phone.appInBackground(true);
    expect(phone.waiting.every((e) => e.state == DownloadState.paused), isTrue);
    expect(phone.statusOf(phone.waiting.first), contains('background'));
    await phone.appInBackground(false);
    expect(phone.waiting.any((e) => e.state == DownloadState.paused), isFalse);
  });

  test('a backup keeps what\'s kept offline and the settings, never the list of files', () async {
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.finish(v('ep1').id);
    await dl.setKept(KeepKind.collection, 'silo', 'Silo', true);
    await dl.setLimitGb(50);
    await dl.setFolder(p.join(dir.path, 'elsewhere'));

    final backup = AppBackup.read(await AppBackup.create(storage));
    final inBackup = backup.files['downloads.json'] as Map;
    expect(inBackup.containsKey('entries'), isFalse);
    expect((inBackup['settings'] as Map).containsKey('folder'), isFalse);
    expect(inBackup['kept'], isNotEmpty);

    // Restoring on top keeps this device's downloads and folder.
    await AppBackup.restore(storage, backup, merge: false);
    final after = await storage.read(DownloadsModel.fileName) as Map;
    expect(after['entries'], hasLength(eps.length), reason: 'the downloaded one and the rest of the kept series');
    expect((after['settings'] as Map)['folder'], p.join(dir.path, 'elsewhere'));
    expect((after['settings'] as Map)['limitGb'], 50);
  });

  test('a new download folder: what\'s downloaded can move with it', () async {
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.finish(v('ep1').id);
    final to = p.join(dir.path, 'moved');
    expect(await dl.setFolder(to, move: true), 0);
    final f = dl.entryOf(v('ep1').id)!.file!;
    expect(p.isWithin(to, f), isTrue);
    expect(File(f).existsSync(), isTrue);
    dl.download([DownloadItem.video(v('ep2'))], const DownloadQuality.original());
    await pumpEvents();
    expect(p.isWithin(to, engine.jobFor(v('ep2').id).path), isTrue);
    await dl.setFolder(null);
    expect(dl.folder, dl.defaultFolder);
  });

  test('quality codes and file types', () {
    for (final q in [
      const DownloadQuality.original(),
      const DownloadQuality.original(video: true),
      const DownloadQuality.videoHeight(720),
      const DownloadQuality.audioBitrate(192),
    ]) {
      expect(DownloadQuality.parse(q.code, video: q.video), q);
    }
    expect(DownloadQuality.parse('nonsense'), const DownloadQuality.original());
    expect(DownloadsModel.extensionForMime('audio/flac'), 'flac');
    expect(DownloadsModel.extensionForMime('video/x-matroska'), 'mkv');
    expect(DownloadsModel.extensionForMime(null), 'mp3');
    expect(fileSizeText(1500000000), '1.5 GB');
  });

  testWidgets('the video menu offers Download… for a server video and asks which copy', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: videos),
          ChangeNotifierProvider<DownloadsModel?>.value(value: dl),
          ChangeNotifierProvider(create: (_) => AppNav()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showVideoMenu(context, v('ep1'), at: const Offset(20, 20)),
                child: const Text('menu'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-download')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('menu-download')));
      await tester.pumpAndSettle();
      expect(find.text('Download "Episode 1"'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quality-v720')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('quality-ok')));
      await tester.pumpAndSettle();
      await pumpEvents();
      expect(dl.entryOf(v('ep1').id)!.quality.code, 'v720');

      // Now it's downloading: Stop downloading instead.
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('menu-download')), findsNothing);
      expect(find.byKey(const ValueKey('menu-download-stop')), findsOneWidget);
      await tester.tapAt(const Offset(5, 500));
      await tester.pumpAndSettle();
    });
  });

  // 27 Oct, the user: a queue page, and "a bar at the top of each video or its collection".
  test('the queue: what\'s downloading first, then the rest in the order they\'ll go; progress together', () async {
    dl.download([DownloadItem.video(v('ep1'))], const DownloadQuality.original());
    dl.download([DownloadItem.video(v('ep2'))], const DownloadQuality.original());
    dl.download([DownloadItem.video(v('ep3'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.progress(v('ep2').id, 0.5, expected: 1000);
    expect([for (final e in dl.queue) e.id], [v('ep2').id, v('ep1').id, v('ep3').id]);
    expect(dl.progressOf([v('ep2').id]), 0.5);
    expect(dl.anyRunning([v('ep1').id, v('ep2').id]), isTrue);
    await engine.finish(v('ep1').id, bytes: 1000);
    expect(dl.progressOf([v('ep1').id]), isNull, reason: 'nothing on its way');
    expect(dl.progressOf([v('ep1').id, v('ep2').id]), 0.75, reason: 'a done one counts as whole');
    expect([for (final e in dl.queue) e.id], isNot(contains(v('ep1').id)));
    expect(dl.progressOf([v('ep4').id]), isNull);
  });

  testWidgets('a downloading video shows its bar; the queue page numbers what\'s waiting; the explainer', (tester) async {
    await tester.runAsync(() async {
      dl.download([DownloadItem.video(v('ep1')), DownloadItem.video(v('ep2'))], const DownloadQuality.original());
      await pumpEvents();
      await engine.progress(v('ep1').id, 0.4, expected: 1000);
    });
    Widget app(Widget home) => MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: videos),
            ChangeNotifierProvider<DownloadsModel?>.value(value: dl),
            ChangeNotifierProvider(create: (_) => AppNav()),
          ],
          child: MaterialApp(home: home),
        );
    await tester.pumpWidget(app(Scaffold(
      body: Row(children: [
        SizedBox(width: 300, child: VideoCard(video: v('ep1'))),
        SizedBox(width: 300, child: VideoCard(video: v('ep4'))),
      ]),
    )));
    await tester.pump();
    final bar = tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('download-progress')));
    expect(bar.value, closeTo(0.4, 0.001));
    expect(find.byKey(const ValueKey('download-progress')), findsOneWidget, reason: 'not on the one not downloading');

    await tester.pumpWidget(app(const DownloadQueueScreen()));
    await tester.pump();
    expect(find.byKey(ValueKey('queue-position:${v('ep1').id}')), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.textContaining('2 in the queue'), findsOneWidget);

    await tester.pumpWidget(app(Builder(
        builder: (context) => TextButton(onPressed: () => showDownloadHelp(context), child: const Text('help')))));
    await tester.tap(find.text('help'));
    await tester.pumpAndSettle();
    expect(find.text('Download or Keep offline?'), findsOneWidget);
    expect(find.text('Keep offline'), findsOneWidget);
    expect(find.textContaining('anything added to it later downloads by itself'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
  });
}
