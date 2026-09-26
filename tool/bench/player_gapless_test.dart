// Plays real files through HomeTunes' own player (with the real audio engine)
// to check gapless playback moves through the queue correctly.
// Run: flutter test tool/bench/player_gapless_test.dart --dart-define=LIBMPV=<path to libmpv-2.dll>
//
// Unlike engine_test.dart (which drives media_kit directly), this goes through the app's own
// LibraryModel and PlayerModel, so it checks HomeTunes' queue logic on top of the real engine.
// Four one-second tones are scanned into a temp library and played silently; the test records
// the order in which titles become "now playing".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/play_queue.dart';
import 'package:hometunes/state/player_model.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

import 'engine_test.dart' show tone;

/// Waits until [done] returns true, checking every 50 ms, giving up after [ms] milliseconds.
Future<void> waitFor(bool Function() done, {int ms = 8000}) async {
  for (var i = 0; i < ms ~/ 50 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  // PlayerModel uses Flutter services (e.g. platform channels), so the test binding is needed.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gapless queue: in order, nothing skipped; Play next, repeat-one and missing files work', () async {
    const lib = String.fromEnvironment('LIBMPV');
    MediaKit.ensureInitialized(libmpv: lib.isEmpty ? null : lib);
    final dir = Directory.systemTemp.createTempSync('hometunes_gapless');
    final music = Directory(p.join(dir.path, 'music'))..createSync();
    // Numbered file names, so sorting by path gives a known order (One, Two, Three, Four).
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
    // Record each new "now playing" title (ignoring repeated notifications for the same song).
    final seen = <String>[];
    player.addListener(() {
      final t = player.current?.title;
      if (t != null && (seen.isEmpty || seen.last != t)) seen.add(t);
    });

    // 1. Play the first three in order; "Four" is put next while "One" plays.
    await player.playTracks(tracks.sublist(0, 3));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await player.playNext(tracks[3]); // should play after One, before Two
    // Wait until all four have played and the queue has stopped at the end.
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

    // 3. (0.1.15) Choosing a song whose file has gone while another plays: the old song must
    //    stop, not carry on under the new title. Repeat-all is on, so this also checks that the
    //    stopped engine doesn't keep skipping round the queue.
    //    A 6-second tone is used so it's still playing when the missing song is chosen.
    tone(p.join(music.path, '05 Long.wav'), 6.0, 330.0);
    tone(p.join(music.path, '06 Gone.wav'), 1.0, 880.0);
    await library.scanLocal();
    final long = library.tracks.firstWhere((t) => t.title == 'Long');
    final gone = library.tracks.firstWhere((t) => t.title == 'Gone');
    player.cycleRepeat(); // off
    player.cycleRepeat(); // all
    await player.playTracks([long]);
    await waitFor(() => player.playing, ms: 3000);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(player.playing, isTrue);
    File(gone.path!).deleteSync();
    await player.playTracks([gone]);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    // ignore: avoid_print
    print('missing file: playing ${player.playing}, now showing ${player.current?.title}, error "${player.lastError}"');
    expect(player.current?.title, 'Gone');
    expect(player.playing, isFalse, reason: 'the previous song must stop');
    expect(player.lastError, contains('isn\'t on this device'));

    // Short pause lets the engine finish shutting down before the temp files are deleted.
    player.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
