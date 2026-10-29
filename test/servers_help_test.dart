// The where-and-how notes in Settings › Servers › Downloads and Temporary copies (0.2.5, the
// user, 29 Oct): they say how to open a thing's menu on this kind of device, and how long
// temporary copies stay.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/ui/screens/settings/download_settings.dart';

void main() {
  String all(List<(String, String)> lines) => [for (final (h, t) in lines) '$h: $t'].join('\n');

  test('Downloads: how to download, Keep offline, where they\'re used, finding them', () {
    final tv = all(downloadsHow(HelpDevice.tv));
    expect(tv, contains('Hold OK on a film'));
    expect(tv, contains('Keep offline'));
    expect(tv, contains('even when the server is off'));
    expect(tv, contains('See downloads'));
    expect(tv, isNot(contains('Filter button'))); // no Filter button on the TV
    final pc = all(downloadsHow(HelpDevice.computer));
    expect(pc, contains('Right-click'));
    expect(pc, contains('Source › Downloaded'));
    expect(all(downloadsHow(HelpDevice.phone)), contains('Press and hold'));
  });

  test('Temporary copies: made by themselves, used on replay, cleared after the days set', () {
    final week = all(temporaryHow(HelpDevice.tv, days: 7));
    expect(week, contains('Save a copy while streaming'));
    expect(week, contains('cleared 7 days after you finish it'));
    expect(week, contains('Keep this copy'));
    expect(week, contains('hold ok on it'));
    expect(all(temporaryHow(HelpDevice.computer, days: 1)), contains('cleared 1 day after'));
    expect(all(temporaryHow(HelpDevice.phone)), contains('stay until you use Clear now'));
  });
}
