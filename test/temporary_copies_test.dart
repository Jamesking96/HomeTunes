// 0.2.4: temporary copies (step 4 of the Servers & Downloads plan). With "Save a copy while
// streaming" on, a server video or song that starts playing is saved as it plays; it replays from
// here and shows a clock on its mark; it's cleared away the chosen number of days after it's
// finished (never, with "Don't delete automatically"); its own space is kept by clearing the
// oldest finished copies first; Keep makes one a download; Clear now removes them all and leaves
// downloads alone. A pretend engine and servers (fake_download_engine.dart) stand in.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/download.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/downloads_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/source_filter.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/nav.dart';
import 'package:hometunes/ui/widgets/source_mark.dart';
import 'package:hometunes/ui/widgets/video_card.dart' show showVideoMenu;
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'fake_download_engine.dart';

const _day = Duration(days: 1);

VideoItem _episode(String id, int e, {int size = 600}) => VideoItem(
      id: 'jf:den:$id',
      path: 'jellyfin://den/$id.mkv',
      title: 'Episode $e',
      collection: 'Silo',
      category: 'TV',
      season: 1,
      episode: e,
      duration: const Duration(minutes: 50),
      sizeBytes: size,
    );

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;
  late VideoLibraryModel videos;
  late FakeEngine engine;
  late DownloadsModel dl;
  var clock = DateTime(2026, 10, 27, 20).millisecondsSinceEpoch;

  Future<DownloadsModel> makeModel() async {
    final m = DownloadsModel(
      storage: storage,
      library: lib,
      playlists: PlaylistsModel(storage),
      videos: videos,
      engine: engine,
      sources: FakeSources(),
      android: false,
    )..now = () => clock;
    await m.load();
    return m;
  }

  setUp(() async {
    // A "GB" of 1000 bytes, so the space limit can be reached with tiny files.
    DownloadsModel.bytesPerGb = 1000;
    clock = DateTime(2026, 10, 27, 20).millisecondsSinceEpoch;
    dir = Directory.systemTemp.createTempSync('hometunes_temporary');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
    videos.setServerVideos('den', [_episode('ep1', 1), _episode('ep2', 2), _episode('ep3', 3)]);
    engine = FakeEngine();
    dl = await makeModel();
    await dl.start();
    await dl.setAhead(0); // only the episode playing, not the next ones
  });

  tearDown(() async {
    DownloadsModel.bytesPerGb = 1000 * 1000 * 1000;
    dl.dispose();
    engine.close();
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  VideoItem v(String id) => videos.byId('jf:den:$id')!;

  /// A server video starts playing (as the video page tells the videos model).
  Future<void> play(String id) async {
    videos.onServerVideoStarted!(v(id));
    await pumpEvents();
  }

  /// Lets the clock move on and the copies be looked over (as the hourly check does).
  Future<void> later(Duration d) async {
    clock += d.inMilliseconds;
    await dl.setTempDays(dl.tempDays);
  }

  test('off to start with: nothing is saved while streaming', () async {
    expect(dl.tempSave, isFalse);
    expect(dl.tempDays, 7);
    expect(dl.tempKeep, isFalse);
    expect(dl.tempLimitGb, 10);
    await play('ep1');
    expect(dl.entries, isEmpty);
  });

  test('on: a video saved while it streams replays from here, marked with a clock, and isn\'t a download', () async {
    await dl.setTempSave(true);
    await play('ep1');
    final e = dl.entryOf(v('ep1').id)!;
    expect(e.isTemporary, isTrue);
    expect(e.quality.isOriginal, isTrue);
    expect(engine.jobs.single.automatic, isTrue);
    await engine.finish(v('ep1').id, bytes: 600);

    expect(dl.isTemporaryCopy(v('ep1').id), isTrue);
    expect(videos.downloadedCopy!(v('ep1')), isNotNull, reason: 'it plays from here');
    expect(dl.done, isEmpty, reason: 'not one of the downloads');
    expect(dl.temporaries.single.id, v('ep1').id);
    expect(dl.usedBytes, 0);
    expect(dl.tempUsedBytes, 600);
    expect(sourceOfVideo(v('ep1')), MediaSource.temporary);
    expect(MediaSource.temporary.label, 'Downloaded', reason: 'the filter lists it under Downloaded');
    expect(markFor({MediaSource.temporary}), MediaSource.temporary);
    expect(sourceIcon(MediaSource.temporary), Icons.schedule);
    expect(markFor({MediaSource.temporary, MediaSource.downloaded}), MediaSource.downloaded);
    expect(dl.statusOf(dl.entryOf(v('ep1').id)!), contains('cleared 7 days after it\'s finished'));

    // Playing it again doesn't save it twice.
    await play('ep1');
    expect(engine.jobs, hasLength(1));
  });

  test('cleared the chosen days after it\'s watched; a part-watched one stays', () async {
    await dl.setTempSave(true);
    await play('ep1');
    await engine.finish(v('ep1').id);
    await play('ep2');
    await engine.finish(v('ep2').id);
    await videos.setWatched([v('ep1').id], true);
    await later(Duration.zero);
    expect(dl.entryOf(v('ep1').id)!.finishedMs, clock);
    expect(dl.statusOf(dl.entryOf(v('ep1').id)!), contains('cleared in 7 days'));
    final file = dl.entryOf(v('ep1').id)!.file!;

    await later(_day * 6);
    expect(dl.entryOf(v('ep1').id), isNotNull);
    await later(_day * 1);
    expect(dl.entryOf(v('ep1').id), isNull);
    expect(File(file).existsSync(), isFalse);
    expect(dl.entryOf(v('ep2').id), isNotNull, reason: 'never finished');

    // Fewer days: counted from when it was finished.
    await videos.setWatched([v('ep2').id], true);
    await later(Duration.zero);
    clock += (_day * 2).inMilliseconds;
    await dl.setTempDays(1);
    expect(dl.entryOf(v('ep2').id), isNull);
  });

  test('marked not watched again, a copy isn\'t finished any more', () async {
    await dl.setTempSave(true);
    await play('ep1');
    await engine.finish(v('ep1').id);
    await videos.setWatched([v('ep1').id], true);
    await later(Duration.zero);
    await videos.setWatched([v('ep1').id], false);
    await later(_day * 10);
    expect(dl.entryOf(v('ep1').id)!.finishedMs, isNull);
  });

  test('Don\'t delete automatically: nothing goes, and once the space is full nothing more is saved', () async {
    await dl.setTempSave(true);
    await dl.setTempKeep(true);
    await dl.setTempLimitGb(1); // 1000 bytes here
    await play('ep1');
    await engine.finish(v('ep1').id, bytes: 600);
    await videos.setWatched([v('ep1').id], true);
    await later(_day * 60);
    expect(dl.entryOf(v('ep1').id), isNotNull);
    expect(dl.statusOf(dl.entryOf(v('ep1').id)!), contains('kept until you clear it'));
    await play('ep2'); // 600 more won't fit
    expect(dl.entryOf(v('ep2').id), isNull);
    expect(engine.jobs, hasLength(1));
  });

  test('when the space is full, the oldest finished copy goes first, then part-played ones', () async {
    await dl.setTempSave(true);
    await dl.setTempLimitGb(1); // 1000 bytes here
    await play('ep1');
    await engine.finish(v('ep1').id, bytes: 400);
    await play('ep2');
    await engine.finish(v('ep2').id, bytes: 400);
    await videos.setWatched([v('ep2').id], true); // ep2 finished, ep1 only part-watched
    await later(Duration.zero);

    await play('ep3'); // 600: room is made by clearing ep2 (finished) first
    expect(dl.entryOf(v('ep2').id), isNull);
    expect(dl.entryOf(v('ep1').id), isNotNull);
    expect(engine.jobFor(v('ep3').id), isNotNull);
  });

  test('Keep makes a temporary copy a download; Keep offline does too', () async {
    await dl.setTempSave(true);
    await play('ep1');
    await engine.finish(v('ep1').id);
    await play('ep2');
    await engine.finish(v('ep2').id);
    await dl.keepCopies([v('ep1').id]);
    expect(dl.entryOf(v('ep1').id)!.origin, DownloadOrigin.manual);
    expect(dl.done.single.id, v('ep1').id);
    await videos.setWatched([v('ep1').id], true);
    await later(_day * 60);
    expect(dl.entryOf(v('ep1').id), isNotNull, reason: 'downloads are never cleared');

    await dl.setKept(KeepKind.collection, 'silo', 'Silo', true);
    expect(dl.entryOf(v('ep2').id)!.origin, DownloadOrigin.keep);
  });

  test('Clear now removes every temporary copy and leaves downloads', () async {
    dl.download([DownloadItem.video(v('ep3'))], const DownloadQuality.original());
    await pumpEvents();
    await engine.finish(v('ep3').id);
    await dl.setTempSave(true);
    await play('ep1');
    await engine.finish(v('ep1').id);
    await play('ep2'); // still being saved
    final file = dl.entryOf(v('ep1').id)!.file!;
    await dl.clearTemporary();
    expect(dl.temporaries, isEmpty);
    expect(dl.entryOf(v('ep2').id), isNull);
    expect(engine.cancelled, contains(DownloadsModel.taskIdFor(v('ep2').id)));
    expect(File(file).existsSync(), isFalse);
    expect(dl.isDownloaded(v('ep3').id), isTrue);
  });

  test('a song: saved when it starts, finished once played through', () async {
    DownloadsModel.bytesPerGb = 1000 * 1000 * 1000; // a song's size is guessed from its length
    await dl.setTempSave(true);
    final song = Track(
      id: 'server:s1',
      source: TrackSource.server,
      title: 'Paper Lanterns',
      artist: 'Harbour Lights',
      album: 'Paper Lanterns',
      albumArtist: 'Harbour Lights',
      duration: const Duration(minutes: 3),
      remoteId: 's1',
    );
    dl.startedPlaying(song);
    await pumpEvents();
    expect(dl.entryOf('server:s1')!.isTemporary, isTrue);
    await engine.finish('server:s1');
    dl.playedThrough(song);
    expect(dl.entryOf('server:s1')!.finishedMs, clock);
    await later(_day * 7);
    expect(dl.entryOf('server:s1'), isNull);
    // Your own songs are never copied.
    dl.startedPlaying(Track(id: 'local:/m/a.mp3', source: TrackSource.local, title: 'A', artist: 'X', album: 'Y', albumArtist: 'X'));
    expect(dl.entryOf('local:/m/a.mp3'), isNull);
  });

  test('a copy that couldn\'t be saved is let go; a lost file is forgotten, not fetched again', () async {
    await dl.setTempSave(true);
    await play('ep1');
    await engine.fail(v('ep1').id, http: 500);
    expect(dl.entryOf(v('ep1').id), isNull, reason: 'no problem left on the Downloads page');

    await play('ep2');
    await engine.finish(v('ep2').id);
    File(dl.entryOf(v('ep2').id)!.file!).deleteSync();
    final again = await makeModel();
    addTearDown(again.dispose);
    expect(again.entryOf(v('ep2').id), isNull);
    expect(again.tempSave, isTrue, reason: 'the settings are saved');
  });

  testWidgets('a temporary copy\'s menu has Keep this copy and Remove temporary copy', (tester) async {
    await tester.runAsync(() async {
      await dl.setTempSave(true);
      await play('ep1');
      await engine.finish(v('ep1').id);
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
      expect(find.text('Keep this copy'), findsOneWidget);
      expect(find.text('Remove temporary copy'), findsOneWidget);
      expect(find.text('Download…'), findsNothing);
      await tester.tap(find.text('Keep this copy'));
      await tester.pumpAndSettle();
      await pumpEvents();
      expect(dl.entryOf(v('ep1').id)!.isTemporary, isFalse);
    });
  });
}
