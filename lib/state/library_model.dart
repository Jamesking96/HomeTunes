// The heart of the app: the library, the user's edits and (almost) all the settings.
//
// LibraryModel loads and saves settings.json, library.json and edits.json. It runs folder scans
// and server syncs (one at a time, see _enqueue), then `_rebuild()` works out everything the
// screens show: edits applied on top of the files' own details, each file sorted into music or
// audiobook (BookRules), and the albums, artists and books built from them. Almost every screen
// watches it. The other models (playlists, listening, bookmarks) are told through callbacks set
// in main.dart when files move or are forgotten, so they can follow. It also holds helpers for
// covers, backups, writing edits into the files, and turning a song into something playable.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/track.dart';
import '../models/track_edit.dart';
import '../services/app_backup.dart';
import '../services/local_scanner.dart';
import '../services/music_permission.dart';
import '../services/storage.dart';
import '../services/subsonic_client.dart';
import '../services/tag_writer.dart';
import '../services/track_matching.dart';
import 'book_index.dart';
import 'library_index.dart' as index;

/// Evening out loudness between songs with ReplayGain information in the files.
enum ReplayGainMode { off, track, album }

/// Holds the music library: local tracks, server tracks, settings, and the
/// derived album/artist lists.
class LibraryModel extends ChangeNotifier {
  final Storage storage;
  final LocalScanner _scanner;

  LibraryModel(this.storage) : _scanner = LocalScanner(storage.artDir);

  // ---- settings ----
  // (Every setting here is saved in settings.json by _saveSettings, and read back in load.)
  /// The music folders the user picked.
  List<String> folders = [];
  /// The Subsonic server's address and login.
  ServerConfig server = const ServerConfig(url: '', username: '', password: '');
  /// The server switch in Settings → Servers. Its songs are kept while off, just hidden.
  bool serverEnabled = false;

  /// Offer to look up missing cover art online (MusicBrainz / Cover Art Archive).
  bool onlineCovers = true;

  /// Offer to look up missing song details (year, artist, genre…) on MusicBrainz.
  bool onlineDetails = true;

  /// Look up lyrics on LRCLIB when a song has none of its own.
  bool onlineLyrics = true;

  /// Audiobooks on the music server show in the Books tab (Settings › Servers).
  bool serverBooks = true;

  // ---- playback settings ----

  /// Load the next song ahead so it follows with no gap.
  bool gaplessPlayback = true;

  /// Even out volume using ReplayGain info in the files (off / by song / by album).
  ReplayGainMode replayGain = ReplayGainMode.off;

  // ---- audiobook settings ----

  /// Folders where everything is an audiobook (scanned as well as [folders]).
  List<String> audiobookFolders = [];

  /// Genres that mark a file as an audiobook.
  List<String> bookGenres = List.of(defaultBookGenres);

  /// Show book covers tall like a book, rather than square like music.
  bool bookCoversTall = false;

  /// Skip buttons while a book plays (seconds).
  int skipBackSeconds = 15;
  int skipForwardSeconds = 30;

  /// Go back a few seconds when resuming a book.
  bool rewindOnResume = true;

  /// Speed for books that haven't had one chosen.
  double defaultBookSpeed = 1.0;

  /// Show the sleep timer button beside play/pause.
  bool sleepButtonShown = true;

  /// Sleep timer length in minutes; [sleepAtEnd] means "end of chapter" (books)
  /// or "end of song" (music).
  int sleepBookMinutes = 30;
  int sleepMusicMinutes = 30;
  // (The sleep timer treats any length of 0 or less the same way.)
  static const sleepAtEnd = -1;

  /// Fade the volume out over this many seconds before the timer pauses (0 = off).
  int sleepFadeSeconds = 10;

  /// "Move to Books" (true) / "Move to Music" (false), by track id.
  Map<String, bool> _kindOverrides = {};
  // The connection to the server, or null when there's no server or it's switched off.
  SubsonicClient? _client;
  SubsonicClient? get client => _client;

  // ---- data ----
  // Songs from the scanned folders and from the server, as read (edits not applied yet).
  List<Track> _local = [];
  List<Track> _remote = [];
  // Every visible song and book file with edits applied, for quick look-up by id.
  Map<String, Track> _byId = {};

  /// Tracks exactly as read from the files / server, before the user's edits.
  Map<String, Track> _rawById = {};

  /// Songs whose files have gone (deleted, moved, or on a drive that isn't
  /// plugged in) but that have edits or are in playlists / Liked Songs. They're
  /// kept so nothing is lost if the song comes back, and are skipped until then.
  List<Track> _missing = [];

  /// Track ids used outside the library (playlists, Liked Songs). Set in main.
  Set<String> Function()? otherReferencedIds;

  /// Told when songs turn up under a new id (moved files, restored backup),
  /// so playlists can follow them. Map is old id → new id.
  void Function(Map<String, String> moved)? onIdsRemapped;

