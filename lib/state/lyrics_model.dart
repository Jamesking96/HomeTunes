// Works out which lyrics to show for a song, and remembers lyrics found online (lyrics.json).
//
// The lyrics view in Now Playing and the desktop player bar call `lyricsFor`. The answer can
// come from several places (see the list on the class below); the user's own lyrics live in
// LibraryModel as an edit, while lyrics found online are cached here so they still work
// offline. A "nothing found" answer from LRCLIB is remembered for 14 days so we don't keep
// asking. The "Find lyrics on LRCLIB…" dialog uses `search` to list every match by hand.
import 'package:flutter/foundation.dart';

import '../models/lyrics.dart';
import '../models/track.dart';
import '../services/local_lyrics.dart';
import '../services/lrclib_client.dart';
import '../services/storage.dart';
import 'library_model.dart';

/// Finds each song's lyrics and remembers the ones found online.
///
/// Where lyrics come from, first match wins:
/// 1. lyrics the user chose or typed (kept as a HomeTunes edit),
/// 2. the music file: its tags or a `.lrc` file beside it (timed wins),
/// 3. lyrics found online before (saved in lyrics.json, so they work offline),
/// 4. the server, for server songs,
/// 5. LRCLIB, if Settings allows it.
class LyricsModel extends ChangeNotifier {
  final LibraryModel library;
  final Storage storage;

  /// For tests: how a song's own lyrics and LRCLIB are reached.
  Future<LocalLyrics> Function(String path) readLocal;
  LrclibClient Function() makeLrclib;

  LyricsModel(this.library, this.storage, {Future<LocalLyrics> Function(String path)? readLocal, LrclibClient Function()? makeLrclib})
      : readLocal = readLocal ?? readLocalLyrics,
        makeLrclib = makeLrclib ?? LrclibClient.new {
    library.addListener(_onLibraryChanged);
  }

  // Files may have changed (rescan, lyrics written into them): read them again. Only when the
  // songs themselves were rebuilt (a new list), not for every settings change (refactor phase 1,
  // 8 Oct 2026: a theme or sidebar change used to throw these away too).
  late List<Track> _knownTracks = library.tracks;
  void _onLibraryChanged() {
    if (identical(library.tracks, _knownTracks)) return;
    _knownTracks = library.tracks;
    _local.clear();
  }

  @override
  void dispose() {
    library.removeListener(_onLibraryChanged);
    super.dispose();
  }

  /// Lyrics found online, by track id: text and where from.
  Map<String, ({String text, LyricsSource source})> _found = {};

  /// Songs nothing was found for online, and when (so we don't ask every time).
  Map<String, int> _none = {};

  /// Ask LRCLIB again for a song it had nothing for after this long.
  static const retryAfter = Duration(days: 14);

  /// Each song's own lyrics (file or .lrc), read once per run.
  final Map<String, LocalLyrics> _local = {};

  /// Look-ups in progress, so asking twice doesn't search twice.
  // Keyed by "track id|online", since an offline-only look-up can give a different answer.
  final Map<String, Future<Lyrics?>> _pending = {};

  /// The clock, swappable in tests.
  DateTime Function() now = DateTime.now;

  /// Goes up whenever lyrics may have changed, so views look again.
  int revision = 0;

  // Every redraw bumps [revision]. Views that cache a lyrics future can compare the number
  // to know when to ask again.
  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  /// Reads lyrics.json (at start-up and after a backup is restored).
  Future<void> load() async {
    _found = {};
    _none = {};
    _local.clear();
    final j = await storage.read('lyrics.json');
    if (j is Map<String, dynamic>) {
      final f = j['found'];
      if (f is Map) {
        for (final e in f.entries) {
          final v = e.value;
          if (v is! Map || v['text'] is! String) continue; // skip damaged entries
          // Older files may not say where the lyrics came from; assume LRCLIB.
          final source = LyricsSource.values.asNameMap()[v['source']] ?? LyricsSource.lrclib;
          _found[e.key as String] = (text: v['text'] as String, source: source);
        }
      }
      final n = j['none'];
      if (n is Map) {
        for (final e in n.entries) {
          if (e.value is int) _none[e.key as String] = e.value as int;
        }
      }
    }
    notifyListeners();
  }

