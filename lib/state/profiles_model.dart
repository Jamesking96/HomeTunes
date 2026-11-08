// Profiles (phase 1, Nov 2026; plan: claude/06_PROFILES_PLAN.md). Several people share one
// HomeTunes and each keeps their own places, playlists, edits, look and settings. Off by default:
// with it off nothing on screen or on disk changes.
//
// profiles.json (in the data folder): {"on": true, "profiles": [{"id": "p1", "name": "James",
// "colour": "#FF7A59", "icon": "headphones"}, …], "last": "p1", "moved": true}. Each profile's
// own files are in profiles/<id>/ (Storage.forProfile). Turning profiles on moves the person's
// files there; turning them off copies the kept profile's back (the others stay, and come back
// when profiles are turned on again).
//
// The models themselves are switched by [ProfileHost] (main.dart): this file only decides whose
// files are used and moves them.
import 'package:flutter/foundation.dart';

import '../services/storage.dart';
import 'custom_art_store.dart' as art;
import 'profile_session.dart';

/// One person who uses HomeTunes on this device.
@immutable
class Profile {
  const Profile({required this.id, required this.name, required this.colour, required this.icon});

  /// Never changes (it names the profile's folder).
  final String id;
  final String name;

  /// Its colour, as 0xAARRGGBB.
  final int colour;

  /// Which picture its circle shows (a name from ui/screens/settings/profiles_ui.dart's list).
  final String icon;

  Profile copyWith({String? name, int? colour, String? icon}) =>
      Profile(id: id, name: name ?? this.name, colour: colour ?? this.colour, icon: icon ?? this.icon);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colour': '#${(colour & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        'icon': icon,
      };

  /// Null when [j] isn't a usable profile.
  static Profile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], colour = j['colour'], icon = j['icon'];
    if (id is! String || !ProfilesModel.goodId.hasMatch(id)) return null;
    final c = colour is String ? int.tryParse(colour.replaceFirst('#', ''), radix: 16) : null;
    return Profile(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'Profile',
      colour: 0xFF000000 | (c ?? ProfilesModel.colours.first),
      icon: icon is String && icon.isNotEmpty ? icon : 'person',
    );
  }
}

/// What switching profile needs from the rest of the app (main.dart; a fake in tests).
abstract class ProfileHost {
  /// Saves anything waiting, for the person leaving.
  Future<void> saveEverything();

  /// The person's own settings as they are now (SettingScope.profile), to start a profile with.
  Map<String, dynamic> personalSettings();

  /// Points every personal model at [personal] and reads it (stopping what's playing first).
  /// [split]: profiles are on (personal settings in [personal], the rest in the data folder).
  Future<void> use(Storage personal, {required bool split});

  /// Saves the settings as they are now (after [use], into whichever files they now belong in).
  Future<void> saveSettings();
}

class ProfilesModel extends ChangeNotifier {
  ProfilesModel(this.data, {this.host}) {
    // The pictures other profiles chose aren't tidied away (the files are shared).
    art.usedByOthers = _picturesOfOthers;
  }

  /// The data folder.
  final Storage data;

  /// Set once the models exist (main.dart). Null in tests of the list alone.
  ProfileHost? host;

  static const fileName = 'profiles.json';

  /// The person's own files (besides settings.json, whose personal part LibraryModel looks after).
  static const personalFiles = [
    'edits.json',
    'video_edits.json',
    'video_places.json',
    'playlists.json',
    'listening.json',
    'bookmarks.json',
    'equalizer.json',
    'history.json',
    'tv_words.json',
  ];

  /// The edits a new profile starts with, copied from the one it's added from (the user, 8 Nov).
  static const editFiles = ['edits.json', 'video_edits.json'];

  /// Edits kept in the settings (artist pictures, series details), copied the same way.
  static const editSettings = ['artistPictures', 'seriesInfo'];

  static final goodId = RegExp(r'^p\d{1,4}$');

  /// The colours offered for a profile, in order (a new one takes the next unused).
  static const colours = [
    0xFFFF7A59, // coral
    0xFF4FC3F7, // sky
    0xFF81C784, // green
    0xFFBA68C8, // purple
    0xFFFFD54F, // yellow
    0xFFF06292, // pink
    0xFF4DB6AC, // teal
    0xFF90A4AE, // grey
  ];

