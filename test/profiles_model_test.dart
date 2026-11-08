// Profiles, phase 1 (state/profiles_model.dart; plan: claude/06_PROFILES_PLAN.md): turning them
// on moves the person's things into a profile (nothing lost), a new profile starts with a copy
// of the edits only, switching swaps whose files every personal model uses (the shared and
// this-device settings stay), and on â†’ off â†’ on gives back the same things.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hometunes/models/playlist.dart';
import 'package:hometunes/models/track_edit.dart';
import 'package:hometunes/services/app_backup.dart';
import 'package:hometunes/services/storage.dart';
import 'package:hometunes/state/bookmarks_model.dart';
import 'package:hometunes/state/custom_art_store.dart';
import 'package:hometunes/state/equalizer_model.dart';
import 'package:hometunes/state/library_model.dart';
import 'package:hometunes/state/listening_model.dart';
import 'package:hometunes/state/play_history.dart';
import 'package:hometunes/state/playlists_model.dart';
import 'package:hometunes/state/profiles_model.dart';
import 'package:hometunes/state/settings/settings_groups.dart';
import 'package:hometunes/state/video_library_model.dart';
import 'package:path/path.dart' as p;

/// The app's host, without the player (main.dart's _AppProfileHost does the same, and stops the
/// music first).
class TestHost implements ProfileHost {
  TestHost(this.lib, this.playlists, this.listening, this.bookmarks, this.equalizer, this.history, this.videos);
  final LibraryModel lib;
  final PlaylistsModel playlists;
  final ListeningModel listening;
  final BookmarksModel bookmarks;
  final EqualizerModel equalizer;
  final PlayHistory history;
  final VideoLibraryModel videos;
  int uses = 0;

  @override
  Future<void> saveEverything() async {
    await lib.flushPendingSaves();
    await videos.flushPendingSaves();
    await equalizer.flush();
  }

  @override
  Map<String, dynamic> personalSettings() => lib.settings.toJsonFor(SettingScope.profile);

  @override
  Future<void> use(Storage personal, {required bool split}) async {
    uses++;
    await lib.usePersonal(personal, split: split);
    await Future.wait([
      playlists.useStorage(personal),
      listening.useStorage(personal),
      bookmarks.useStorage(personal),
      equalizer.useStorage(personal),
      history.useStorage(personal),
      videos.usePersonal(personal),
    ]);
  }

  @override
  Future<void> saveSettings() => lib.saveSettingsNow();

  // The servers are in profile_servers_test.dart.
  @override
  Map<String, dynamic> currentSignIns() => {'signIns': <String, String>{}, 'servers': <Object>[]};
}