  /// Writes the online finds and the "nothing found" times back to lyrics.json.
  Future<void> _save() => storage.write('lyrics.json', {
        'found': {
          for (final e in _found.entries) e.key: {'text': e.value.text, 'source': e.value.source.name},
        },
        'none': _none,
      });

  /// Files that moved (old id -> new id) keep the lyrics found for them online, and the
  /// "nothing found" time, so they aren't looked up again (0.1.16; wired up in main.dart).
  void remapIds(Map<String, String> moved) {
    var changed = false;
    for (final e in moved.entries) {
      final found = _found.remove(e.key);
      if (found != null) {
        _found.putIfAbsent(e.value, () => found);
        changed = true;
      }
      final none = _none.remove(e.key);
      if (none != null) {
        _none.putIfAbsent(e.value, () => none);
        changed = true;
      }
    }
    if (changed) _save();
  }

  /// Songs the user chose to forget (Settings › Folders & scanning › missing songs): their
  /// lyrics found online and "nothing found" times go too (refactor phase 1, 8 Oct 2026; wired
  /// up in main.dart next to playlists, listening places and bookmarks).
  void removeIds(Set<String> ids) {
    final before = _found.length + _none.length;
    _found.removeWhere((id, _) => ids.contains(id));
    _none.removeWhere((id, _) => ids.contains(id));
    if (_found.length + _none.length != before) _save();
  }

  /// A song's lyrics, or null if it has none (or the user hid them).
  /// With [online] false, only what's on this device is used.
  Future<Lyrics?> lyricsFor(Track t, {bool online = true}) {
    final key = '${t.id}|$online';
    // (A block body: returning the removed future would make it wait on itself.)
    return _pending[key] ??= _resolve(t, online).whenComplete(() {
      _pending.remove(key);
    });
  }

  /// Does the actual look-up, trying each source in turn (see the list on the class).
  Future<Lyrics?> _resolve(Track t, bool online) async {
    // 1. The user's own lyrics. An empty edit means "hide lyrics for this song".
    final yours = library.lyricsEdit(t.id);
    if (yours != null) return yours.trim().isEmpty ? null : Lyrics(yours, LyricsSource.yours);

    // 2. The file's own lyrics (tags or a .lrc file beside it).
    final own = await _ownLyrics(t);
    if (own != null) return own;

    // 3. Lyrics found online on an earlier look-up. After this we'd need the internet.
    final saved = _found[t.id];
    if (saved != null) return Lyrics(saved.text, saved.source);
    if (!online) return null;

    // 4. For server songs, ask the Subsonic server (if one is set up).
    final client = library.client;
    if (!t.isLocal && client != null) {
      final text = await client.fetchLyrics(t);
      if (text != null && text.trim().isNotEmpty) {
        await _remember(t.id, text, LyricsSource.server);
        return Lyrics(text, LyricsSource.server);
      }
    }

    // 5. LRCLIB, but only if the user turned on online lyrics, and never for audiobooks.
    if (!library.onlineLyrics || library.bookOfTrack(t.id) != null) return null;
    // Don't ask again if LRCLIB had nothing for this song within the last 14 days.
    final triedAt = _none[t.id];
    if (triedAt != null && now().difference(DateTime.fromMillisecondsSinceEpoch(triedAt)) < retryAfter) return null;
    final lrclib = makeLrclib();
    try {
      final m = await lrclib.find(
        title: t.title,
        artist: t.artist,
        album: t.album,
        duration: t.hasDuration ? t.duration : null,
      );
      final text = m?.bestLyrics;
      // Nothing found: remember when, so we wait before asking again.
      if (text == null) {
        _none[t.id] = now().millisecondsSinceEpoch;
        await _save();
        return null;
      }
      await _remember(t.id, text, LyricsSource.lrclib);
      return Lyrics(text, LyricsSource.lrclib);
    } on LrclibException {
      return null; // offline: try again next time
    } finally {
      // Always close the HTTP client, whatever happened.
      lrclib.close();
    }
  }

