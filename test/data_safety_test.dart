// Tests that damaged or hand-edited data files never stop HomeTunes starting and are never
// silently thrown away (release 0.1.14, fixes 2 and 16 in the code review plan). Each model
// reads what it can, falls back to defaults for the rest, keeps a `.corrupt-<date>` copy of
// the file before its next save replaces it, and reports the problem through Storage.problems
// (shown in the status strip).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/playlists_model.dart';

void main() {
  late Directory dir;
  late Storage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_safety');
    storage = Storage.at(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  void put(String name, Object json) => File('${dir.path}/$name').writeAsStringSync(jsonEncode(json));
  List<String> copiesOf(String base) => [
        for (final f in dir.listSync())
          if (f.path.contains('$base.corrupt-')) f.path,
      ];

  test('settings with a wrong type keep every other setting', () async {
    put('settings.json', {
      'folders': ['C:/Music', 42],
      'skipBackSeconds': 'fifteen',
      'sleepFadeSeconds': 5,
      'skipForwardSeconds': 45.0,
      'rewindOnResume': false,
      'server': {'url': 7},
    });
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.folders, ['C:/Music']);
    expect(lib.skipBackSeconds, 15); // the default
    expect(lib.skipForwardSeconds, 45);
    expect(lib.sleepFadeSeconds, 5);
    expect(lib.rewindOnResume, isFalse);
    expect(copiesOf('settings'), hasLength(1));
    expect(lib.dataProblem, contains('settings'));
  });

  test('a settings file that is the wrong shape loads defaults and is kept', () async {
    put('settings.json', ['not', 'a', 'map']);
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.folders, isEmpty);
    expect(copiesOf('settings'), hasLength(1));
  });

  test('good settings files are left alone and report nothing', () async {
    put('settings.json', {'folders': ['C:/Music'], 'skipBackSeconds': 10});
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.skipBackSeconds, 10);
    expect(copiesOf('settings'), isEmpty);
    expect(lib.dataProblem, isNull);
  });

  test('one damaged edit and one damaged track are skipped, the rest are kept', () async {
    put('edits.json', {
      'local:/a.mp3': {'title': 'Good'},
      'local:/b.mp3': {'title': 99},
    });
    put('library.json', {
      'local': [
        {'id': 'local:/a.mp3', 'source': 'local', 'title': 'A', 'artist': 'X', 'album': 'Y', 'albumArtist': 'X', 'path': '/a.mp3', 'durationMs': 1000},
        'not a track',
      ],
    });
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.isEdited('local:/a.mp3'), isTrue);
    expect(lib.isEdited('local:/b.mp3'), isFalse);
    expect(copiesOf('edits'), hasLength(1));
    expect(copiesOf('library'), hasLength(1));
  });

  test('one damaged playlist is skipped and the file is kept', () async {
    put('playlists.json', {
      'playlists': [
        {'id': 'p1', 'name': 'Road trip', 'trackIds': ['local:/a.mp3']},
        {'id': 'p2', 'name': 5, 'trackIds': []},
      ],
      'liked': ['local:/a.mp3', 3],
    });
    final pl = PlaylistsModel(storage);
    await pl.load();
    expect(pl.playlists.map((p) => p.name), ['Road trip']);
    expect(pl.liked, ['local:/a.mp3']);
    expect(copiesOf('playlists'), hasLength(1));
  });

  test('listening places, bookmarks and the equaliser survive the wrong shape', () async {
    put('listening.json', ['wrong']);
    put('bookmarks.json', {'bookmarks': 'wrong'});
    put('equalizer.json', {'enabled': 'yes', 'custom': [1, 2]});
    final listening = ListeningModel(storage);
    final bookmarks = BookmarksModel(storage);
    final eq = EqualizerModel(storage);
    await listening.load();
    await bookmarks.load();
    await eq.load();
    expect(eq.enabled, isFalse);
    expect(copiesOf('listening'), hasLength(1));
    expect(copiesOf('bookmarks'), hasLength(1));
    expect(copiesOf('equalizer'), hasLength(1));
    expect(storage.problems, hasLength(3));
  });

  test('dismissing the message clears the data problems', () async {
    put('settings.json', ['wrong']);
    final lib = LibraryModel(storage);
    await lib.load();
    expect(lib.dataProblem, isNotNull);
    lib.clearError();
    expect(lib.dataProblem, isNull);
  });
}
