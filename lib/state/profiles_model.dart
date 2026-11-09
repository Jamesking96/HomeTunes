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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../services/storage.dart';
import 'custom_art_store.dart' as art;
import 'playlists_model.dart' show playlistOwners;
import 'profile_session.dart';

/// One person who uses HomeTunes on this device.
@immutable
class Profile {
  const Profile({required this.id, required this.name, required this.colour, required this.icon, this.photo, this.pin});

  /// Phase 5: their PIN, only ever kept as `salt:sha256(salt + PIN)` in hex (the user's decision
  /// 4: optional, set up inside the profile, asked when someone switches into it). Null: none.
  final String? pin;

  /// Whether switching into this profile asks for a PIN.
  bool get hasPin => pin != null;

  /// Their own picture (8 Nov: "allow for users to upload their own images via something on the
  /// device or search for one online"): a file in art/profiles, or null for the colour and icon.
  final String? photo;

  /// Never changes (it names the profile's folder).
  final String id;
  final String name;

  /// Its colour, as 0xAARRGGBB.
  final int colour;

  /// Which picture its circle shows (a name from ui/screens/settings/profiles_ui.dart's list).
  final String icon;

  Profile copyWith(
          {String? name, int? colour, String? icon, String? photo, bool noPhoto = false, String? pin, bool noPin = false}) =>
      Profile(
        id: id,
        name: name ?? this.name,
        colour: colour ?? this.colour,
        icon: icon ?? this.icon,
        photo: noPhoto ? null : (photo ?? this.photo),
        pin: noPin ? null : (pin ?? this.pin),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colour': '#${(colour & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        'icon': icon,
        if (photo != null) 'photo': photo,
        if (pin != null) 'pin': pin,
      };

  /// Null when [j] isn't a usable profile.
  static Profile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], colour = j['colour'], icon = j['icon'], photo = j['photo'], pin = j['pin'];
    if (id is! String || !ProfilesModel.goodId.hasMatch(id)) return null;
    final c = colour is String ? int.tryParse(colour.replaceFirst('#', ''), radix: 16) : null;
    return Profile(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : 'Profile',
      colour: 0xFF000000 | (c ?? ProfilesModel.colours.first),
      icon: icon is String && icon.isNotEmpty ? icon : 'person',
      photo: photo is String && photo.isNotEmpty ? photo : null,
      pin: pin is String && RegExp(r'^[0-9a-f]{32}:[0-9a-f]{64}$').hasMatch(pin) ? pin : null,
    );
  }
}

/// What [ProfilesModel.checkPin] found.
enum PinCheck {
  /// Right (or the profile has no PIN).
  right,

  /// Wrong; another try is allowed.
  wrong,

  /// Too many wrong tries: wait ([ProfilesModel.pinWaitLeft]) before trying again.
  wait,
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

  /// The server sign-ins in use now (ServersModel.currentSignIns), which become the first
  /// profile's when profiles are switched on (phase 3). Saved as [ProfilesModel.serversFile].
  Map<String, dynamic> currentSignIns();
}

class ProfilesModel extends ChangeNotifier {
  ProfilesModel(this.data, {this.host}) {
    // The pictures other profiles chose aren't tidied away (the files are shared).
    art.usedByOthers = _picturesOfOthers;
    // Their shared playlists are shown to the person using HomeTunes (phase 4).
    playlistOwners = () async => [
          if (on)
            for (final x in profiles)
              if (x.id != currentId) (id: x.id, name: x.name, storage: data.forProfile(x.id)),
        ];
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
    // Phase 3: what each person's own sign-in reads from the servers, and places waiting to go.
    'server_videos.json',
    'server_videos_pending.json',
    'server_books.json',
    'server_books_pending.json',
  ];

  /// The person's server sign-ins and own servers (ServersModel.mineFile; phase 3). Not in
  /// [personalFiles]: with profiles off they're folded into the data folder's servers.json.
  static const serversFile = 'my_servers.json';

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

  /// HomeTunes opens straight into the last profile used, without asking who's listening (the
  /// user, 8 Nov: "a toggle for a default profile to be loaded in, this should be on by default
  /// and be set to the most recent profile that's been signed into"). Off: it asks every time.
  bool openLast = true;

  /// HomeTunes should ask who's listening before showing anything else: when it's set to ask, or
  /// when the last profile used has a PIN (phase 5: opening straight into it would get round it).
  bool get needsChoosing => on && !chosen && profiles.isNotEmpty && (!openLast || (current?.hasPin ?? false));

