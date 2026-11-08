// Every setting says whose it is when profiles are on (Profiles plan, phase 0;
// state/settings/settings_groups.dart SettingScope). With profiles off nothing changes:
// settings.json holds them all, as before.
import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/state/settings/settings_groups.dart';

void main() {
  test('every setting has one scope, and every exception names a real setting', () {
    final s = AppSettings();
    final keys = <String>{};
    for (final g in s.groups) {
      final mine = {for (final x in g.settings) x.key};
      for (final k in mine) {
        expect(keys.add(k), isTrue, reason: '$k is in two groups');
      }
      for (final k in g.scopeExceptions.keys) {
        expect(mine, contains(k), reason: '${g.runtimeType} has an exception for "$k", which it doesn\'t have');
      }
    }
    expect(s.scopes.keys.toSet(), keys);
  });

  test('the device\'s, everyone\'s and each person\'s, as planned', () {
    final w = AppSettings().scopes;
    for (final k in ['folders', 'videoFolders', 'server', 'onlineCovers']) {
      expect(w[k], SettingScope.shared, reason: k);
    }
    for (final k in ['alwaysOnTop', 'videoDirectDrawing', 'tvMode', 'tvSounds', 'scaleWithWindow', 'sidebarWidth', 'sidebarFolded']) {
      expect(w[k], SettingScope.device, reason: k);
    }
    for (final k in ['theme', 'gaplessPlayback', 'skipBackSeconds', 'subtitleSize', 'quickLinks', 'artistPictures', 'seriesInfo']) {
      expect(w[k], SettingScope.profile, reason: k);
    }
  });

  test('the three parts together are the whole of settings.json', () {
    final s = AppSettings();
    final whole = s.toJson();
    final parts = {
      for (final scope in SettingScope.values) ...s.toJsonFor(scope),
    };
    expect(parts, whole);
  });
}
