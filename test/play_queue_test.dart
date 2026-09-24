import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/track.dart';
import 'package:hometunes/state/play_queue.dart';

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
}
