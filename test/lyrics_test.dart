import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/lyrics.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/local_lyrics.dart';
import 'package:hometunes/services/lrclib_client.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/services/subsonic_client.dart';
import 'package:hometunes/services/tag_writer.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/lyrics_model.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

Track song(String path, {int seconds = 200}) => Track(
      id: 'local:$path',
      source: TrackSource.local,
      title: 'Kettle Song',
      artist: 'The Mornings',
      album: 'Quiet Street',
      albumArtist: 'The Mornings',
      duration: Duration(seconds: seconds),
      path: path,
    );

void main() {
  const s = Duration(seconds: 1);

  group('Reading lyrics', () {
    test('plain lyrics keep their lines and verse gaps, trimmed at the ends', () {
      final l = Lyrics('\n\nLine one\nLine two\n\nLine three  \n\n', LyricsSource.file);
      expect(l.timed, isFalse);
      expect(l.lines.map((x) => x.text), ['Line one', 'Line two', '', 'Line three']);
    });

    test('LRC: times, tags dropped, several times per line, sorted', () {
      final l = Lyrics(
        '[ar:Someone]\n[ti:Song]\n[00:12.50]Second\n[00:05.00][00:20.1]Chorus\n[00:02]First\nnot timed',
        LyricsSource.lrcFile,
      );
      expect(l.timed, isTrue);
      expect(l.lines, [
        const LyricLine('First', Duration(seconds: 2)),
        const LyricLine('Chorus', Duration(seconds: 5)),
        const LyricLine('Second', Duration(milliseconds: 12500)),
        const LyricLine('Chorus', Duration(milliseconds: 20100)),
      ]);
    });

    test('LRC offset and word timings', () {
      final l = Lyrics('[offset:+500]\n[00:10.00]<00:10.00>Hello <00:10.40>there', LyricsSource.lrclib);
      expect(l.lines.single, const LyricLine('Hello there', Duration(milliseconds: 9500)));
    });

    test('which line is being sung', () {
      final l = Lyrics('[00:01.00]a\n[00:03.00]b\n[00:05.00]c', LyricsSource.file);
      expect(l.lineAt(Duration.zero), -1);
      expect(l.lineAt(s * 1), 0);
      expect(l.lineAt(s * 4), 1);
      expect(l.lineAt(s * 60), 2);
    });

    test('a [Chorus] marker alone does not make lyrics timed', () {
      expect(Lyrics('[Chorus]\nLa la', LyricsSource.file).timed, isFalse);
    });
  });

  group('LRCLIB', () {
    LrclibMatch m(int id, {int secs = 200, String? synced, String? plain, String album = ''}) => LrclibMatch(
          id: id,
          title: 'Kettle Song',
          artist: 'The Mornings',
          album: album,
          duration: Duration(seconds: secs),
          syncedLyrics: synced,
          plainLyrics: plain,
        );

    test('ranking: has lyrics, then close length, then timed, then same album', () {
      final ranked = LrclibClient.rank([
        m(1, secs: 260, synced: 'x'),
        m(2, plain: 'x'),
        m(3), // nothing
        m(4, synced: 'x'),
        m(5, synced: 'x', album: 'Quiet Street', secs: 202),
      ], duration: s * 200, album: 'Quiet Street');
      expect(ranked.map((x) => x.id), [5, 4, 2, 1, 3]);
    });

    test('names match ignoring case, punctuation and featured artists', () {
      expect(LrclibClient.sameText('Kettle Song (feat. Someone)', 'kettle song'), isTrue);
      expect(LrclibClient.sameText('The Mornings', 'Mornings, The'), isFalse);
      expect(LrclibClient.sameText('', 'x'), isFalse);
    });

    test('find: exact lookup first, else a search checked against the length', () async {
      final asked = <String>[];
      final client = LrclibClient(httpClient: MockClient((req) async {
        asked.add(req.url.path);
        expect(req.headers['User-Agent'], contains('HomeTunes'));
        if (req.url.path == '/api/get') return http.Response('{"code":404}', 404);
        return http.Response(
          jsonEncode([
            {'id': 1, 'trackName': 'Kettle Song', 'artistName': 'The Mornings', 'duration': 320, 'syncedLyrics': '[00:01.00]long'},
            {'id': 2, 'trackName': 'Kettle Song', 'artistName': 'The Mornings', 'duration': 201.5, 'plainLyrics': 'right one'},
          ]),
          200,
        );
      }));
      final found = await client.find(title: 'Kettle Song', artist: 'The Mornings', duration: s * 200);
      expect(asked, ['/api/get', '/api/search']);
      expect(found?.id, 2);
      expect(found?.bestLyrics, 'right one');
    });
  });

  test('server lyrics: timed OpenSubsonic lyrics become LRC (offset applied)', () {
    final text = SubsonicClient.structuredLyricsToText({
      'structuredLyrics': [
        {'synced': false, 'line': [{'value': 'plain'}]},
        {
          'synced': true,
          'offset': 100,
          'line': [
            {'start': 1100, 'value': 'one'},
            {'start': 62000, 'value': 'two'},
          ],
        },
      ],
    });
    expect(text, '[00:01.00]one\n[01:01.90]two');
  });

  group('Where lyrics come from', () {
    late Directory dir;
    late LibraryModel library;
    late LyricsModel lyrics;
    late Map<String, LocalLyrics> local;
    late int lrclibCalls;
    String? lrclibAnswer;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_lyrics');
      final storage = Storage.at(dir);
      final musicFile = File(p.join(dir.path, 'music', 'kettle.mp3'))..createSync(recursive: true);
      await storage.write('library.json', {
        'local': [song(musicFile.path).toJson()],
      });
      library = LibraryModel(storage);
      await library.load();
      local = {};
      lrclibCalls = 0;
      lrclibAnswer = null;
      lyrics = LyricsModel(
        library,
        storage,
        readLocal: (path) async => local[path] ?? (tags: null, lrc: null),
        makeLrclib: () => LrclibClient(httpClient: MockClient((req) async {
          lrclibCalls++;
          if (lrclibAnswer == null) return http.Response('[]', req.url.path == '/api/get' ? 404 : 200);
          return http.Response(
            jsonEncode({
              'id': 9,
              'trackName': 'Kettle Song',
              'artistName': 'The Mornings',
              'duration': 200,
              'syncedLyrics': lrclibAnswer,
            }),
            200,
          );
        })),
      );
      await lyrics.load();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      dir.deleteSync(recursive: true);
    });

    Track t() => library.tracks.single;

    test('timed .lrc file beats plain tags; tags beat nothing', () async {
      local[t().path!] = (tags: 'plain words', lrc: '[00:01.00]timed words');
      expect((await lyrics.lyricsFor(t()))!.source, LyricsSource.lrcFile);
      local[t().path!] = (tags: 'plain words', lrc: null);
      await lyrics.forget(t());
      final l = await lyrics.lyricsFor(t());
      expect(l!.source, LyricsSource.file);
      expect(lrclibCalls, 0);
    });

    test('found online once, then saved (works offline, survives a restart)', () async {
      lrclibAnswer = '[00:01.00]from the web';
      final first = await lyrics.lyricsFor(t());
      expect(first!.source, LyricsSource.lrclib);
      expect(lrclibCalls, 1);

      final again = LyricsModel(library, Storage.at(dir), makeLrclib: () => throw StateError('no network'),
          readLocal: (_) async => (tags: null, lrc: null));
      await again.load();
      expect((await again.lyricsFor(t()))!.lines.single.text, 'from the web');
    });

    test('nothing online: not asked again for a while', () async {
      expect(await lyrics.lyricsFor(t()), isNull);
      final calls = lrclibCalls;
      expect(await lyrics.lyricsFor(t()), isNull);
      expect(lrclibCalls, calls);
      lyrics.now = () => DateTime.now().add(LyricsModel.retryAfter + const Duration(days: 1));
      await lyrics.lyricsFor(t());
      expect(lrclibCalls, greaterThan(calls));
    });

    test('switched off in Settings: nothing is looked up', () async {
      await library.setOnlineLyrics(false);
      lrclibAnswer = '[00:01.00]from the web';
      expect(await lyrics.lyricsFor(t()), isNull);
      expect(lrclibCalls, 0);
    });

    test('your lyrics win, can be hidden, and removing them brings the file\'s back', () async {
      local[t().path!] = (tags: 'file words', lrc: null);
      await lyrics.setYours(t(), 'my words');
      expect((await lyrics.lyricsFor(t()))!.source, LyricsSource.yours);
      expect(library.isEdited(t().id), isTrue);

      await lyrics.hide(t());
      expect(lyrics.isHidden(t()), isTrue);
      expect(await lyrics.lyricsFor(t()), isNull);

      await lyrics.removeYours(t());
      expect(library.isEdited(t().id), isFalse);
      expect((await lyrics.lyricsFor(t()))!.lines.single.text, 'file words');
    });

    test('editing details or resetting them keeps your lyrics', () async {
      await lyrics.setYours(t(), 'my words');
      await library.setEdit(t().id, const TrackEdit(title: 'New title'));
      expect(library.lyricsEdit(t().id), 'my words');
      expect(t().title, 'New title');
      await library.resetEdits([t().id]);
      expect(t().title, 'Kettle Song');
      expect(library.lyricsEdit(t().id), 'my words');
    });

    test('backups carry your lyrics and the ones found online', () async {
      lrclibAnswer = '[00:01.00]from the web';
      await lyrics.lyricsFor(t());
      await lyrics.setYours(t(), 'my words');
      final bytes = await AppBackup.create(Storage.at(dir));
      final files = (jsonDecode(utf8.decode(gzip.decode(bytes))) as Map)['files'] as Map;
      expect(jsonEncode(files['edits.json']), contains('my words'));
      expect(jsonEncode(files['lyrics.json']), contains('from the web'));
    });
  });

  test('a .lrc file next to the song is found whatever the case of its extension', () {
    final dir = Directory.systemTemp.createTempSync('hometunes_lrc');
    addTearDown(() => dir.deleteSync(recursive: true));
    final songPath = p.join(dir.path, 'A Song.flac');
    File(songPath).writeAsStringSync('');
    File(p.join(dir.path, 'A Song.LRC')).writeAsStringSync('﻿[00:01.00]hi');
    final r = readLocalLyricsNow(songPath);
    expect(r.lrc, '[00:01.00]hi');
    expect(r.tags, isNull);
  });

  group('Saving edits into files keeps what HomeTunes doesn\'t change', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('hometunes_tags'));
    tearDown(() => dir.deleteSync(recursive: true));

    File copy(String name) =>
        File(p.join('test', 'fixtures', name)).copySync(p.join(dir.path, name));

    // Text frames may be UTF-8, Latin-1 or UTF-16 (little endian).
    bool has(File f, String text) => _has(f, utf8.encode(text)) || _has(f, [for (final c in text.codeUnits) ...[c, 0]]);

    bool _has(File f, List<int> needle) {
      final bytes = f.readAsBytesSync();
      outer:
      for (var i = 0; i + needle.length <= bytes.length; i++) {
        for (var j = 0; j < needle.length; j++) {
          if (bytes[i + j] != needle[j]) continue outer;
        }
        return true;
      }
      return false;
    }

    for (final name in ['tagged.mp3', 'tagged_v24.mp3', 'tagged.flac', 'tagged.m4a']) {
      test('$name: lyrics read, new title written, ReplayGain/comment/composer kept', () async {
        final f = copy(name);
        expect(readLocalLyricsNow(f.path).tags, '[00:00.50]first line\n[00:01.00]second line');

        final r = await writeTagsToFile(f.path, const TrackEdit(title: 'Renamed'));
        expect(r.ok, isTrue, reason: r.error);
        final m = readMetadata(f, getImage: false);
        expect(m.title, 'Renamed');
        expect(m.lyrics, '[00:00.50]first line\n[00:01.00]second line');
        expect(m.discNumber, 2);
        expect(has(f, 'kept comment'), isTrue);
        expect(has(f, 'Some Composer'), isTrue);
        expect(has(f, '-6.50 dB'), isTrue);
        expect(has(f, 'Album Person'), isTrue);
        // To check the written files with another tag reader: set HT_KEEP_TAGGED to a folder.
        final keep = Platform.environment['HT_KEEP_TAGGED'];
        if (keep != null) f.copySync(p.join(keep, 'renamed_$name'));
      });

      test('$name: new lyrics are written into the file', () async {
        final f = copy(name);
        final r = await writeTagsToFile(f.path, const TrackEdit(lyrics: '[00:02.00]new words\nsecond'));
        expect(r.ok, isTrue, reason: r.error);
        expect(r.leftover.isEmpty, isTrue);
        expect(readLocalLyricsNow(f.path).tags, '[00:02.00]new words\nsecond');
        expect(has(f, '-6.50 dB'), isTrue);
      });
    }

    test('WAV files can\'t hold lyrics: they stay as a HomeTunes edit', () {
      expect(TagSupport.forPath('a.wav').leftover(const TrackEdit(lyrics: 'x', title: 'y')).lyrics, 'x');
      expect(TagSupport.forPath('a.flac').leftover(const TrackEdit(lyrics: 'x')).isEmpty, isTrue);
    });
  });
}
