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
    // Files may have changed (rescan, lyrics written into them): read them again.
    library.addListener(_local.clear);
  }

  @override
  void dispose() {
    library.removeListener(_local.clear);
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
  final Map<String, Future<Lyrics?>> _pending = {};

  DateTime Function() now = DateTime.now;

  /// Goes up whenever lyrics may have changed, so views look again.
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

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
          if (v is! Map || v['text'] is! String) continue;
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

  Future<void> _save() => storage.write('lyrics.json', {
        'found': {
          for (final e in _found.entries) e.key: {'text': e.value.text, 'source': e.value.source.name},
        },
        'none': _none,
      });

  /// A song's lyrics, or null if it has none (or the user hid them).
  /// With [online] false, only what's on this device is used.
  Future<Lyrics?> lyricsFor(Track t, {bool online = true}) {
    final key = '${t.id}|$online';
    return _pending[key] ??= _resolve(t, online).whenComplete(() => _pending.remove(key));
  }

  Future<Lyrics?> _resolve(Track t, bool online) async {
    final yours = library.lyricsEdit(t.id);
    if (yours != null) return yours.trim().isEmpty ? null : Lyrics(yours, LyricsSource.yours);

    final own = await _ownLyrics(t);
    if (own != null) return own;

    final saved = _found[t.id];
    if (saved != null) return Lyrics(saved.text, saved.source);
    if (!online) return null;

    final client = library.client;
    if (!t.isLocal && client != null) {
      final text = await client.fetchLyrics(t);
      if (text != null && text.trim().isNotEmpty) {
        await _remember(t.id, text, LyricsSource.server);
        return Lyrics(text, LyricsSource.server);
      }
    }

    if (!library.onlineLyrics || library.bookOfTrack(t.id) != null) return null;
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
      lrclib.close();
    }
  }

  /// The file's own lyrics: timed ones win, then the tags, then a .lrc file.
  Future<Lyrics?> _ownLyrics(Track t) async {
    final path = t.path;
    if (!t.isLocal || path == null) return null;
    final LocalLyrics local;
    try {
      local = _local[t.id] ??= await readLocal(path);
    } catch (_) {
      return null;
    }
    final tags = local.tags == null ? null : Lyrics(local.tags!, LyricsSource.file);
    final lrc = local.lrc == null ? null : Lyrics(local.lrc!, LyricsSource.lrcFile);
    if (lrc != null && lrc.timed && (tags == null || !tags.timed)) return lrc;
    if (tags != null && !tags.isEmpty) return tags;
    if (lrc != null && !lrc.isEmpty) return lrc;
    return null;
  }

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
  bool isHidden(Track t) => library.lyricsEdit(t.id) == '';

  // ---- searching LRCLIB by hand ----

  /// Everything LRCLIB has for this song, best first.
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