  /// Told when the user forgets songs that aren't on this device.
  void Function(Set<String> ids)? onIdsForgotten;

  /// The user's edits (song details and covers), by track id. Saved in edits.json.
  Map<String, TrackEdit> _edits = {};
  /// Music only (audiobooks are in [books]).
  List<Track> tracks = [];
  List<Album> albums = [];
  List<Artist> artists = [];

  /// Audiobooks, sorted by title.
  List<Book> books = [];

  /// Songs A–Z by title and albums newest first, worked out once per library
  /// change rather than on every redraw.
  List<Track> get songsByTitle => _songsByTitle ??=
      [...tracks]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  List<Track>? _songsByTitle;

  List<Album> get albumsByNewest => _albumsByNewest ??= [...albums]..sort((a, b) => _newest(b).compareTo(_newest(a)));
  List<Album>? _albumsByNewest;

  // "Newest" means the most recently changed file in the album (a stand-in for "recently added").
  static int _newest(Album a) =>
      a.tracks.fold<int>(0, (m, t) => (t.modifiedMs ?? 0) > m ? (t.modifiedMs ?? 0) : m);
  // Quick look-ups built by _rebuild: books by id, and which book each book file belongs to.
  Map<String, Book> _bookById = {};
  Map<String, Book> _bookByTrackId = {};

  /// Whether the phone lets HomeTunes read audio files (always allowed off Android).
  MusicAccess musicAccess = MusicAccess.allowed;

  /// For tests: how to check access.
  Future<MusicAccess> Function() checkAccess = MusicPermission.check;

  /// Music or audiobook folders are set up but the files can't be read.
  bool get needsMusicAccess =>
      musicAccess != MusicAccess.allowed && (folders.isNotEmpty || audiobookFolders.isNotEmpty);

  /// Re-checks access (at start-up and when coming back from the phone's
  /// Settings). Rescans when access has just been given.
  Future<void> refreshMusicAccess({bool rescanIfNewlyAllowed = true}) async {
    final before = musicAccess;
    musicAccess = await checkAccess();
    // Only react when the answer changed (e.g. the user just allowed access in the phone's
    // Settings): clear the "not allowed" message and scan straight away.
    if (musicAccess != before) {
      if (musicAccess == MusicAccess.allowed && error == _noAccessMessage) error = null;
      notifyListeners();
      if (rescanIfNewlyAllowed && musicAccess == MusicAccess.allowed && before != MusicAccess.allowed) {
        await scanLocal();
      }
    }
  }

  static const _noAccessMessage =
      'HomeTunes isn\'t allowed to read your music files. Tap "Allow access" in Settings.';

  // ---- status ----
  /// True while a scan, sync, restore or tag write is running.
  bool busy = false;
  /// Progress text, e.g. "Scanning 120 / 900". Kept in its own notifier so
  /// progress updates only redraw the places that show it, not the whole app
  /// (with thousands of songs, redrawing everything each time was what made
  /// big scans slow).
  final ValueNotifier<String?> statusText = ValueNotifier(null);
  String? get status => statusText.value;
  set status(String? v) => statusText.value = v;
  /// A message for the user when something went wrong (shown as a banner), or null.
  String? error;

  /// Any song or audiobook file by id.
  Track? byId(String id) => _byId[id];

  Book? bookById(String id) => _bookById[id];

  /// The book a file belongs to (null for music).
  Book? bookOfTrack(String trackId) => _bookByTrackId[trackId];

  /// Whether the user moved this file to Books (true) or Music (false) by hand.
  bool? kindOverride(String trackId) => _kindOverrides[trackId];

  /// Every folder that's scanned: music and audiobook folders.
  List<String> get _scanFolders => {...folders, ...audiobookFolders}.toList();

  void clearError() {
    error = null;
    notifyListeners();
  }