void main() {
  late Directory dir;
  late Storage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hometunes_profiles');
    storage = Storage.at(dir);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  File file(String rel) => File(p.joinAll([dir.path, ...rel.split('/')]));
  Map<String, dynamic>? json(String rel) {
    final f = file(rel);
    return f.existsSync() ? jsonDecode(f.readAsStringSync()) as Map<String, dynamic> : null;
  }

  /// Opens everything the way main.dart does: profiles first, then the models on its session.
  Future<(ProfilesModel, TestHost)> open() async {
    final profiles = ProfilesModel(storage);
    await profiles.load();
    final mine = profiles.session.storage;
    final lib = LibraryModel(storage, personal: mine, splitSettings: profiles.on);
    final playlists = PlaylistsModel(mine);
    final listening = ListeningModel(mine);
    final bookmarks = BookmarksModel(mine);
    final equalizer = EqualizerModel(mine);
    final history = PlayHistory(mine);
    await Future.wait([lib.load(), playlists.load(), listening.load(), bookmarks.load(), equalizer.load(), history.load()]);
    final videos = VideoLibraryModel(storage, lib, personal: mine);
    await videos.load();
    final host = TestHost(lib, playlists, listening, bookmarks, equalizer, history, videos);
    profiles.host = host;
    addTearDown(() {
      videos.dispose();
      history.dispose();
    });
    return (profiles, host);
  }

  test('off by default: nothing moves and the data folder is used', () async {
    final (profiles, host) = await open();
    expect(profiles.on, isFalse);
    expect(profiles.needsChoosing, isFalse);
    expect(identical(profiles.session.storage, storage), isTrue);
    expect(host.lib.splitSettings, isFalse);
    expect(file('profiles.json').existsSync(), isFalse);
  });

  test('turning on moves the person\'s things into a profile, nothing lost', () async {
    await storage.write('playlists.json', {'liked': ['a', 'b']});
    await storage.write('listening.json', {'books': <String, Object>{}});
    await storage.write('edits.json', {'song1': const TrackEdit(title: 'Mine').toJson()});
    var (profiles, host) = await open();
    expect(host.playlists.liked, ['a', 'b']);
    expect(host.lib.isEdited('song1'), isTrue);
    await host.lib.settings.appearance.setLook(textSize: 1.3);
    await host.lib.settings.appearance.setTvMode(TvMode.on);

    await profiles.turnOn(name: 'Sam');
    expect(profiles.on, isTrue);
    expect(profiles.current?.name, 'Sam');
    expect(profiles.currentId, 'p1');
    expect(profiles.needsChoosing, isFalse); // the one who turned it on is listening
    // The files moved: in the profile, not in the data folder.
    expect(json('profiles/p1/playlists.json')?['liked'], ['a', 'b']);
    expect(file('playlists.json').existsSync(), isFalse);
    expect(file('listening.json').existsSync(), isFalse);
    expect(file('edits.json').existsSync(), isFalse);
    expect(json('profiles/p1/edits.json')?['song1'], isNotNull);
    // Settings split: the person's own in the profile, this device's in the data folder.
    expect(json('profiles/p1/settings.json')?['textSize'], 1.3);
    expect(json('settings.json')?.containsKey('textSize'), isFalse);
    expect(json('settings.json')?['tvMode'], 'on');
    expect(json('profiles.json')?['moved'], isNull);
    // Still the same things on screen.
    expect(host.playlists.liked, ['a', 'b']);
    expect(host.lib.settings.appearance.textSize, 1.3);

    // Opening again: profiles on, the last one loaded and opened straight away (8 Nov: "a
    // default profile to be loaded in, this should be on by default").
    (profiles, host) = await open();
    expect(profiles.on, isTrue);
    expect(profiles.currentId, 'p1');
    expect(profiles.openLast, isTrue);
    expect(profiles.needsChoosing, isFalse);
    // With that switched off, "Who's listening?" asks.
    await profiles.setOpenLast(false);
    (profiles, host) = await open();
    expect(profiles.openLast, isFalse);
    expect(profiles.needsChoosing, isTrue);
    expect(host.playlists.liked, ['a', 'b']);
    expect(host.lib.settings.appearance.textSize, 1.3);
    expect(host.lib.settings.appearance.tvMode, TvMode.on);
    await profiles.switchTo('p1');
    expect(profiles.needsChoosing, isFalse);
  });

  test('a new profile starts with a copy of the edits only; switching swaps whose things are used', () async {
    await storage.write('playlists.json', {'liked': ['a']});
    await storage.write('edits.json', {'song1': const TrackEdit(title: 'Mine').toJson()});
    final (profiles, host) = await open();
    await host.lib.settings.appearance.setLook(textSize: 1.3);
    await host.lib.settings.appearance.setTvMode(TvMode.on);
    await profiles.turnOn(name: 'Sam');

    final alex = await profiles.add(name: 'Alex');
    expect(alex.id, 'p2');
    expect(alex.colour, isNot(profiles.byId('p1')!.colour));
    expect(json('profiles/p2/edits.json')?['song1'], isNotNull);
    expect(file('profiles/p2/playlists.json').existsSync(), isFalse);
    expect(json('profiles/p2/settings.json')?.keys.toSet().difference(ProfilesModel.editSettings.toSet()), isEmpty);

    await profiles.switchTo('p2');
    expect(profiles.current?.name, 'Alex');
    expect(host.playlists.liked, isEmpty);
    expect(host.lib.settings.appearance.textSize, 1.0); // their own look
    expect(host.lib.settings.appearance.tvMode, TvMode.on); // this device's
    expect(host.lib.isEdited('song1'), isTrue); // the copied edits
    // Alex's changes are Alex's.
    await host.lib.settings.appearance.setLook(textSize: 0.9);
    expect(json('profiles/p2/settings.json')?['textSize'], 0.9);
    expect(json('profiles/p1/settings.json')?['textSize'], 1.3);

    await profiles.switchTo('p1');
    expect(host.playlists.liked, ['a']);
    expect(host.lib.settings.appearance.textSize, 1.3);
    expect(host.lib.isEdited('song1'), isTrue);
    expect(json('profiles.json')?['last'], 'p1');
  });

  test('on, off and on again gives back the same things; the other profiles are kept', () async {
    await storage.write('playlists.json', {'liked': ['a']});
    final (profiles, host) = await open();
    await host.lib.settings.appearance.setLook(textSize: 1.3);
    await profiles.turnOn(name: 'Sam');
    await profiles.add(name: 'Alex');
    await profiles.switchTo('p2');
    await storage.forProfile('p2').write('playlists.json', {'liked': ['z']});
    await host.playlists.load();

    // Off, keeping Sam's: Sam's things are everyone's again.
    await profiles.turnOff('p1');
    expect(profiles.on, isFalse);
    expect(identical(profiles.session.storage, storage), isTrue);
    expect(host.lib.splitSettings, isFalse);
    expect(host.playlists.liked, ['a']);
    expect(host.lib.settings.appearance.textSize, 1.3);
    expect(json('playlists.json')?['liked'], ['a']);
    expect(json('settings.json')?['textSize'], 1.3);
    expect(profiles.profiles.length, 2);
    expect(file('profiles/p2/playlists.json').existsSync(), isTrue);

    // Something changed while off belongs to Sam when profiles come back.
    await host.lib.settings.appearance.setLook(textSize: 1.1);
    await profiles.turnOn();
    expect(profiles.currentId, 'p1');
    expect(profiles.profiles.length, 2);
    expect(json('profiles/p1/settings.json')?['textSize'], 1.1);
    expect(file('playlists.json').existsSync(), isFalse);
    await profiles.switchTo('p2');
    expect(host.playlists.liked, ['z']);
  });

  test('a crash between moving and clearing just clears the data folder next time', () async {
    await storage.forProfile('p1').write('playlists.json', {'liked': ['a']});
    await storage.write('playlists.json', {'liked': ['a']});
    await storage.write(ProfilesModel.fileName, {
      'on': true,
      'profiles': [{'id': 'p1', 'name': 'Sam', 'colour': '#FF7A59', 'icon': 'person'}],
      'last': 'p1',
      'moved': false,
    });
    final (profiles, host) = await open();
    expect(profiles.on, isTrue);
    expect(file('playlists.json').existsSync(), isFalse);
    expect(json('profiles.json')?['moved'], isNull);
    expect(host.playlists.liked, ['a']);
  });

  test('a damaged list of profiles is made again from the folders', () async {
    await storage.forProfile('p1').write('playlists.json', {'liked': ['a']});
    await storage.forProfile('p2').write('playlists.json', {'liked': ['b']});
    file('profiles.json').writeAsStringSync('{"on": tr');
    final (profiles, host) = await open();
    expect(profiles.on, isTrue);
    expect([for (final p in profiles.profiles) p.id], ['p1', 'p2']);
    expect(host.playlists.liked, ['a']);
  });

  test('removing a profile takes its things; not the one in use, nor the last', () async {
    final (profiles, _) = await open();
    await profiles.turnOn(name: 'Sam');
    expect(await profiles.remove('p1'), isFalse); // the only one, and in use
    await profiles.add(name: 'Alex');
    expect(Directory(p.join(dir.path, 'profiles', 'p2')).existsSync(), isTrue);
    expect(await profiles.remove('p1'), isFalse); // in use
    expect(await profiles.remove('p2'), isTrue);
    expect(profiles.profiles.length, 1);
    expect(Directory(p.join(dir.path, 'profiles', 'p2')).existsSync(), isFalse);
    // Its folder has gone, so a new one can have its id (and starts empty).
    final again = await profiles.add(name: 'Jo');
    expect(again.id, 'p2');
  });

  test('a picture another profile chose isn\'t tidied away', () async {
    final (profiles, _) = await open();
    await profiles.turnOn(name: 'Sam');
    await profiles.add(name: 'Alex');
    final folder = Directory(p.join(storage.artDir, 'custom'))..createSync(recursive: true);
    final theirs = File(p.join(folder.path, 'theirs.jpg'))..writeAsBytesSync([1]);
    final nobodys = File(p.join(folder.path, 'nobodys.jpg'))..writeAsBytesSync([2]);
    await storage.forProfile('p2').write('edits.json', {'song1': {'art': theirs.path}});
    await CustomArtStore(folder.path).removeUnused(const {});
    expect(theirs.existsSync(), isTrue);
    expect(nobodys.existsSync(), isFalse);
  });

  test('a profile\'s own picture is kept in art/profiles, and goes when nobody uses it', () async {
    final (profiles, _) = await open();
    await profiles.turnOn(name: 'Sam');
    final alex = await profiles.add(name: 'Alex');
    expect(profiles.photoFile(profiles.current!), isNull);
    await profiles.setPhoto('p1', [1, 2, 3]);
    await profiles.setPhoto(alex.id, [4, 5, 6]);
    final mine = profiles.photoFile(profiles.byId('p1')!)!;
    final theirs = profiles.photoFile(profiles.byId(alex.id)!)!;
    expect(File(mine).readAsBytesSync(), [1, 2, 3]);
    expect(p.dirname(mine), p.join(storage.artDir, 'profiles'));
    // Only the file's name is kept in profiles.json.
    expect((json('profiles.json')?['profiles'] as List).first['photo'], p.basename(mine));
    final again = ProfilesModel(storage);
    await again.load();
    expect(again.photoFile(again.byId('p1')!), mine);
    // Back to the colour and icon: the picture goes.
    await profiles.setPhoto('p1', null);
    expect(profiles.photoFile(profiles.byId('p1')!), isNull);
    expect(File(mine).existsSync(), isFalse);
    // Removing the profile takes its picture too.
    await profiles.remove(alex.id);
    expect(File(theirs).existsSync(), isFalse);
  });

  test('renaming and recolouring are saved', () async {
    final (profiles, _) = await open();
    await profiles.turnOn(name: 'Sam');
    await profiles.update('p1', name: '  James ', colour: ProfilesModel.colours[2], icon: 'headphones');
    final again = ProfilesModel(storage);
    await again.load();
    expect(again.current?.name, 'James');
    expect(again.current?.colour, ProfilesModel.colours[2]);
    expect(again.current?.icon, 'headphones');
  });

  test('a backup holds the person\'s things, and restoring puts them back into the profile', () async {
    await storage.write('playlists.json', {'liked': ['a']});
    final (profiles, host) = await open();
    await host.lib.settings.appearance.setLook(textSize: 1.3);
    await profiles.turnOn(name: 'Sam');
    final backup = AppBackup.read(await host.lib.createBackup());
    expect((backup.files['playlists.json'] as Map)['liked'], ['a']);
    expect((backup.files['settings.json'] as Map)['textSize'], 1.3);

    // Change things, then restore the backup (replacing).
    await storage.forProfile('p1').write('playlists.json', {'liked': ['x']});
    await host.lib.settings.appearance.setLook(textSize: 0.9);
    await host.lib.restoreBackup(backup, merge: false, reloadOthers: host.playlists.load);
    expect(host.playlists.liked, ['a']);
    expect(host.lib.settings.appearance.textSize, 1.3);
    expect(file('playlists.json').existsSync(), isFalse);
    expect(json('settings.json')?.containsKey('textSize'), isFalse);
    expect(json('profiles/p1/settings.json')?['textSize'], 1.3);
  });

  // ---- Phase 4: shared playlists (the owner chooses: play it, or play and change it) ----

  test('a shared playlist shows for everyone else; only "play and change" lets them change it', () async {
    final (profiles, host) = await open();
    await profiles.turnOn(name: 'Sam');
    final pl = host.playlists;
    final mineOnly = pl.create('Sam only');
    final road = pl.create('Road trip')..trackIds.addAll(['a', 'b', 'c']);
    pl.setSharing(road, PlaylistSharing.play);
    final party = pl.create('Party')..trackIds.addAll(['x', 'y']);
    pl.setSharing(party, PlaylistSharing.change);
    expect(mineOnly.sharing, PlaylistSharing.off);
    await host.saveEverything();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(json('profiles/p1/playlists.json')?['playlists'][1]['sharing'], 'play');

    await profiles.add(name: 'Alex');
    await profiles.switchTo('p2');
    // Alex sees Sam's two shared playlists, not the private one, marked as Sam's.
    expect([for (final p in pl.playlists) p.name], ['Road trip', 'Party']);
    final seenRoad = pl.playlists.first, seenParty = pl.playlists.last;
    expect(seenRoad.isMine, isFalse);
    expect(seenRoad.ownerName, 'Sam');
    expect(seenRoad.canChangeSongs, isFalse);
    expect(seenParty.canChangeSongs, isTrue);

    // Play only: nothing changes, not even the name.
    pl.removeAt(seenRoad, 0);
    pl.rename(seenRoad, 'Mine now');
    pl.delete(seenRoad);
    expect(seenRoad.trackIds, ['a', 'b', 'c']);
    expect(seenRoad.name, 'Road trip');
    expect(pl.playlists, contains(seenRoad));
    // Play and change: songs can move and go, written into Sam's file; the name is still Sam's.
    pl.setOrder(seenParty, ['y', 'x']);
    pl.removeAt(seenParty, 1);
    pl.rename(seenParty, 'Alex party');
    await pl.flush();
    final samParty = (json('profiles/p1/playlists.json')?['playlists'] as List).firstWhere((p) => p['name'] == 'Party');
    expect(samParty['trackIds'], ['y']);
    // Alex's own playlists file holds only Alex's (none yet).
    expect(json('profiles/p2/playlists.json')?['playlists'] ?? const [], isEmpty);

    // A new playlist of Alex's comes before the shared ones.
    pl.create('Alex mix');
    expect(pl.playlists.first.name, 'Alex mix');

    // Back to Sam: the change is there, and nothing of Alex's is shown (not shared).
    await profiles.switchTo('p1');
    expect([for (final p in pl.playlists) p.name], ['Sam only', 'Road trip', 'Party']);
    expect(pl.byId(party.id)?.trackIds, ['y']);
    expect(pl.playlists.every((p) => p.isMine), isTrue);
  });

  test('with sharing turned back off, the others no longer see it; with profiles off nobody does', () async {
    final (profiles, host) = await open();
    await profiles.turnOn(name: 'Sam');
    final pl = host.playlists;
    final road = pl.create('Road trip');
    pl.setSharing(road, PlaylistSharing.change);
    await profiles.add(name: 'Alex');
    await profiles.switchTo('p2');
    expect(pl.playlists.single.name, 'Road trip');
    await profiles.switchTo('p1');
    pl.setSharing(pl.byId(road.id)!, PlaylistSharing.off);
    await profiles.switchTo('p2');
    expect(pl.playlists, isEmpty);
    await profiles.switchTo('p1');
    await profiles.turnOff('p1');
    expect([for (final p in pl.playlists) p.name], ['Road trip']);
    expect(pl.playlists.single.isMine, isTrue);
  });
}
