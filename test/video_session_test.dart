// The video page's playback, without the page or the real engine (refactor phase 5): a
// VideoSession driving a FakeVideoEngine over a real VideoLibraryModel (a two-season series made
// of empty files).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/engine/video_engine.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/state/video_session.dart';
import 'package:path/path.dart' as p;

import 'fake_audio_engine.dart';
import 'fake_video_engine.dart';

void main() {
  late Directory dir;
  late LibraryModel lib;
  late VideoLibraryModel videos;
  late FakeAudioEngine musicEngine;
  late PlayerModel music;
  late FakeVideoEngine engine;
  VideoSession? session;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_video_session');
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    lib = LibraryModel(storage);
    videos = VideoLibraryModel(storage, lib);
    final show = p.join(dir.path, 'vids', 'TV', 'Silo');
    for (var s = 1; s <= 2; s++) {
      final season = Directory(p.join(show, 'Season $s'))..createSync(recursive: true);
      for (var e = 1; e <= 2; e++) {
        File(p.join(season.path, 'Silo S0${s}E0$e.mkv')).writeAsBytesSync([1]);
      }
    }
    await lib.addVideoFolder(p.join(dir.path, 'vids'));
    await videos.scan();
    musicEngine = FakeAudioEngine();
    music = PlayerModel(lib, engine: musicEngine);
    engine = FakeVideoEngine();
    session = null;
  });

  tearDown(() async {
    session?.dispose();
    music.dispose();
    await pumpEventQueue();
    await videos.settle();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    dir.deleteSync(recursive: true);
  });

  String idOf(String name) => videos.videos.firstWhere((v) => p.basenameWithoutExtension(v.path) == name).id;
  VideoItem item(String name) => videos.byId(idOf(name))!;

  VideoSession start(String name, {void Function(Duration)? onCarryOn}) => session = VideoSession(
        engine: engine,
        videos: videos,
        music: music,
        videoId: idOf(name),
        onCarryOn: onCarryOn,
        upNextTick: const Duration(milliseconds: 1),
        tracksSettle: Duration.zero,
        openingTimeout: const Duration(seconds: 1),
      );

  Future<void> settle() => pumpEventQueue();

  Future<void> until(bool Function() ok) async {
    for (var i = 0; i < 400 && !ok(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ok(), isTrue);
  }

  test('opens the video at its collection\'s speed', () async {
    videos.rememberSpeed(item('Silo S01E01').collection, 1.5);
    final s = start('Silo S01E01');
    await settle();
    expect(engine.calls, containsAllInOrder(['open Silo S01E01', 'rate 1.5']));
    expect(s.speed, 1.5);
    expect(s.opening, isTrue);
    engine.loaded();
    engine.moveTo(const Duration(seconds: 1));
    expect(s.opening, isFalse); // moving: it's showing
  });

  test('carries on from its place, a little earlier, and Start over goes back to the start', () async {
    final id = idOf('Silo S01E02');
    videos.savePlace(id, const Duration(minutes: 5), const Duration(minutes: 20));
    Duration? offered;
    final s = start('Silo S01E02', onCarryOn: (d) => offered = d);
    await settle();
    final expected = const Duration(minutes: 5) - PlayerModel.resumeRewind(Duration.zero);
    expect(engine.calls.first, 'open Silo S01E02 at $expected');
    expect(offered, expected);
    await s.startOver();
    expect(engine.calls.last, 'seek ${Duration.zero}');
  });

  test('the end counts as watched, then Up next opens the next episode by itself', () async {
    final s = start('Silo S01E01');
    await settle();
    engine.loaded();
    engine.finish();
    expect(videos.placeOf(idOf('Silo S01E01'))!.watched, isTrue);
    expect(s.upNext?.id, idOf('Silo S01E02'));
    expect(s.countdown, 10);
    await until(() => engine.openName == 'Silo S01E02');
    expect(s.id, idOf('Silo S01E02'));
    expect(s.shownId.value, idOf('Silo S01E02'));
    expect(s.upNext, isNull);
  });

  test('Up next can be cancelled, and the last episode has none', () async {
    final s = start('Silo S01E02');
    await settle();
    engine.loaded();
    engine.finish();
    expect(s.upNext?.id, idOf('Silo S02E01')); // on into the next season
    s.cancelUpNext();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.openName, 'Silo S01E02');
    expect(s.upNext, isNull);

    s.goTo(idOf('Silo S02E02'));
    await settle();
    engine.loaded();
    engine.finish();
    expect(s.upNext, isNull);
  });

  test('next and previous go across seasons, and each press moves on again (0.1.71)', () async {
    final s = start('Silo S01E02');
    await settle();
    s.jump(forward: true);
    await settle();
    expect(engine.openName, 'Silo S02E01');
    s.jump(forward: true); // 0.1.71: this replayed S02E01
    await settle();
    expect(engine.openName, 'Silo S02E02');
    expect(s.neighbour(s.id, forward: true), isNull);
    s.jump(forward: true); // the end: nothing happens
    await settle();
    expect(engine.openName, 'Silo S02E02');
    // (Each press settles first: two presses in the same instant can open in the wrong order, as
    // they could before phase 5; a person can't press that fast.)
    s.jump(forward: false);
    await settle();
    s.jump(forward: false);
    await settle();
    expect(engine.openName, 'Silo S01E02');
    expect(s.shownId.value, idOf('Silo S01E02'));
  });

  test('the place is saved on pause, and when the page closes', () async {
    final s = start('Silo S01E01');
    await settle();
    engine.loaded();
    engine.moveTo(const Duration(minutes: 3));
    engine.setPlaying(false);
    final place = videos.placeOf(idOf('Silo S01E01'))!;
    expect(place.position, const Duration(minutes: 3));
    expect(place.watched, isFalse);

    engine.setPlaying(true);
    engine.moveTo(const Duration(minutes: 7));
    s.dispose();
    session = null;
    await settle();
    expect(videos.placeOf(idOf('Silo S01E01'))!.position, const Duration(minutes: 7));
    expect(engine.disposed, isTrue);
  });

  test('the audio and subtitles chosen are used for the rest of the collection', () async {
    final collection = item('Silo S01E01').collection;
    videos.rememberTrackChoice(collection,
        audio: const TrackPick(language: 'jpn'), subtitles: const TrackPick(language: 'eng', title: 'Signs'));
    final s = start('Silo S01E01');
    await settle();
    engine.loaded(
      audio: const [MediaTrack('1', language: 'eng'), MediaTrack('2', language: 'jpn')],
      subtitles: const [MediaTrack('1', language: 'eng', title: 'Full'), MediaTrack('2', language: 'eng', title: 'Signs')],
    );
    await until(() => s.sid == '2');
    expect(engine.calls, containsAllInOrder(['audio 2', 'subtitles 2']));
    expect(s.aid, '2');
    expect(s.tracksSetUp, isTrue);

    // Subtitles off: remembered for the next episode too.
    await s.chooseSubtitles(null);
    expect(engine.calls.last, 'subtitles off');
    expect(s.sid, 'no');
    expect(videos.trackChoiceFor(collection).subtitles!.off, isTrue);
    s.jump(forward: true);
    await settle();
    engine.loaded(subtitles: const [MediaTrack('1', language: 'eng', title: 'Full')]);
    await until(() => s.sid == 'no');
    expect(engine.calls.last, 'subtitles off');
  });

  test('a video the engine can\'t open says so', () async {
    final s = start('Silo S01E01');
    await settle();
    engine.fail('unsupported format');
    expect(s.problem, contains('Can\'t play this video'));
    expect(s.opening, isFalse);
  });

  test('music starting pauses the video', () async {
    start('Silo S01E01');
    await settle();
    engine.loaded();
    expect(engine.isPlaying, isTrue);
    await musicEngine.playOrPause(); // the music starts
    await settle();
    expect(music.playing, isTrue);
    expect(engine.calls.last, 'pause');
    expect(engine.isPlaying, isFalse);
  });

  test('the speed chosen is used for the rest of the collection', () async {
    final s = start('Silo S01E01');
    await settle();
    await s.setSpeed(1.25);
    expect(engine.rate, 1.25);
    s.jump(forward: true);
    await settle();
    expect(engine.calls.last, 'rate 1.25');
  });
}
