// Phase 1 of the modular refactor (8 Oct 2026): four small fixes found in the code review.
// - The video player's equaliser leaves out bands at or above half the sound's sample rate, as
//   the music player does (a video with 22 kHz sound used to have no equaliser at all: the engine
//   rejected the whole filter over the 16 kHz band; checked in tool/bench/engine_test.dart).
// - A song's own lyrics (tags / .lrc) are only read again when the songs were rebuilt, not on
//   every settings change.
// - Forgetting missing songs also forgets the lyrics found online for them.
// - The video folder that owns a file is the deepest one, counted like the music folders.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/eq_preset.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/lyrics_model.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:hometunes/ui/screens/video_player_screen.dart' show videoEqualizerSettings;
import 'package:path/path.dart' as p;

void main() {
  group('Video equaliser', () {
    final rock = builtInEqPreset('rock');

    test('bands at or above half the sample rate are left out', () {
      expect(videoEqualizerSettings(rock, sampleRate: 22050).filter, isNot(contains('f=16000')));
      expect(videoEqualizerSettings(rock, sampleRate: 22050).filter, contains('f=8000'));
      expect(videoEqualizerSettings(rock, sampleRate: 48000).filter, contains('f=16000'));
    });

    test('the same filter text as the music player for the same rate', () {
      for (final rate in [22050, 32000, 44100, 48000]) {
        expect(videoEqualizerSettings(rock, sampleRate: rate).filter, eqFilter(rock, sampleRate: rate));
      }
    });

    test('off: no filter and no level change', () {
      final off = videoEqualizerSettings(null, sampleRate: 48000);
      expect(off.filter, eqFilter(null));
      expect(off.level, '0.0');
    });
  });

  group('With a library', () {
    late Directory dir;
    late Storage storage;
    late LibraryModel library;
    late String songPath;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('hometunes_p1');
      storage = Storage.at(dir);
      songPath = p.join(dir.path, 'music', 'kettle.mp3');
      File(songPath).createSync(recursive: true);
      await storage.write('library.json', {
        'local': [
          {'id': 'local:$songPath', 'source': 'local', 'title': 'Kettle Song', 'artist': 'The Mornings', 'album': 'Breakfast', 'albumArtist': 'The Mornings', 'path': songPath, 'durationMs': 200000},
        ],
      });
      library = LibraryModel(storage);
      await library.load();
    });
    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100)); // saves finish in the background
      dir.deleteSync(recursive: true);
    });

    test('a song\'s own lyrics are read again after a rebuild, not after a settings change', () async {
      var reads = 0;
      final lyrics = LyricsModel(library, storage, readLocal: (path) async {
        reads++;
        return (tags: 'la la', lrc: null);
      });
      await lyrics.load();
      await lyrics.lyricsFor(library.tracks.single, online: false);
      expect(reads, 1);
      await library.setArtistsGrid(true); // a setting: the songs aren't rebuilt
      await library.setSidebar(width: 300);
      await lyrics.lyricsFor(library.tracks.single, online: false);
      expect(reads, 1);
      await library.setBookGenres(['Audiobook']); // rebuilds the songs (as a rescan does)
      await lyrics.lyricsFor(library.tracks.single, online: false);
      expect(reads, 2);
    });

    test('forgotten songs lose their lyrics found online', () async {
      await storage.write('lyrics.json', {
        'found': {
          'local:gone': {'text': 'old words', 'source': 'lrclib'},
          'local:$songPath': {'text': 'kept words', 'source': 'lrclib'},
        },
        'none': {'local:gone2': 5, 'local:kept2': 6},
      });
      final lyrics = LyricsModel(library, storage);
      await lyrics.load();
      lyrics.removeIds({'local:gone', 'local:gone2'});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final saved = jsonDecode(File(p.join(dir.path, 'lyrics.json')).readAsStringSync()) as Map<String, dynamic>;
      expect((saved['found'] as Map).keys, ['local:$songPath']);
      expect((saved['none'] as Map).keys, ['local:kept2']);
    });

    test('the video folder that owns a file is the deepest one', () {
      final videos = VideoLibraryModel(storage, library);
      final root = p.join(dir.path, 'Videos');
      final tv = p.join(root, 'TV');
      library.videoFolders = ['$root${p.separator * 4}', tv];
      expect(videos.ownerFolder(p.join(tv, 'Show', 'e1.mkv')), tv);
      expect(videos.ownerFolder(p.join(root, 'Films', 'f.mkv')), '$root${p.separator * 4}');
      expect(videos.ownerFolder(p.join(dir.path, 'elsewhere.mkv')), isNull);
      videos.dispose();
    });
  });
}