  /// Profiles are switched on.
  bool on = false;

  /// Everyone, in the order they were added. Kept when profiles are switched off.
  List<Profile> profiles = [];

  /// Whose things are in use now (null with profiles off).
  String? currentId;

  /// The profile last used (with profiles off: the one whose things are in the data folder).
  String? last;

  // False between turning profiles on and the person's files being cleared from the data folder
  // (a crash in between just clears them next time).
  bool _moved = true;

  /// "Who's listening?" has been answered since HomeTunes opened.
  bool chosen = false;

  /// HomeTunes should ask who's listening before showing anything else.
  bool get needsChoosing => on && !chosen && profiles.isNotEmpty;

  Profile? get current => byId(currentId);

  Profile? byId(String? id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Whose files the models should use now.
  ProfileSession get session => ProfileSession.of(data, on ? currentId : null);

  /// Reads profiles.json (at start-up, before the models that use [session]).
  Future<void> load() async {
    on = false;
    profiles = [];
    currentId = null;
    last = null;
    _moved = true;
    chosen = false;
    final j = await data.read(fileName);
    if (j is Map) {
      final seen = <String>{};
      for (final x in j['profiles'] is List ? j['profiles'] as List : const []) {
        final p = Profile.fromJson(x);
        if (p != null && seen.add(p.id)) profiles.add(p);
      }
      on = j['on'] == true && profiles.isNotEmpty;
      last = j['last'] is String ? j['last'] as String : null;
      _moved = j['moved'] != false;
    } else if (data.profileFolders().isNotEmpty) {
      // The list is missing or damaged (set aside by Storage) but the folders are there: make it
      // again from them, so nobody's things go missing. With the person's files still in the
      // data folder, profiles were off.
      profiles = [
        for (final (i, id) in data.profileFolders().where(goodId.hasMatch).indexed)
          Profile(id: id, name: 'Profile ${i + 1}', colour: colours[i % colours.length], icon: 'person'),
      ];
      var filesHere = false;
      for (final f in personalFiles) {
        if (await data.has(f)) filesHere = true;
      }
      on = profiles.isNotEmpty && !filesHere;
      if (profiles.isNotEmpty) await _save();
    }
    if (byId(last) == null) last = profiles.isEmpty ? null : profiles.first.id;
    currentId = on ? last : null;
    if (on && !_moved) await _clearDataFolder();
    notifyListeners();
  }

  Future<void> _save() => data.write(fileName, {
        'on': on,
        'profiles': [for (final p in profiles) p.toJson()],
        if (last != null) 'last': last,
        if (!_moved) 'moved': false,
      });

  /// The id for a new profile: p1, p2… (never one used before by a folder that's still there).
  String _nextId() {
    final used = {...profiles.map((p) => p.id), ...data.profileFolders()};
    for (var n = 1;; n++) {
      if (!used.contains('p$n')) return 'p$n';
    }
  }

  /// The next colour not taken (or the first again).
  int nextColour() {
    final taken = profiles.map((p) => p.colour).toSet();
    return colours.firstWhere((c) => !taken.contains(c), orElse: () => colours[profiles.length % colours.length]);
  }

  /// Switches profiles on (Settings › Profiles). The person's things move into a profile: a new
  /// one called [name] the first time, or the one they were kept from when profiles were
  /// switched off before. Nothing is lost or reset.
  Future<void> turnOn({String name = 'Me', int? colour, String icon = 'person'}) async {
    if (on) return;
    final h = host;
    await h?.saveEverything();
    var id = byId(last)?.id;
    if (id == null) {
      id = _nextId();
      profiles = [...profiles, Profile(id: id, name: _cleanName(name), colour: colour ?? nextColour(), icon: icon)];
    }
    final dest = data.forProfile(id);
    // 1. Copy (the originals stay until the end, so a crash part-way loses nothing).
    for (final f in personalFiles) {
      if (!await data.copyTo(dest, f)) await dest.remove(f);
    }
    if (h != null) await dest.write('settings.json', h.personalSettings());
    // 2. From now on the profile's files are the ones used.
    on = true;
    currentId = id;
    last = id;
    chosen = true;
    _moved = false;
    await _save();
    if (h != null) {
      await h.use(dest, split: true);
      await h.saveSettings();
    }
    // 3. Clear the person's files out of the data folder.
    await _clearDataFolder();
    notifyListeners();
  }

  Future<void> _clearDataFolder() async {
    for (final f in personalFiles) {
      await data.remove(f);
    }
    _moved = true;
    await _save();
  }

  /// Switches profiles off: [keepId]'s things are used again by everyone (copied back to the
  /// data folder). The other profiles stay on disk and come back when profiles are switched on.
  Future<void> turnOff(String keepId) async {
    if (!on || byId(keepId) == null) return;
    if (keepId != currentId) await switchTo(keepId);
    final h = host;
    await h?.saveEverything();
    final src = data.forProfile(keepId);
    for (final f in personalFiles) {
      if (!await src.copyTo(data, f)) await data.remove(f);
    }
    on = false;
    currentId = null;
    last = keepId;
    await _save();
    if (h != null) {
      await h.use(data, split: false);
      await h.saveSettings();
    }
    notifyListeners();
  }

  /// Adds a profile. It starts with a copy of the current profile's edits (song, book and video
  /// details, artist pictures and series details: the user, 8 Nov); everything else starts
  /// afresh.
  Future<Profile> add({required String name, int? colour, String icon = 'person'}) async {
    final p = Profile(id: _nextId(), name: _cleanName(name), colour: colour ?? nextColour(), icon: icon);
    final dest = data.forProfile(p.id);
    final from = session.storage;
    final h = host;
    await h?.saveEverything();
    for (final f in editFiles) {
      await from.copyTo(dest, f);
    }
    if (h != null) {
      final mine = h.personalSettings();
      await dest.write('settings.json', {
        for (final k in editSettings)
          if (mine.containsKey(k)) k: mine[k],
      });
    }
    profiles = [...profiles, p];
    await _save();
    notifyListeners();
    return p;
  }

  /// Changes a profile's name, colour or picture.
  Future<void> update(String id, {String? name, int? colour, String? icon}) async {
    final i = profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    profiles = [...profiles]..[i] = profiles[i].copyWith(name: name == null ? null : _cleanName(name), colour: colour, icon: icon);
    await _save();
    notifyListeners();
  }

  /// Removes a profile and everything that was theirs. Not the one in use, nor the last one.
  Future<bool> remove(String id) async {
    if (id == currentId || profiles.length < 2 || byId(id) == null) return false;
    profiles = [for (final p in profiles) if (p.id != id) p];
    if (last == id) last = currentId ?? profiles.first.id;
    await _save();
    await data.deleteProfile(id);
    notifyListeners();
    return true;
  }

  /// Someone else is listening: what's playing stops, and their things are used from now on.
  Future<void> switchTo(String id) async {
    if (!on || byId(id) == null) return;
    if (id == currentId) {
      chosen = true;
      notifyListeners();
      return;
    }
    final h = host;
    await h?.saveEverything();
    currentId = id;
    last = id;
    await _save();
    await h?.use(data.forProfile(id), split: true);
    chosen = true;
    notifyListeners();
  }

  static String _cleanName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Profile';
    return n.length > 30 ? n.substring(0, 30) : n;
  }

  // Every picture path the profiles not in use point at (their edits and settings).
  Future<Set<String>> _picturesOfOthers() async {
    final out = <String>{};
    void strings(Object? j) {
      if (j is String) {
        out.add(j);
      } else if (j is Map) {
        j.values.forEach(strings);
      } else if (j is List) {
        j.forEach(strings);
      }
    }

    for (final id in data.profileFolders()) {
      if (on && id == currentId) continue;
      if (!goodId.hasMatch(id)) continue;
      final s = data.forProfile(id);
      for (final f in [...editFiles, 'settings.json', 'playlists.json']) {
        try {
          strings(await s.read(f));
        } catch (_) {}
      }
    }
    return out;
  }
}