  /// Settings › Profiles › Open with the last profile used.
  Future<void> setOpenLast(bool value) async {
    if (openLast == value) return;
    openLast = value;
    await _save();
    notifyListeners();
  }

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
    openLast = true;
    final j = await data.read(fileName);
    if (j is Map) {
      final seen = <String>{};
      for (final x in j['profiles'] is List ? j['profiles'] as List : const []) {
        final p = Profile.fromJson(x);
        if (p != null && seen.add(p.id)) profiles.add(p);
      }
      on = j['on'] == true && profiles.isNotEmpty;
      last = j['last'] is String ? j['last'] as String : null;
      openLast = j['openLast'] != false;
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
        if (!openLast) 'openLast': false,
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
    if (h != null) {
      await dest.write('settings.json', h.personalSettings());
      // The sign-ins in use now are this person's (the user, 8 Nov: only they have server users).
      await dest.write(serversFile, h.currentSignIns());
    }
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

  // ---- PINs (phase 5) ----

  /// A PIN is 4 to 8 digits.
  static final pinPattern = RegExp(r'^\d{4,8}$');

  /// Wrong tries allowed before a wait, and how long the wait is.
  static const pinTries = 5;
  static const pinWait = Duration(seconds: 30);

  final Map<String, int> _wrongPins = {};
  final Map<String, DateTime> _pinWaitUntil = {};

  /// For tests: the clock.
  @visibleForTesting
  DateTime Function() now = DateTime.now;

  static String _pinHash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Sets (or with null, removes) the PIN of the profile **in use**: a PIN is set up inside its
  /// own profile (decision 4). Throws on a PIN that isn't 4–8 digits.
  Future<void> setPin(String? pin) async {
    final id = currentId;
    final i = profiles.indexWhere((x) => x.id == id);
    if (!on || i < 0) return;
    if (pin != null && !pinPattern.hasMatch(pin)) throw ArgumentError('A PIN is 4 to 8 numbers');
    String? stored;
    if (pin != null) {
      final r = Random.secure();
      final salt = [for (var k = 0; k < 16; k++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
      stored = '$salt:${_pinHash(salt, pin)}';
    }
    profiles = [...profiles]..[i] = profiles[i].copyWith(pin: stored, noPin: stored == null);
    await _save();
    notifyListeners();
  }

  /// How long until profile [id]'s PIN can be tried again (zero: now).
  Duration pinWaitLeft(String id) {
    final until = _pinWaitUntil[id];
    if (until == null) return Duration.zero;
    final left = until.difference(now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks [pin] against profile [id]'s. After [pinTries] wrong ones in a row it waits
  /// [pinWait] before taking more.
  PinCheck checkPin(String id, String pin) {
    final hash = byId(id)?.pin;
    if (hash == null) return PinCheck.right;
    if (pinWaitLeft(id) > Duration.zero) return PinCheck.wait;
    final at = hash.indexOf(':');
    if (_pinHash(hash.substring(0, at), pin.trim()) == hash.substring(at + 1)) {
      _wrongPins.remove(id);
      _pinWaitUntil.remove(id);
      return PinCheck.right;
    }
    final wrong = (_wrongPins[id] ?? 0) + 1;
    if (wrong >= pinTries) {
      _wrongPins.remove(id);
      _pinWaitUntil[id] = now().add(pinWait);
      return PinCheck.wait;
    }
    _wrongPins[id] = wrong;
    return PinCheck.wrong;
  }

  /// Where profile pictures are kept (art/profiles; named by their contents).
  String get photoDir => p.join(data.artDir, 'profiles');

  /// The file of [profile]'s own picture, or null (the colour and icon show). Only a file in
  /// [photoDir] counts (profiles.json holds just its name).
  String? photoFile(Profile profile) {
    final name = profile.photo;
    if (name == null) return null;
    final f = p.join(photoDir, p.basename(name));
    return File(f).existsSync() ? f : null;
  }

  /// Gives [id] its own picture ([bytes], already made a sensible size), or takes it away (null).
  /// Pictures nobody uses any more are deleted.
  Future<void> setPhoto(String id, List<int>? bytes) async {
    final i = profiles.indexWhere((x) => x.id == id);
    if (i < 0) return;
    final store = art.CustomArtStore(photoDir);
    final file = bytes == null ? null : await store.store(bytes, '.jpg');
    profiles = [...profiles]
      ..[i] = file == null ? profiles[i].copyWith(noPhoto: true) : profiles[i].copyWith(photo: p.basename(file));
    await _save();
    await store.removeUnused({
      for (final x in profiles)
        if (x.photo != null) p.join(photoDir, p.basename(x.photo!)),
    });
    art.picturesChanged();
    notifyListeners();
  }

  /// Removes a profile and everything that was theirs. Not the one in use, nor the last one.
  Future<bool> remove(String id) async {
    if (id == currentId || profiles.length < 2 || byId(id) == null) return false;
    profiles = [for (final p in profiles) if (p.id != id) p];
    if (last == id) last = currentId ?? profiles.first.id;
    await _save();
    await data.deleteProfile(id);
    // Their picture goes too, unless someone else uses the same one.
    await art.CustomArtStore(photoDir).removeUnused({
      for (final x in profiles)
        if (x.photo != null) p.join(photoDir, p.basename(x.photo!)),
    });
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
