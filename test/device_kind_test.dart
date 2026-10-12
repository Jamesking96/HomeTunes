// Tests for DeviceKind (Android TV phase, 0.2.0): the "is this a TV?" answer from the app's
// `hometunes/app` channel, and what happens when the channel can't answer.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/services/device_kind.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('hometunes/app');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    DeviceKind.debugIsTv = false;
  });

  test('a TV says so through the app channel', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return call.method == 'isTv' ? true : null;
    });
    expect(await DeviceKind.detect(android: true), isTrue);
    expect(DeviceKind.isTv, isTrue);
    expect(calls, ['isTv']);
  });

  test('a phone is not a TV', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => false);
    expect(await DeviceKind.detect(android: true), isFalse);
    expect(DeviceKind.isTv, isFalse);
  });

  test('an older app shell without isTv counts as not a TV', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw MissingPluginException('no isTv');
    });
    DeviceKind.debugIsTv = true;
    expect(await DeviceKind.detect(android: true), isFalse);
    expect(DeviceKind.isTv, isFalse);
  });

  test('not Android: never asks, never a TV', () async {
    var asked = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      asked = true;
      return true;
    });
    expect(await DeviceKind.detect(android: false), isFalse);
    expect(asked, isFalse);
  });
}
