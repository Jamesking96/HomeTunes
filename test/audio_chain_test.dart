// The equaliser chain shared by the music player and the video page (refactor phase 4).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/eq_preset.dart';
import 'package:hometunes/services/engine/audio_chain.dart';

EqPreset preset(double g, {double level = 0}) =>
    EqPreset(id: 'p', name: 'P', gains: List.filled(10, g), level: level);

void main() {
  late List<String> sent;
  late List<double> factors;
  late List<bool> results;
  EqPreset? current;
  Completer<void>? hold;
  var options = true;
  final refuse = <String>{};

  AudioChain chain(EqLevel level) => AudioChain(
        preset: () => current,
        hasOptions: () => options,
        setOption: (name, value) async {
          if (hold != null) await hold!.future;
          if (refuse.contains(name)) throw StateError('refused $name');
          sent.add('$name=$value');
        },
        level: level,
        onLevelFactor: (f) async => factors.add(f),
        onResult: results.add,
      );

  setUp(() {
    sent = [];
    factors = [];
    results = [];
    current = null;
    hold = null;
    options = true;
    refuse.clear();
  });

  test('music: the filter goes out once, and the level becomes a volume factor', () async {
    final c = chain(EqLevel.volumeFactor);
    current = preset(2, level: -6);
    await c.update();
    await c.update(); // nothing changed: nothing sent
    expect(sent, [startsWith('af=format=format=floatp,lavfi=[')]);
    expect(factors.single, closeTo(0.501, 0.001));
    expect(c.levelFactor, factors.single);
    expect(results, [false]);
  });

  test('videos: the filter and replaygain-fallback go out together', () async {
    final c = chain(EqLevel.replayGainFallback);
    current = preset(0, level: -3);
    await c.update();
    expect(sent, ['af=', 'replaygain-fallback=-3.0']);
    expect(factors, isEmpty);
    expect(c.levelFactor, 1.0);
    current = preset(0, level: -4);
    await c.update(); // only the level changed: still re-sent
    expect(sent.last, 'replaygain-fallback=-4.0');
  });

  test('a new sample rate drops the bands it can\'t carry; the same rate does nothing', () async {
    final c = chain(EqLevel.volumeFactor);
    current = preset(3);
    await c.update();
    expect(sent.last, contains('f=16000'));
    c.sampleRateChanged(22050);
    await pumpEventQueue();
    expect(sent.last, isNot(contains('f=16000')));
    c.sampleRateChanged(22050);
    c.sampleRateChanged(0);
    c.sampleRateChanged(null);
    await pumpEventQueue();
    expect(sent, hasLength(2));
  });

  test('changes made while one is being sent are caught up with the latest only', () async {
    final c = chain(EqLevel.volumeFactor);
    hold = Completer();
    current = preset(1);
    final first = c.update();
    current = preset(2);
    unawaited(c.update());
    current = preset(4);
    unawaited(c.update());
    hold!.complete();
    await first;
    expect(sent, hasLength(2));
    expect(sent.last, contains('g=4.0'));
  });

  test('a refusal is reported and not retried for the same filter', () async {
    final c = chain(EqLevel.volumeFactor);
    refuse.add('af');
    current = preset(1);
    await c.update();
    await c.update();
    expect(results, [true]);
  });

  test('without engine options nothing is sent, and it goes out once they are there', () async {
    final c = chain(EqLevel.volumeFactor);
    options = false;
    current = preset(1);
    await c.update();
    expect(sent, isEmpty);
    options = true;
    await c.update();
    expect(sent, hasLength(1));
  });

  test('nothing is sent after close', () async {
    final c = chain(EqLevel.volumeFactor);
    c.close();
    current = preset(1);
    await c.update();
    expect(sent, isEmpty);
  });
}