  /// Reads settings, edits and the saved library from disk, then builds everything.
  /// Called at start-up and again after a backup is restored.
  Future<void> load() async {
    // Start from defaults, so re-loading after a restore doesn't keep old values.
    folders = [];
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    onlineCovers = true;
    onlineDetails = true;
    onlineLyrics = true;
    serverBooks = true;
    gaplessPlayback = true;
    replayGain = ReplayGainMode.off;
    audiobookFolders = [];
    bookGenres = List.of(defaultBookGenres);
    bookCoversTall = false;
    skipBackSeconds = 15;
    skipForwardSeconds = 30;
    rewindOnResume = true;
    defaultBookSpeed = 1.0;
    sleepButtonShown = true;
    sleepBookMinutes = 30;
    sleepMusicMinutes = 30;
    sleepFadeSeconds = 10;
    _kindOverrides = {};
    _edits = {};
    _local = [];
    _remote = [];
    _missing = [];
    // 1. Settings. Each value falls back to its default if it's missing (e.g. a setting added
    //    in a newer version than the one that wrote the file).
    final s = await storage.read('settings.json') as Map<String, dynamic>?;
    if (s != null) {
      folders = (s['folders'] as List? ?? const []).cast<String>().toList();
      if (s['server'] is Map<String, dynamic>) {
        server = ServerConfig.fromJson(s['server'] as Map<String, dynamic>);
      }
      serverEnabled = (s['serverEnabled'] as bool?) ?? false;
      onlineCovers = (s['onlineCovers'] as bool?) ?? true;
      onlineDetails = (s['onlineDetails'] as bool?) ?? true;
      onlineLyrics = (s['onlineLyrics'] as bool?) ?? true;
      serverBooks = (s['serverBooks'] as bool?) ?? true;
      gaplessPlayback = (s['gaplessPlayback'] as bool?) ?? true;
      replayGain = ReplayGainMode.values.asNameMap()[s['replayGain']] ?? ReplayGainMode.off;
      audiobookFolders = (s['audiobookFolders'] as List? ?? const []).cast<String>().toList();
      if (s['bookGenres'] is List) bookGenres = (s['bookGenres'] as List).cast<String>().toList();
      bookCoversTall = (s['bookCoversTall'] as bool?) ?? false;
      skipBackSeconds = (s['skipBackSeconds'] as int?) ?? 15;
      skipForwardSeconds = (s['skipForwardSeconds'] as int?) ?? 30;
      rewindOnResume = (s['rewindOnResume'] as bool?) ?? true;
      defaultBookSpeed = (s['defaultBookSpeed'] as num?)?.toDouble() ?? 1.0;
      sleepButtonShown = (s['sleepButtonShown'] as bool?) ?? true;
      sleepBookMinutes = (s['sleepBookMinutes'] as int?) ?? 30;
      sleepMusicMinutes = (s['sleepMusicMinutes'] as int?) ?? 30;
      sleepFadeSeconds = (s['sleepFadeSeconds'] as int?) ?? 10;
      final o = s['bookOverrides'];
      if (o is Map) _kindOverrides = {for (final e in o.entries) e.key as String: e.value == true};
    }
    _rebuildClient();
    // 2. The user's edits.
    final edits = await storage.read('edits.json') as Map<String, dynamic>?;
    if (edits != null) {
      _edits = {
        for (final e in edits.entries)
          if (e.value is Map<String, dynamic>) e.key: TrackEdit.fromJson(e.value as Map<String, dynamic>),
      };
    }
    // 3. The library as last scanned/synced, so the app opens instantly without rescanning.
    final lib = await storage.read('library.json') as Map<String, dynamic>?;
    if (lib != null) {
      _local = [for (final j in (lib['local'] as List? ?? const [])) Track.fromJson(j as Map<String, dynamic>)];
      _remote = [for (final j in (lib['remote'] as List? ?? const [])) Track.fromJson(j as Map<String, dynamic>)];
      _missing = [for (final j in (lib['missing'] as List? ?? const [])) Track.fromJson(j as Map<String, dynamic>)];
    }
    _rebuild();
  }

  /// Writes every setting to settings.json.
  Future<void> _saveSettings() => storage.write('settings.json', {
        'folders': folders,
        'server': server.toJson(),
        'serverEnabled': serverEnabled,
        'onlineCovers': onlineCovers,
        'onlineDetails': onlineDetails,
        'onlineLyrics': onlineLyrics,
        'serverBooks': serverBooks,
        'gaplessPlayback': gaplessPlayback,
        'replayGain': replayGain.name,
        'audiobookFolders': audiobookFolders,
        'bookGenres': bookGenres,
        'bookCoversTall': bookCoversTall,
        'skipBackSeconds': skipBackSeconds,
        'skipForwardSeconds': skipForwardSeconds,
        'rewindOnResume': rewindOnResume,
        'defaultBookSpeed': defaultBookSpeed,
        'sleepButtonShown': sleepButtonShown,
        'sleepBookMinutes': sleepBookMinutes,
        'sleepMusicMinutes': sleepMusicMinutes,
        'sleepFadeSeconds': sleepFadeSeconds,
        'bookOverrides': _kindOverrides,
      });

