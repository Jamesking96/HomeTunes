// Tests for the play queue logic (state/play_queue.dart), which PlayerModel uses to decide what
// plays next: repeat off / all / one, shuffle on and off, "Play next" and "Add to queue",
// reordering and removing upcoming songs, and "peeking" at the next song so it can be loaded
// early for gapless playback. Pure logic, no audio engine involved.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/state/play_queue.dart';

/// A minimal song whose id and title are both [id] (e.g. 't3').
Track t(String id) => Track(
      id: id,
      source: TrackSource.local,
      title: id,
      artist: 'A',
      album: 'B',
      albumArtist: 'A',
    );

void main() {
  final five = [for (var i = 1; i <= 5; i++) t('t$i')];

  // "Back to music" after an audiobook saves the queue and puts it back later. The original
  // order must come back too, so turning shuffle off afterwards restores it (0.1.15).
  test('a saved shuffled queue comes back whole, and shuffle off restores the original order', () {
    final q = PlayQueue(random: Random(7))..setTracks(five, start: 0, shuffle: true);
    q.next();
    q.repeat = RepeatSetting.all;
    final playOrder = q.tracks;
    final original = q.originalTracks;
    final pos = q.position;
    expect(original.map((x) => x.id), ['t1', 't2', 't3', 't4', 't5']);

    // A book plays in between (the queue is replaced), then the music is put back.
    q.setTracks([t('book part 1'), t('book part 2')], shuffle: false);
    q.restore(playOrder, original, position: pos, shuffle: true, repeat: RepeatSetting.all, label: 'Album · X');
    expect(q.tracks, playOrder);
    expect(q.position, pos);
    expect(q.shuffle, isTrue);
    expect(q.repeat, RepeatSetting.all);
    expect(q.contextLabel, 'Album · X');

    final current = q.current!;
    q.setShuffle(false);
    expect(q.tracks.map((x) => x.id), ['t1', 't2', 't3', 't4', 't5']);
    expect(q.current, current);
  });

  // `auto: true` means "the song finished by itself", as opposed to the user pressing Next.
  test('plays in order and stops at the end with repeat off', () {
    final q = PlayQueue()..setTracks(five, start: 3);
    expect(q.current!.id, 't4');
    expect(q.next(auto: true)!.id, 't5');
    expect(q.next(auto: true), isNull);
  });

  test('repeat all wraps round in both directions', () {
    final q = PlayQueue()..setTracks(five, start: 4);
    q.repeat = RepeatSetting.all;
    expect(q.next()!.id, 't1');
    expect(q.previous()!.id, 't5');
  });

  test('repeat one replays on auto-advance but skip still moves on', () {
    final q = PlayQueue()..setTracks(five);
    q.repeat = RepeatSetting.one;
    expect(q.next(auto: true)!.id, 't1');
    expect(q.next()!.id, 't2');
  });

  // A fixed Random seed makes the shuffle order the same every run.
  test('shuffle keeps the chosen song first and contains every song once', () {
    final q = PlayQueue(random: Random(1))..setTracks(five, start: 2, shuffle: true);
    expect(q.current!.id, 't3');
    expect(q.tracks.map((x) => x.id).toSet(), five.map((x) => x.id).toSet());
    expect(q.tracks.length, 5);
  });

  test('turning shuffle off restores album order at the current song', () {
    final q = PlayQueue(random: Random(7))..setTracks(five, start: 0, shuffle: true);
    q.next();
    final cur = q.current!;
    q.setShuffle(false);
    expect(q.current, cur);
    expect(q.tracks.map((x) => x.id).toList(), ['t1', 't2', 't3', 't4', 't5']);
  });

  test('play next inserts after the current song, add goes to the end', () {
    final q = PlayQueue()..setTracks(five.sublist(0, 3));
    q.playNext(t('x'));
    q.add(t('y'));
    expect(q.tracks.map((x) => x.id).toList(), ['t1', 'x', 't2', 't3', 'y']);
  });

  test('reorder and remove upcoming', () {
    final q = PlayQueue()..setTracks(five);
    // upcoming = t2 t3 t4 t5; move t2 to after t4
    q.moveUpcoming(0, 2);
    expect(q.upcoming.map((x) => x.id).toList(), ['t3', 't4', 't2', 't5']);
    q.removeUpcoming(1);
    expect(q.upcoming.map((x) => x.id).toList(), ['t3', 't2', 't5']);
  });

  test('previous at the start with repeat off stays on first song', () {
    final q = PlayQueue()..setTracks(five);
    expect(q.previous()!.id, 't1');
  });

  // peekNextAuto() says which song will play when the current one ends, without moving the
  // queue, so the player can preload it and start it with no gap.
  group('Song to load ahead (gapless)', () {
    test('the next song, without moving', () {
      final q = PlayQueue()..setTracks(five, start: 1);
      expect(q.peekNextAuto()!.id, 't3');
      expect(q.current!.id, 't2');
    });

    test('end of the queue: nothing, or the first song with repeat-all', () {
      final q = PlayQueue()..setTracks(five, start: 4);
      expect(q.peekNextAuto(), isNull);
      q.cycleRepeat(); // all
      expect(q.peekNextAuto()!.id, 't1');
    });

    // With shuffle + repeat-all, a new shuffle order is made when the queue loops, so the next song
    // can't be known in advance: null means "don't preload".
    test('repeat-all with shuffle reshuffles at the loop, so it isn\'t known yet', () {
      final q = PlayQueue(random: Random(3))..setTracks(five, shuffle: true);
      q.cycleRepeat(); // all
      q.jumpTo(4);
      expect(q.peekNextAuto(), isNull);
    });

    // Whatever was peeked must be exactly what next() then gives, even after the queue was edited.
    test('matches what actually plays next, after Play next and reordering', () {
      final q = PlayQueue()..setTracks(five.sublist(0, 3));
      q.playNext(t('x'));
      expect(q.peekNextAuto()!.id, 'x');
      q.moveUpcoming(0, 2);
      final peeked = q.peekNextAuto();
      expect(q.next(auto: true), peeked);
    });

    test('repeat-one: the same song', () {
      final q = PlayQueue()..setTracks(five);
      q.cycleRepeat();
      q.cycleRepeat();
      expect(q.repeat, RepeatSetting.one);
      expect(q.peekNextAuto()!.id, 't1');
    });
  });
}