  /// The file's own lyrics: timed ones win, then the tags, then a .lrc file.
  Future<Lyrics?> _ownLyrics(Track t) async {
    final path = t.path;
    if (!t.isLocal || path == null) return null;
    final LocalLyrics local;
    // Reading the file happens once per song per run (cached in _local). A file we can't read
    // (moved, locked, damaged) simply has no lyrics of its own.
    try {
      local = _local[t.id] ??= await readLocal(path);
    } catch (_) {
      return null;
    }
    final tags = local.tags == null ? null : Lyrics(local.tags!, LyricsSource.file);
    final lrc = local.lrc == null ? null : Lyrics(local.lrc!, LyricsSource.lrcFile);
    // A timed .lrc beats untimed tag lyrics; otherwise the tags come first, then the .lrc.
    if (lrc != null && lrc.timed && (tags == null || !tags.timed)) return lrc;
    if (tags != null && !tags.isEmpty) return tags;
    if (lrc != null && !lrc.isEmpty) return lrc;
    return null;
  }

  /// Saves lyrics found online, and clears any earlier "nothing found" note for the song.
  Future<void> _remember(String id, String text, LyricsSource source) async {
    _found[id] = (text: text, source: source);
    _none.remove(id);
    await _save();
  }

  /// Uses [text] as the song's lyrics (picked from LRCLIB, pasted or typed).
  Future<void> setYours(Track t, String text) async {
    await library.setLyrics(t.id, text);
    notifyListeners();
  }

  /// Hides any lyrics the song has (file, .lrc or online).
  Future<void> hide(Track t) async {
    await library.setLyrics(t.id, '');
    notifyListeners();
  }

  /// Drops the user's own lyrics for the song, so the file's (or online
  /// ones) show again.
  Future<void> removeYours(Track t) async {
    await library.setLyrics(t.id, null);
    notifyListeners();
  }

  /// Forgets the lyrics found online for a song, and re-reads the file's own,
  /// so the next look-up starts fresh.
  Future<void> forget(Track t) async {
    _local.remove(t.id);
    final hadFound = _found.remove(t.id) != null;
    final hadNone = _none.remove(t.id) != null;
    final changed = hadFound || hadNone;
    if (changed) await _save();
    notifyListeners();
  }

  /// The song has lyrics the user chose or typed.
  bool hasYours(Track t) => (library.lyricsEdit(t.id) ?? '').trim().isNotEmpty;

  /// The user said the song has no lyrics.
  // (Only an exactly empty edit counts here; lyricsFor also treats blank-space-only as hidden.)
  bool isHidden(Track t) => library.lyricsEdit(t.id) == '';

  // ---- searching LRCLIB by hand ----

  /// Everything LRCLIB has for this song, best first.
  /// [title] and [artist] let the user change the search words in the dialog.
  Future<List<LrclibMatch>> search(Track t, {String? title, String? artist}) async {
    final c = makeLrclib();
    try {
      final list = await c.search(
        title: title ?? t.title,
        artist: artist ?? t.artist,
        album: t.album,
        duration: t.hasDuration ? t.duration : null,
      );
      if (list.isNotEmpty || (artist ?? t.artist).isEmpty) return list;
      // Nothing with the artist: try the words together.
      return await c.searchText('${title ?? t.title} ${artist ?? t.artist}', duration: t.hasDuration ? t.duration : null);
    } finally {
      c.close();
    }
  }
}