  // The simple on/off settings below redraw first (so the switch moves at once), then save.
  Future<void> setOnlineDetails(bool on) async {
    onlineDetails = on;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setOnlineLyrics(bool on) async {
    onlineLyrics = on;
    notifyListeners();
    await _saveSettings();
  }

  /// Shows or leaves out the audiobooks found on the music server.
  Future<void> setServerBooks(bool on) async {
    serverBooks = on;
    // Changes which files go on the Books tab, so everything has to be rebuilt.
    _rebuild();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setOnlineCovers(bool on) async {
    onlineCovers = on;
    notifyListeners();
    await _saveSettings();
  }

  /// Writes the scanned/synced songs (and the missing ones being kept) to library.json.
  Future<void> _saveLibrary() => storage.write('library.json', {
        'local': [for (final t in _local) t.toJson()],
        'remote': [for (final t in _remote) t.toJson()],
        'missing': [for (final t in _missing) t.toJson()],
      });

  /// Makes a fresh server connection from the current settings (or none).
  /// Syncs check `identical(c, _client)` to notice the connection was replaced mid-sync.
  void _rebuildClient() {
    _client?.close();
    _client = serverEnabled && server.isComplete ? SubsonicClient(server) : null;
  }

  /// Works out everything the screens show from the raw songs, the edits and the settings.
  /// Called after anything changes. It's the slow part of a scan, so scans only call it a few
  /// times rather than once per batch of files.
  void _rebuild() {
    // 1. All songs (server ones only while the server is on), then the user's edits on top.
    final raw = [..._local, if (serverEnabled) ..._remote];
    _rawById = {for (final t in raw) t.id: t};
    final all = [for (final t in raw) _edits[t.id]?.applyTo(t) ?? t];
    _byId = {for (final t in all) t.id: t};
    // 2. Sort each file into music or audiobook. Server book files are left out entirely
    //    when "Audiobooks from the music server" is off.
    final rules = BookRules(genres: bookGenres, bookFolders: audiobookFolders, overrides: _kindOverrides);
    final bookFiles = <Track>[];
    tracks = [];
    for (final t in all) {
      if (!rules.isBook(t)) {
        tracks.add(t);
      } else if (t.isLocal || serverBooks) {
        bookFiles.add(t);
      }
    }
    // 3. Group into books, albums and artists, and refresh the look-up tables.
    books = groupBooks(bookFiles);
    _bookById = {for (final b in books) b.id: b};
    _bookByTrackId = {for (final b in books) for (final t in b.parts) t.id: b};
    albums = index.groupAlbums(tracks);
    artists = index.groupArtists(albums);
    // Throw away the cached sorted lists; they're rebuilt the next time they're asked for.
    _songsByTitle = null;
    _albumsByNewest = null;
    _albumByKey = {for (final a in albums) a.key: a};
    notifyListeners();
  }

  /// Searches songs, albums and artists (see library_index.dart).
  index.SearchResults search(String q) => index.search(q, tracks, albums, artists);

  /// Audiobooks whose title, author, narrator or series contain every word of [q].
  List<Book> searchBooks(String q) => searchBookList(books, q);

  /// Audiobook chapters whose name contains every word of [q].
  List<({Book book, int chapter})> searchChapters(String q) => searchChapterList(books, q);

  /// An album by its key (album artist + album name).
  Album? albumByKey(String key) => _albumByKey[key];
  Map<String, Album> _albumByKey = {};

  /// An artist by name, ignoring case.
  Artist? artistByName(String name) {
    final l = name.toLowerCase();
    for (final a in artists) {
      if (a.name.toLowerCase() == l) return a;
    }
    return null;
  }

  // ---- audiobooks ----

  /// Adds a folder where everything is an audiobook, and scans it.
  Future<void> addAudiobookFolder(String path) async {
    if (audiobookFolders.contains(path)) return;
    audiobookFolders = [...audiobookFolders, path];
    await _saveSettings();
    notifyListeners();
    await scanLocal();
  }

  /// Stops scanning an audiobook folder. The rescan drops its files from the library.
  Future<void> removeAudiobookFolder(String path) async {
    audiobookFolders = audiobookFolders.where((f) => f != path).toList();
    await _saveSettings();
    await scanLocal();
  }

  /// Sets which genres count as audiobooks (blank entries are dropped).
  Future<void> setBookGenres(List<String> genres) async {
    bookGenres = [for (final g in genres) if (g.trim().isNotEmpty) g.trim()];
    await _saveSettings();
    _rebuild();
  }

  Future<void> setBookCoversTall(bool tall) async {
    bookCoversTall = tall;
    await _saveSettings();
    notifyListeners();
  }

  /// Changes the playback settings (Settings > Playback).
  Future<void> updatePlaybackSettings({bool? gaplessPlayback, ReplayGainMode? replayGain}) async {
    this.gaplessPlayback = gaplessPlayback ?? this.gaplessPlayback;
    this.replayGain = replayGain ?? this.replayGain;
    notifyListeners();
    await _saveSettings();
  }

  /// Changes any of the listening settings (Settings > Audiobooks) and sleep timer settings (Settings > Sleep timer).
  Future<void> updateListeningSettings({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    bool? rewindOnResume,
    double? defaultBookSpeed,
    bool? sleepButtonShown,
    int? sleepBookMinutes,
    int? sleepMusicMinutes,
    int? sleepFadeSeconds,
  }) async {
    this.skipBackSeconds = skipBackSeconds ?? this.skipBackSeconds;
    this.skipForwardSeconds = skipForwardSeconds ?? this.skipForwardSeconds;
    this.rewindOnResume = rewindOnResume ?? this.rewindOnResume;
    this.defaultBookSpeed = defaultBookSpeed ?? this.defaultBookSpeed;
    this.sleepButtonShown = sleepButtonShown ?? this.sleepButtonShown;
    this.sleepBookMinutes = sleepBookMinutes ?? this.sleepBookMinutes;
    this.sleepMusicMinutes = sleepMusicMinutes ?? this.sleepMusicMinutes;
    this.sleepFadeSeconds = sleepFadeSeconds ?? this.sleepFadeSeconds;
    notifyListeners();
    await _saveSettings();
  }

  /// "Move to Books" (true), "Move to Music" (false), or back to automatic (null).
  Future<void> setIsBook(Iterable<String> trackIds, bool? isBook) async {
    for (final id in trackIds) {
      if (isBook == null) {
        _kindOverrides.remove(id);
      } else {
        _kindOverrides[id] = isBook;
      }
    }
    await _saveSettings();
    _rebuild();
  }

  // ---- folders ----

  /// Adds a music folder and scans it.
  Future<void> addFolder(String path) async {
    if (folders.contains(path)) return;
    folders = [...folders, path];
    await _saveSettings();
    notifyListeners();
    await scanLocal();
  }

  /// Stops scanning a music folder. The rescan drops its songs (or keeps them as "missing" if
  /// they're in a playlist or have edits).
  Future<void> removeFolder(String path) async {
    folders = folders.where((f) => f != path).toList();
    await _saveSettings();
    await scanLocal();
  }

  /// Scans and syncs run one after another, never at the same time.
  Future<void> _jobs = Future.value();
  int _queued = 0;

  /// Runs [work] after any job already running or waiting. Each job is chained onto the
  /// previous one, so they queue up. The library is rebuilt once each job finishes.
  Future<void> _enqueue(Future<void> Function() work) {
    _queued++;
    final next = _jobs.then((_) async {
      busy = true;
      notifyListeners();
      try {
        await work();
      } finally {
        _queued--;
        busy = _queued > 0;
        _rebuild();
      }
    });
    // The chain swallows errors so one failed job doesn't block the ones after it, but the
    // caller still gets the error through `next`.
    _jobs = next.catchError((_) {});
    return next;
  }

  Future<void> scanLocal() => _enqueue(() async {
        // Without access the scan would find nothing and wrongly drop every
        // song from the library, so don't scan at all.
        musicAccess = await checkAccess();
        if (musicAccess != MusicAccess.allowed && _scanFolders.isNotEmpty) {
          error = _noAccessMessage;
          return;
        }
        error = null;
        status = 'Looking for music…';
        notifyListeners();
        try {
          // Give the scanner what we already know, so unchanged files are reused, not re-read.
          final previous = {for (final t in _local) t.id: t};
          // Progress goes into statusText only (no notifyListeners), so the app isn't redrawn.
          _local = await _scanner.scan(_scanFolders, previous: previous, onProgress: (done, total) {
            status = 'Scanning $done / $total';
          });
          // Follow moved files and keep gone ones that matter, save, then tidy unused covers.
          await _reconcile(previous);
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

  // ---- server ----

  /// Saves server details after checking they work. Returns an error message or null.
  Future<String?> connectServer(ServerConfig config) async {
    // Try the details with a throwaway connection first, so bad details never get saved.
    final test = SubsonicClient(config);
    try {
      await test.ping();
    } on SubsonicException catch (e) {
      return e.message;
    } catch (e) {
      // e.g. an address that isn't a valid URL at all.
      return 'That server address doesn\'t look right ($e)';
    } finally {
      test.close();
    }
    server = config;
    serverEnabled = true;
    _rebuildClient();
    await _saveSettings();
    await syncServer();
    return null;
  }

  /// The server on/off switch. Turning it on syncs, if we don't have its songs yet.
  Future<void> setServerEnabled(bool on) async {
    serverEnabled = on;
    _rebuildClient();
    await _saveSettings();
    _rebuild();
    if (on && _remote.isEmpty) await syncServer();
  }

  /// Removes the server's details and its songs.
  Future<void> forgetServer() async {
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    _remote = [];
    _rebuildClient();
    await _saveSettings();
    await _saveLibrary();
    _rebuild();
  }

  /// Fetches the server's whole song list (album by album) and replaces the server songs.
  Future<void> syncServer() => _enqueue(() async {
        final c = _client;
        if (c == null) return;
        error = null;
        status = 'Connecting to server…';
        notifyListeners();
        try {
          final result = await c.fetchAllTracks(onProgress: (done, total) {
            status = 'Syncing server albums $done / $total';
          });
          status = null;
          // The server may have been forgotten or switched off while we synced.
          if (!identical(c, _client)) return;
          _remote = result.tracks;
          await _saveLibrary();
          if (result.failedAlbums > 0) {
            error = 'Synced, but ${result.failedAlbums} album(s) could not be read from the server.';
          }
        } catch (e) {
          status = null;
          // Cancelled by "Forget server" / switching it off: not an error.
          if (!identical(c, _client)) return;
          error = 'Server sync failed: $e';
        }
      });

  /// After a scan: follows songs that moved to their new place, and keeps the
  /// details of songs that have gone (if anything refers to them) so they
  /// come back as they were if the file returns.
  Future<void> _reconcile(Map<String, Track> previous) async {
    // Everything we knew of before the scan: last scan's songs plus ones already missing.
    final known = {for (final t in _missing) t.id: t, ...previous};
    final found = {for (final t in _local) t.id};
    final gone = [for (final t in known.values) if (!found.contains(t.id)) t];
    if (gone.isEmpty) {
      _missing = [];
      return;
    }
    // Songs that vanished and songs that are new may be the same files in a new place
    // (track_matching.dart pairs them up). Their edits, playlists etc. move to the new id.
    final added = [for (final t in _local) if (!known.containsKey(t.id)) t];
    final moved = matchMovedTracks(gone, added);
    if (moved.isNotEmpty) await _remapIds(moved);
    // Of the rest, keep only the ones something still refers to; the others are simply gone.
    final referenced = referencedIds;
    _missing = [
      for (final t in gone)
        if (!moved.containsKey(t.id) && referenced.contains(t.id)) t
    ];
  }

  /// Ids anything refers to: edits, playlists, Liked Songs.
  Set<String> get referencedIds => {..._edits.keys, ...?otherReferencedIds?.call()};

  /// Moves edits and Books/Music choices from old ids to new ids, then tells the other models.
  Future<void> _remapIds(Map<String, String> moved) async {
    var editsChanged = false;
    for (final e in moved.entries) {
      final edit = _edits.remove(e.key);
      if (edit == null) continue;
      editsChanged = true;
      // A song that already has its own edits keeps them.
      _edits.putIfAbsent(e.value, () => edit);
    }
    if (editsChanged) {
      await storage.write('edits.json', {for (final e in _edits.entries) e.key: e.value.toJson()});
    }
    var overridesChanged = false;
    for (final e in moved.entries) {
      final o = _kindOverrides.remove(e.key);
      if (o == null) continue;
      overridesChanged = true;
      _kindOverrides.putIfAbsent(e.value, () => o);
    }
    if (overridesChanged) await _saveSettings();
    // Playlists, book places and bookmarks follow too (wired up in main.dart).
    onIdsRemapped?.call(moved);
  }

  /// Songs that aren't on this device right now, but whose details and
  /// playlist places are being kept.
  List<Track> get missingTracks => [for (final t in _missing) _edits[t.id]?.applyTo(t) ?? t];

  /// Drops everything kept for songs that aren't on this device.
  Future<void> forgetMissing() async {
    final ids = {for (final t in _missing) t.id};
    if (ids.isEmpty) return;
    _missing = [];
    _edits.removeWhere((id, _) => ids.contains(id));
    onIdsForgotten?.call(ids);
    await _saveLibrary();
    await _saveEdits();
  }

  /// Records a song's real length (found while playing it) and saves it.
  Future<void> learnDuration(String id, Duration d) async {
    var changed = false;
    // Copies the list, swapping in an updated copy of the song (Tracks are never changed in place).
    List<Track> update(List<Track> list) => [
          for (final t in list)
            if (t.id == id && t.duration != d) (() {
              changed = true;
              return t.copyWith(duration: d);
            })() else t,
        ];
    _local = update(_local);
    _remote = update(_remote);
    if (!changed) return;
    _rebuild();
    await _saveLibrary();
  }

  // ---- editing song details ----

  /// The song as read from the file/server, ignoring the user's edits.
  Track? originalById(String id) => _rawById[id];

  /// True if the user has changed anything about this song in HomeTunes.
  bool isEdited(String id) => _edits.containsKey(id);

  /// Applies [changes] (by track id). Fields left null in a change keep their
  /// current value. Edits that end up matching the file are dropped.
  Future<void> editTracks(Map<String, TrackEdit> changes) async {
    for (final entry in changes.entries) {
      final original = _rawById[entry.key];
      if (original == null) continue;
      // Combine with any earlier edit, then drop fields that just repeat what the file says.
      final merged = (_edits[entry.key] ?? TrackEdit.empty).mergedWith(entry.value).normalizedAgainst(original);
      if (merged.isEmpty) {
        _edits.remove(entry.key);
      } else {
        _edits[entry.key] = merged;
      }
    }
    await _saveEdits();
  }

  /// Replaces one song's edit completely (the single-song editor, where a
  /// blank field means "use the file's value").
  Future<void> setEdit(String id, TrackEdit edit) async {
    final original = _rawById[id];
    if (original == null) return;
    // The details editor doesn't touch lyrics: keep the song's own.
    if (edit.lyrics == null) edit = edit.withLyrics(_edits[id]?.lyrics);
    final e = edit.normalizedAgainst(original);
    if (e.isEmpty) {
      _edits.remove(id);
    } else {
      _edits[id] = e;
    }
    await _saveEdits();
  }

  /// Removes custom covers (keeping any other edits) so the files' own art shows.
  Future<void> resetCovers(Iterable<String> ids) async {
    for (final id in ids) {
      final e = _edits[id];
      if (e == null || e.art == null) continue;
      final without = e.withoutArt();
      if (without.isEmpty) {
        _edits.remove(id);
      } else {
        _edits[id] = without;
      }
    }
    await _saveEdits();
  }

  /// Applies the same change to several songs (album edit, multi-select).
  Future<void> editMany(Iterable<String> ids, TrackEdit change) =>
      editTracks({for (final id in ids) id: change});

  /// Forgets the user's edits so the songs show what the files say again.
  /// Lyrics the user added are kept (they have their own "remove").
  Future<void> resetEdits(Iterable<String> ids) async {
    for (final id in ids) {
      // Remove the whole edit, then put back a lyrics-only edit if there were lyrics.
      final lyrics = _edits.remove(id)?.lyrics;
      if (lyrics != null) _edits[id] = TrackEdit(lyrics: lyrics);
    }
    await _saveEdits();
  }

  // ---- lyrics ----

  /// Lyrics the user chose or typed for a song: null if none, "" if they
  /// said the song has no lyrics.
  String? lyricsEdit(String id) => _edits[id]?.lyrics;

  /// Sets (or with null, removes) the user's lyrics for a song.
  Future<void> setLyrics(String id, String? lyrics) async {
    // Other edits on the song are kept; only the lyrics change.
    final e = (_edits[id] ?? TrackEdit.empty).withLyrics(lyrics);
    if (e.isEmpty) {
      _edits.remove(id);
    } else {
      _edits[id] = e;
    }
    await _saveEdits();
  }

  /// Saves edits.json, rebuilds so the change shows, and deletes custom covers no longer used.
  Future<void> _saveEdits() async {
    await storage.write('edits.json', {for (final e in _edits.entries) e.key: e.value.toJson()});
    _rebuild();
    await _removeUnusedCustomArt();
  }

  // Covers the user picked or downloaded live here, apart from the scanner's cached covers.
  String get _customArtDir => p.join(storage.artDir, 'custom');

  /// Copies an image the user picked into the app's data folder (so moving or
  /// deleting the original doesn't break the cover) and returns the copy's path.
  Future<String> importCover(String sourcePath) async =>
      importCoverBytes(await File(sourcePath).readAsBytes(), p.extension(sourcePath).toLowerCase());

  /// Saves cover image bytes (e.g. downloaded from online) and returns the file path.
  Future<String> importCoverBytes(List<int> bytes, [String ext = '']) async {
    // No file extension given: work it out from the image data itself.
    if (ext.isEmpty) {
      final mime = imageMimeType(bytes);
      ext = mime == 'image/png' ? '.png' : (mime == 'image/jpeg' ? '.jpg' : '.img');
    }
    final dir = Directory(_customArtDir);
    await dir.create(recursive: true);
    // Name the file after a fingerprint (md5) of its contents: the same picture is stored once.
    final dest = File(p.join(dir.path, '${md5.convert(bytes)}${ext.isEmpty ? '.img' : ext}'));
    if (!await dest.exists()) await dest.writeAsBytes(bytes, flush: true);
    // Make sure images show the new picture even if an old one was cached.
    PaintingBinding.instance.imageCache.clear();
    return dest.path;
  }

  /// Deletes custom covers that no edit points at any more.
  Future<void> _removeUnusedCustomArt() async {
    final dir = Directory(_customArtDir);
    if (!await dir.exists()) return;
    final used = {for (final e in _edits.values) if (e.art != null) p.normalize(e.art!)};
    await for (final f in dir.list()) {
      if (f is File && !used.contains(p.normalize(f.path))) {
        // A file that can't be deleted right now (e.g. in use) is left for next time.
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  // ---- backup & restore ----

  /// Everything HomeTunes keeps on this device, as one file (see [AppBackup]).
  Future<Uint8List> createBackup({bool includePassword = false, bool includeCoverCache = true}) =>
      AppBackup.create(storage, includePassword: includePassword, includeCoverCache: includeCoverCache);

  /// Where the automatic "just before restoring" backup is kept.
  String get beforeRestorePath => p.join(storage.root.path, AppBackup.beforeRestoreName);

  /// Restores [backup] (replacing or merging, see [AppBackup.restore]), after
  /// saving the current data to [beforeRestorePath]. [reloadOthers] reloads
  /// the other models (playlists). Then rescans, so songs are matched up.
  Future<RestoreResult> restoreBackup(
    BackupContents backup, {
    required bool merge,
    required Future<void> Function() reloadOthers,
  }) async {
    late RestoreResult result;
    await _enqueue(() async {
      error = null;
      status = 'Restoring backup…';
      notifyListeners();
      // 1. Save everything as it is now, so a bad restore can be undone.
      final undo = await AppBackup.create(storage, includePassword: true);
      await File(beforeRestorePath).writeAsBytes(undo, flush: true);
      // 2. Write the backup's files, then reload this model and the others from them.
      result = await AppBackup.restore(storage, backup, merge: merge);
      await load();
      await reloadOthers();
      status = null;
    });
    // 3. Rescan (a backup from another computer has different paths) and sync if needed.
    await scanLocal();
    if (_client != null && _remote.isEmpty) await syncServer();
    return result;
  }

  // ---- writing edits into the music files ----

  /// Local songs whose HomeTunes edits could be written into their files.
  List<Track> get tracksWithWritableEdits => [
        for (final t in _local)
          if (_edits.containsKey(t.id) && t.path != null && TagSupport.forPath(t.path!).anything) t,
      ];

  /// Songs with edits that can't go into their files (server songs, OGG/Opus…).
  int get unwritableEditCount =>
      _edits.keys.where(_rawById.containsKey).length - tracksWithWritableEdits.length;

  /// Where copies of files are kept before tags are written into them.
  String get backupRoot => p.join(storage.root.path, 'backups');

  /// Writes the HomeTunes edits of [tracks] into their music files. Anything a
  /// file type can't hold stays as a HomeTunes edit. With [backup], each file
  /// is copied into a dated folder under [backupRoot] first.
  Future<List<TagWriteResult>> writeEditsToFiles(List<Track> tracks, {bool backup = true}) async {
    final results = <TagWriteResult>[];
    // A folder name like 2026-09-25T14-03-11 (":" isn't allowed in Windows file names).
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backupDir = backup ? p.join(backupRoot, stamp) : null;
    await _enqueue(() async {
      error = null;
      var done = 0;
      for (final t in tracks) {
        status = 'Writing tags ${++done} / ${tracks.length}';
        final edit = _edits[t.id];
        if (edit == null || t.path == null) continue;
        final r = await writeTagsToFile(t.path!, edit, backupDir: backupDir);
        results.add(r);
        // Written: whatever the file now holds is no longer needed as an edit; anything the
        // format couldn't hold (the leftover) stays as an edit. A failed write changes nothing.
        if (r.ok) {
          if (r.leftover.isEmpty) {
            _edits.remove(t.id);
          } else {
            _edits[t.id] = r.leftover;
          }
        }
      }
      await storage.write('edits.json', {for (final e in _edits.entries) e.key: e.value.toJson()});
      // Re-read the changed files so the library shows their new tags.
      status = 'Re-reading changed files…';
      notifyListeners();
      final previous = {for (final t in _local) t.id: t};
      _local = await _scanner.scan(_scanFolders, previous: previous);
      await _reconcile(previous);
      await _saveLibrary();
      await _removeUnusedCustomArt();
      status = null;
    });
    return results;
  }

  /// Local songs, and any song given a custom cover, use an image file on disk;
  /// server songs otherwise use the server's cover art.
  bool _artIsFile(Track t) => t.isLocal || _edits[t.id]?.art != null;

  // ---- playback helpers ----

  /// What the player should open for this track: a file path or a stream URL.
  String? playableUri(Track t) {
    // Null means "can't play this right now"; the player then skips the song.
    if (t.isLocal) {
      // The file may have gone since the last scan (deleted, drive unplugged).
      final path = t.path;
      return path != null && File(path).existsSync() ? path : null;
    }
    final c = _client;
    if (c == null || t.remoteId == null) return null;
    return c.streamUrl(t.remoteId!);
  }

  /// Cover art location for the system media controls (notification, lock screen).
  Uri? artUriFor(Track t, {int size = 512}) {
    final art = t.art;
    if (art == null) return null;
    if (_artIsFile(t)) return Uri.file(art);
    final c = _client;
    return c == null ? null : Uri.parse(c.coverArtUrl(art, size: size));
  }

  /// The cover image to show in the app: a file on disk, or the server's cover picture.
  ImageProvider? artFor(Track? t, {int size = 512}) {
    if (t == null || t.art == null) return null;
    if (_artIsFile(t)) return FileImage(File(t.art!));
    final c = _client;
    if (c == null) return null;
    return NetworkImage(c.coverArtUrl(t.art!, size: size));
  }
}
