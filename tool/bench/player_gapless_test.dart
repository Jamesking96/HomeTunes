// Plays real files through HomeTunes' own player (with the real audio engine)
// to check gapless playback moves through the queue correctly.
// Run: flutter test tool/bench/player_gapless_test.dart --dart-define=LIBMPV=<path to libmpv-2.dll>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/play_queue.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'engine_test.dart' show tone;

Future<void> waitFor(bool Function() done, {int ms = 8000}) async {
  for (var i = 0; i < ms ~/ 50 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gapless queue: in order, nothing skipped; Play next and repeat-one still work', () async {
    const lib = String.fromEnvironment('LIBMPV');
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final dir = Directory.systemTemp.createTempSync('hometunes_gapless');
    final music = Directory(p.join(dir.path, 'music'))..createSync();
    for (final (name, hz) in [('01 One', 440.0), ('02 Two', 550.0), ('03 Three', 660.0), ('04 Four', 770.0)]) {
      tone(p.join(music.path, '$name.wav'), 1.0, hz);
    }
    final storage = Storage.at(Directory(p.join(dir.path, 'data'))..createSync());
    Directory(storage.artDir).createSync();
    final library = LibraryModel(storage)..folders = [music.path];
    await library.scanLocal();
    final tracks = [...library.tracks]..sort((a, b) => a.path!.compareTo(b.path!));
    expect(tracks.length, 4);

    final player = PlayerModel(library);
    await player.setVolume(0);
    final seen = <String>[];
    player.addListener(() {
      final t = player.current?.title;
      if (t != null && (seen.isEmpty || seen.last != t)) seen.add(t);
    });

    // 1. Play the first three in order; "Four" is put next while "One" plays.
    await player.playTracks(tracks.sublist(0, 3));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.playNext(tracks[3]); // should play after One, before Two
    await waitFor(() => seen.length >= 4 && !player.playing, ms: 9000);
    // ignore: avoid_print
    print('played: $seen');
    expect(seen, ['One', 'Four', 'Two', 'Three']);

    // 2. Repeat one: the same song again, without moving on.
    seen.clear();
    player.cycleRepeat(); // all
    player.cycleRepeat(); // one
    expect(player.repeat, RepeatSetting.one);
    await player.playTracks(tracks.sublist(0, 2));
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    // ignore: avoid_print
    print('repeat one: $seen, still on ${player.current?.title}, playing ${player.playing}');
    expect(player.current?.title, 'One');
    expect(player.playing, isTrue);

    player.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
