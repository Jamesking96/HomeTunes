// PlayerModel with a pretend audio engine (refactor phase 4, 9 Oct 2026). Before, the player's
// queue, gapless and audiobook logic could only be checked on the real engine
// (tool/bench/player_gapless_test.dart, which still runs it for real). These tests check what
// PlayerModel asks the engine to do: which files it holds, what it opens where, and what happens
// when a file ends. See test/fake_audio_engine.dart for how the pretend engine behaves.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/models/volume_boost.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_queue.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:path/path.dart' as p;

import 'fake_audio_engine.dart';

/// Lets the engine's events reach PlayerModel and its reactions finish.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late Storage storage;
  late LibraryModel library;
  late FakeAudioEngine engine;
  late EqualizerModel eq;
  late PlayerModel player;
  late List<Track> songs; // One, Two, Three, Four

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hometunes_player');
    storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    final music = p.join(dir.path, 'music');
    final book = p.join(music, 'Books', 'Dune');
    Map<String, dynamic> track(String path, String title, {int seconds = 200, Map<String, dynamic> more = const {}}) {
      File(path)
        ..createSync(recursive: true)
        ..writeAsBytesSync([0]);
      return {
        'id': 'local:$path', 'source': 'local', 'title': title, 'artist': 'The Mornings', 'album': 'Breakfast',
        'albumArtist': 'The Mornings', 'path': path, 'durationMs': seconds * 1000, ...more,
      };
    }

    await storage.write('settings.json', {'folders': [music]});
    await storage.write('library.json', {
      'local': [
        for (final (i, name) in ['One', 'Two', 'Three', 'Four'].indexed)
          track(p.join(music, '0${i + 1} $name.mp3'), name, more: {'trackNumber': i + 1}),
        for (final n in [1, 2])
          track(p.join(book, 'Dune $n.mp3'), 'Dune $n', seconds: 60, more: {
            'artist': 'Frank Herbert', 'albumArtist': 'Frank Herbert', 'album': 'Dune', 'genre': 'Audiobook',
            'trackNumber': n,
          }),
      ],
    });
    library = LibraryModel(storage);
    await library.load();
    songs = [...library.tracks]..sort((a, b) => a.path!.compareTo(b.path!));
    eq = EqualizerModel(storage);
    engine = FakeAudioEngine();
    player = PlayerModel(library, listening: ListeningModel(storage), equalizer: eq, engine: engine);
    await settle();
  });

  tearDown(() async {
    player.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 100)); // saves finish in the background
    dir.deleteSync(recursive: true);
  });

  test('the library has four songs and one two-file audiobook', () {
    expect([for (final t in songs) t.title], ['One', 'Two', 'Three', 'Four']);
    expect(library.books.single.parts.map((t) => t.title), ['Dune 1', 'Dune 2']);
  });

  group('Gapless', () {
    test('the engine holds this song and the next; it moves on by itself and the queue follows', () async {
      await player.playTracks(songs.sublist(0, 3));
      await settle();
      expect(player.current!.title, 'One');
      expect(engine.names, ['One', 'Two']);

      engine.finishCurrent();
      await settle();
      expect(player.current!.title, 'Two');
      expect(engine.names, ['Two', 'Three']); // One dropped, Three loaded ahead

      engine.finishCurrent();
      await settle();
      expect(player.current!.title, 'Three');
      expect(engine.names, ['Three']); // nothing after it

      // The end of the queue: it stops at the start of the last song.
      engine.finishCurrent();
      await settle();
      expect(player.current!.title, 'Three');
      expect(player.playing, isFalse);
      expect(engine.calls.last, 'seek ${Duration.zero}');
    });

    test('Play next replaces the song loaded ahead', () async {
      await player.playTracks(songs.sublist(0, 3));
      await player.playNext(songs[3]);
      await settle();
      expect(engine.names, ['One', 'Four']);
      engine.finishCurrent();
      await settle();
      expect(player.current!.title, 'Four');
      expect(engine.names, ['Four', 'Two']);
    });

    test('repeat-one: the engine loops the song by itself, with nothing loaded ahead', () async {
      player.cycleRepeat(); // all
      player.cycleRepeat(); // one
      expect(player.repeat, RepeatSetting.one);
      await player.playTracks(songs.sublist(0, 2));
      await settle();
      expect(engine.calls, contains('loop one true'));
      expect(engine.names, ['One']);
      engine.finishCurrent();
      await settle();
      expect(player.current!.title, 'One');
      expect(player.playing, isTrue);
    });

    test('gapless off: one file at a time, and the engine is told', () async {
      await library.updatePlaybackSettings(gaplessPlayback: false);
      await settle();
      expect(engine.options['gapless-audio'], 'no');
      expect(engine.options['prefetch-playlist'], 'no');
      await player.playTracks(songs.sublist(0, 3));
      await settle();
      expect(engine.names, ['One']);
    });

    test('a song whose file has gone is skipped', () async {
      File(songs[1].path!).deleteSync();
      await player.playTracks(songs.sublist(0, 3), start: 1);
      await settle();
      expect(player.current!.title, 'Three');
      expect(engine.currentName, 'Three');
      // Today the "isn't on this device" note is cleared once the next song opens.
      expect(player.lastError, isNull);
    });
  });

  group('Audiobooks', () {
    test('a skip forward past the end of a file opens the next file at the right place', () async {
      await player.playBook(library.books.single, fromStart: true);
      await settle();
      expect(player.inBook, isTrue);
      expect(engine.currentName, 'Dune 1');
      engine.position = const Duration(seconds: 50);
      await player.skipForward(); // 30 s: 20 s into the second 60 s file
      await settle();
      expect(engine.calls.last, 'open Dune 2 at ${const Duration(seconds: 20)}');
      expect(player.current!.title, 'Dune 2');
    });

    test('Play next during a book waits; Back to music brings the queue back where it was', () async {
      await player.playTracks(songs.sublist(0, 3));
      await settle();
      engine.position = const Duration(seconds: 5);
      await player.playBook(library.books.single, fromStart: true);
      await player.playNext(songs[3]);
      await settle();
      expect(engine.currentName, 'Dune 1'); // the book carries on
      expect(player.hasWaitingMusic, isTrue);

      await player.resumeMusic();
      await settle();
      expect(player.inBook, isFalse);
      expect(player.current!.title, 'One');
      expect(engine.calls.last, 'open One, Four at ${const Duration(seconds: 5)}');
    });
  });

  group('Sound', () {
    test('the equaliser leaves out bands at or above half the sample rate', () async {
      await eq.setEnabled(true);
      await eq.choose('rock', forBooks: false);
      engine.reportSampleRate(22050);
      await settle();
      expect(engine.options['af'], contains('equalizer'));
      expect(engine.options['af'], isNot(contains('f=16000')));
      engine.reportSampleRate(48000);
      await settle();
      expect(engine.options['af'], contains('f=16000'));
    });

    test('an equaliser the engine refuses is reported to the Equaliser screen', () async {
      engine.refuse.add('af');
      await eq.setEnabled(true);
      await eq.choose('rock', forBooks: false);
      await settle();
      expect(eq.unavailable, isTrue);
    });

    test('the volume goes to the engine as its own scale', () async {
      await player.setVolume(50);
      expect(engine.volume, engineVolume(50));
    });
  });

  group('Keeping playback honest (real time)', () {
    test('back on screen but not moving: the song is reopened where it was', () async {
      await player.playTracks(songs.sublist(0, 2));
      await settle();
      engine.position = const Duration(seconds: 42);
      await player.checkAfterResume(); // waits 3 s for movement
      await settle();
      expect(engine.calls.last, 'open One, Two at ${const Duration(seconds: 42)}');
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('a wrong tagged length is learned from the engine a few seconds after the song starts', () async {
      await player.playTracks([songs[0]]);
      await settle();
      engine.reportDuration(const Duration(seconds: 215)); // tagged 200 s
      await Future<void>.delayed(const Duration(milliseconds: 5500)); // 3 s check + 2 s to apply
      expect(library.byId(songs[0].id)!.duration, const Duration(seconds: 215));
    }, timeout: const Timeout(Duration(seconds: 20)));
  });
}
