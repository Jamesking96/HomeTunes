// videos.json split in three (0.2.13, Profiles plan phase 0): the shared part stays in
// videos.json; the person's edits go to video_edits.json and their places to video_places.json,
// which a profile keeps in its own folder. Older files (and every backup) hold all of it in
// videos.json: it moves across when read, and backups still hold the one-file form.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/video_item.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late Storage storage;
  late LibraryModel lib;

  const v1 = 'jf:s1:a', v2 = 'jf:s1:b';
  Map<String, dynamic> oneFile() => {
        'videos': <Object>[],
        'edits': {v1: {'title': 'Pilot'}},
        'places': {v1: {'positionMs': 60000, 'watched': false, 'updatedMs': 5}},
        'favourites': ['show'],
        'speeds': {'show': 1.5},
        'seasonTitles': {'show': {'1': 'Beginnings'}},
        'foundGenres': {'show': {'genre': 'Drama', 'source': 'TVmaze', 'at': 7}},
      };

  VideoLibraryModel make(Storage personal) {
    final m = VideoLibraryModel(storage, lib, personal: personal);
    m.setServerVideos('s1', [
      const VideoItem(id: v1, path: 'jellyfin://s1/a.mkv', title: 'A', collection: 'Show', duration: Duration(minutes: 40)),
      const VideoItem(id: v2, path: 'jellyfin://s1/b.mkv', title: 'B', collection: 'Show', duration: Duration(minutes: 40)),
    ]);
    return m;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_video_split');
    storage = Storage.at(dir);
    lib = LibraryModel(storage);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('an older videos.json moves its personal parts to their own files, nothing lost', () async {
    await storage.write(VideoLibraryModel.fileName, oneFile());
    final m = make(storage);
    addTearDown(m.dispose);
    await m.load();
    expect(m.editOf(v1)?.title, 'Pilot');
    expect(m.placeOf(v1)?.position, const Duration(minutes: 1));
    expect(m.speedFor('Show'), 1.5);
    expect(m.seasonTitleOf(m.collectionNamed('Show')!, 1), 'Beginnings');
    final shared = await storage.read(VideoLibraryModel.fileName) as Map;
    expect(shared.keys.toSet(), {'videos', 'foundGenres'});
    expect((await storage.read(VideoLibraryModel.editsFileName) as Map).keys, containsAll(['edits', 'seasonTitles']));
    expect((await storage.read(VideoLibraryModel.placesFileName) as Map).keys, containsAll(['places', 'favourites', 'speeds']));
    // And it reads back the same from the three files.
    final again = make(storage);
    addTearDown(again.dispose);
    await again.load();
    expect(again.editOf(v1)?.title, 'Pilot');
    expect(again.placeOf(v1)?.position, const Duration(minutes: 1));
  });

  test('a profile keeps its edits and places in its own folder; the videos stay shared', () async {
    final mine = storage.forProfile('p1');
    final m = make(mine);
    addTearDown(m.dispose);
    await m.setEdit(v2, const VideoEdit(title: 'Mine'));
    m.savePlace(v2, const Duration(minutes: 2), const Duration(minutes: 40), paused: true);
    await m.flushPendingSaves();
    expect(File(p.join(dir.path, 'profiles', 'p1', VideoLibraryModel.editsFileName)).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'profiles', 'p1', VideoLibraryModel.placesFileName)).existsSync(), isTrue);
    expect(File(p.join(dir.path, VideoLibraryModel.editsFileName)).existsSync(), isFalse);
    // Someone else (another profile) sees no edit and no place.
    final theirs = make(storage.forProfile('p2'));
    addTearDown(theirs.dispose);
    await theirs.load();
    expect(theirs.editOf(v2), isNull);
    expect(theirs.placeOf(v2), isNull);
  });

  test('backups still hold the one-file form; restoring one moves it across again', () async {
    final m = make(storage);
    addTearDown(m.dispose);
    await m.setEdit(v1, const VideoEdit(title: 'Pilot'));
    m.savePlace(v1, const Duration(minutes: 1), const Duration(minutes: 40), paused: true);
    await m.flushPendingSaves();
    final backup = AppBackup.read(await AppBackup.create(storage));
    final vj = backup.files['videos.json'] as Map;
    expect(vj['edits'], contains(v1));
    expect(vj['places'], contains(v1));

    final other = Storage.at(Directory(p.join(dir.path, 'other'))..createSync());
    await AppBackup.restore(other, backup, merge: false);
    final lib2 = LibraryModel(other);
    final m2 = VideoLibraryModel(other, lib2);
    addTearDown(m2.dispose);
    await m2.load();
    expect(m2.editOf(v1)?.title, 'Pilot');
    expect(m2.placeOf(v1)?.position, const Duration(minutes: 1));
    expect((await other.read(VideoLibraryModel.fileName) as Map).containsKey('edits'), isFalse);
  });

  test('a merging restore keeps this device\'s own places and edits (now in their own files)', () async {
    final m = make(storage);
    addTearDown(m.dispose);
    await m.setEdit(v2, const VideoEdit(title: 'Here'));
    m.savePlace(v2, const Duration(minutes: 9), const Duration(minutes: 40), paused: true);
    await m.flushPendingSaves();
    // A backup from elsewhere, in the one-file form.
    final src = Storage.at(Directory(p.join(dir.path, 'src'))..createSync());
    await src.write('videos.json', oneFile());
    final backup = AppBackup.read(await AppBackup.create(src));
    await AppBackup.restore(storage, backup, merge: true);
    final m2 = make(storage);
    addTearDown(m2.dispose);
    await m2.load();
    expect(m2.editOf(v2)?.title, 'Here');
    expect(m2.placeOf(v2)?.position, const Duration(minutes: 9));
    expect(m2.editOf(v1)?.title, 'Pilot');
    expect(m2.placeOf(v1)?.position, const Duration(minutes: 1));
  });
}
