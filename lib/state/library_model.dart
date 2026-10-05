// The heart of the app: the library, the user's edits and (almost) all the settings.
//
// LibraryModel loads and saves settings.json, library.json and edits.json. It runs folder scans
// and server syncs (one at a time, see _enqueue), then `_rebuild()` works out everything the
// screens show: edits applied on top of the files' own details, each file sorted into music or
// audiobook (BookRules), and the albums, artists and books built from them. Almost every screen
// watches it. The other models (playlists, listening, bookmarks) are told through callbacks set
// in main.dart when files move or are forgotten, so they can follow. It also holds helpers for
// covers, backups, writing edits into the files, and turning a song into something playable.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/track.dart';
import '../models/track_edit.dart';
import '../models/video_item.dart' show PictureShape;
import '../models/video_player_look.dart';
import '../models/volume_boost.dart';
import '../services/app_backup.dart';
import '../services/local_scanner.dart';
import '../services/music_permission.dart';
import '../services/music_video.dart';
import '../services/path_safety.dart';
import '../services/secret_store.dart';
import '../services/server_art_cache.dart';
import '../services/storage.dart';
import '../services/subsonic_client.dart';
import '../services/tag_writer.dart';
import '../services/track_matching.dart';
import '../services/window_pin.dart';
import 'book_index.dart';
import 'library_index.dart' as index;

/// Evening out loudness between songs with ReplayGain information in the files.
enum ReplayGainMode { off, track, album }

/// Reads values out of a JSON map (settings.json), falling back to the default for any value
/// that's missing or has the wrong type. Wrong types are noted in [damaged] so a copy of the
/// file can be kept; missing values are normal (a setting newer than the file) and aren't.
class _Fields {
  final Map<String, dynamic> m;
  bool damaged = false;
  _Fields(this.m);

  T get<T>(String key, T fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is T) return v;
    damaged = true;
    return fallback;
  }

  /// A whole number (a hand-typed 15.0 is accepted as 15).
  int integer(String key, int fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is num && v.isFinite) return v.toInt();
    damaged = true;
    return fallback;
  }

  double number(String key, double fallback) {
    final v = m[key];
    if (v == null) return fallback;
    if (v is num && v.isFinite) return v.toDouble();
    damaged = true;
    return fallback;
  }

  /// A list of text values; anything else in the list is dropped (and noted).
  List<String>? strings(String key) {
    final v = m[key];
    if (v == null) return null;
    if (v is! List) {
      damaged = true;
      return null;
    }
    final out = [for (final x in v) if (x is String) x];
    if (out.length != v.length) damaged = true;
    return out;
  }
}

/// Holds the music library: local tracks, server tracks, settings, and the
/// derived album/artist lists.
class LibraryModel extends ChangeNotifier {
  final Storage storage;
  final LocalScanner _scanner;

  /// Where the server password is kept (see secret_store.dart). Null on platforms without
  /// protected storage, where it stays in settings.json as before.
  final SecretStore? secrets;

  LibraryModel(this.storage, {SecretStore? secrets})
      : _scanner = LocalScanner(storage.artDir),
        secrets = secrets ?? SecretStore.forPlatform() {
    // Damaged files, recoveries and failed saves show in the status strip as they happen.
    storage.addListener(notifyListeners);
  }

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

  /// Offer "Search online" for video pictures and collection posters (TVmaze, AniList,
  /// Wikipedia; 0.1.40).
  bool onlineVideoArt = true;

  /// Audiobooks on the music server show in the Books tab (Settings › Servers).
  bool serverBooks = true;

  // ---- playback settings ----

  /// Load the next song ahead so it follows with no gap.
  bool gaplessPlayback = true;

  /// Even out volume using ReplayGain info in the files (off / by song / by album).
  ReplayGainMode replayGain = ReplayGainMode.off;

  /// Swipe the player left or right (touch screens) to go to the next or previous song, or to
  /// skip forward or back in an audiobook (0.1.17).
  bool swipeToSkip = true;

  /// PC: the window stays on top of other windows (0.1.60, the pin button; see
  /// services/window_pin.dart). Remembered, and put back when the app opens.
  bool alwaysOnTop = false;

  /// Volume boost (0.1.61, Settings › Playback): louder than normal, up to 500 %, for music,
  /// audiobooks and videos. Off and 100 % by default (models/volume_boost.dart). Since 0.1.62
  /// the percentage is how far the volume sliders go ([maxVolume]), not a fixed boost.
  bool volumeBoost = false;
  int volumeBoostPercent = 100;

  /// The top of every volume slider: 100, or the boost's percentage while it's on.
  double get maxVolume => maxVolumeFor(on: volumeBoost, percent: volumeBoostPercent);

  /// Now Playing can show a song's music video in place of its cover, when it has one (0.1.40).
  /// Off: no videos and no video button (Settings › Music).
  bool showMusicVideos = true;

  /// Your Library › Artists shows round pictures in a grid instead of a list (0.1.52).
  bool artistsGrid = false;

  /// Pictures chosen for artists (0.1.53), by artist name: a copied image in art/custom, or
  /// "album:" plus an album key for one of their album covers. Artists not here use their first
  /// album's cover. Kept in settings.json (so in backups).
  Map<String, String> artistPictures = {};
  static const artistAlbumPrefix = 'album:';

  /// The music video starts by itself when a song with one plays. Off: the cover shows until
  /// the video button on Now Playing is pressed (for that song).
  bool autoPlayMusicVideos = true;

  /// The computer's left-hand sidebar (1 Oct): how wide it's been dragged, and whether it's
  /// folded down to its icons.
  double sidebarWidth = 250;
  bool sidebarFolded = false;
  static const sidebarMinWidth = 180.0, sidebarMaxWidth = 420.0;

  /// Settings › Appearance › Shrink to fit small windows (0.1.41): on a computer, buttons and text
  /// get a little smaller when the window is made small (ui/widgets/window_scale.dart).
  bool scaleWithWindow = true;

  /// Settings › Appearance: the colour theme, and "Your own" colours ("#RRGGBB"). See setTheme.
  String themeId = 'default';
  String? customAccent;
  String? customBackground;

  /// Settings › Appearance › Advanced (0.1.25): the user's saved themes, as saved (each a map of
  /// id, name and "#RRGGBB" colours; ui/theme.dart AppPalette.fromJson reads them), the text size
  /// (a multiple of the system size) and how rounded corners are (0 = square, 1 = as designed).
  List<Map<String, dynamic>> savedThemes = [];
  double textSize = 1.0;
  double cornerRoundness = 1.0;

  // ---- audiobook settings ----

  /// Folders where everything is an audiobook (scanned as well as [folders]).
  List<String> audiobookFolders = [];

  /// Folders for the Videos tab (0.1.40). Scanned by VideoLibraryModel, not by the music scan.
  /// An .mp4 inside one is a video, not a song (unless it's the music video beside a song).
  List<String> videoFolders = [];

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

  // ---- video settings (Settings › Videos, 0.1.40) ----

  /// Skip buttons (and ← → keys) while a video plays (seconds).
  int videoSkipBackSeconds = 10;
  int videoSkipForwardSeconds = 10;

  /// Speed for collections that haven't had one chosen (each remembers its own).
  double defaultVideoSpeed = 1.0;

  /// Go back a few seconds when carrying on with a video.
  bool videoRewindOnResume = true;

  /// Phone: videos and music videos are drawn straight from the video chip (0.1.57,
  /// services/video_drawing.dart). Off: the older way (the chip's pictures are copied first).
  bool videoDirectDrawing = true;

  /// The usual picture shape for videos and for collections (each can have its own).
  PictureShape videoPictureShape = PictureShape.wide;
  PictureShape collectionPictureShape = PictureShape.wide;

  /// How the video player's buttons look (Settings › Appearance › Video player).
  VideoPlayerLook videoPlayerLook = VideoPlayerLook.standard;

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

  /// Downloaded server covers for the system media controls (0.1.21, security review #2).
  ServerArtCache? _serverArt;
  String get _serverArtDir => p.join(storage.artDir, 'server');

  /// The server address (host, lower case) the user agreed may be reached over plain http even
  /// though it's on the internet (0.1.21, security review #4). Null when they haven't.
  String? httpAllowedHost;

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

  /// The folders whose files HomeTunes may open, show in Explorer or write tags into: the music
  /// and audiobook folders. (0.1.21, security review #3: paths from a restored backup are only
  /// used when they're inside one of these.)
  List<String> get libraryFolders => _scanFolders;

  /// Where a cover picture may come from: the library folders and HomeTunes' own art folder.
  List<String> get coverFolders => [..._scanFolders, storage.artDir];

  /// Messages about data files that were damaged or recovered (see Storage.problems), or null.
  /// Kept apart from [error] because scans clear [error] when they start.
  String? get dataProblem {
    final m = storage.messages;
    return m.isEmpty ? null : m.join(' ');
  }

  /// Dismisses the message in the status strip (the error, and any data file messages).
  void clearError() {
    error = null;
    storage.clearMessages();
    notifyListeners();
  }

  /// Reads settings, edits and the saved library from disk, then builds everything.
  /// Called at start-up and again after a backup is restored.
  Future<void> load() async {
    // Start from defaults, so re-loading after a restore doesn't keep old values.
    folders = [];
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    httpAllowedHost = null;
    onlineCovers = true;
    onlineDetails = true;
    onlineLyrics = true;
    onlineVideoArt = true;
    serverBooks = true;
    gaplessPlayback = true;
    replayGain = ReplayGainMode.off;
    swipeToSkip = true;
    alwaysOnTop = false;
    volumeBoost = false;
    volumeBoostPercent = 100;
    showMusicVideos = true;
    autoPlayMusicVideos = true;
    artistsGrid = false;
    artistPictures = {};
    sidebarWidth = 250;
    sidebarFolded = false;
    scaleWithWindow = true;
    audiobookFolders = [];
    videoFolders = [];
    bookGenres = List.of(defaultBookGenres);
    bookCoversTall = false;
    skipBackSeconds = 15;
    skipForwardSeconds = 30;
    rewindOnResume = true;
    defaultBookSpeed = 1.0;
    videoSkipBackSeconds = 10;
    videoSkipForwardSeconds = 10;
    defaultVideoSpeed = 1.0;
    videoRewindOnResume = true;
    videoDirectDrawing = true;
    videoPictureShape = PictureShape.wide;
    collectionPictureShape = PictureShape.wide;
    videoPlayerLook = VideoPlayerLook.standard;
    sleepButtonShown = true;
    sleepBookMinutes = 30;
    sleepMusicMinutes = 30;
    sleepFadeSeconds = 10;
    themeId = 'default';
    customAccent = null;
    customBackground = null;
    savedThemes = [];
    textSize = 1.0;
    cornerRoundness = 1.0;
    hiddenFormats = {};
    _kindOverrides = {};
    _edits = {};
    _local = [];
    _remote = [];
    _missing = [];
    // 1. Settings. Each value falls back to its default if it's missing (e.g. a setting added
    //    in a newer version than the one that wrote the file) or has the wrong type.
    //    HomeTunes: a wrong type used to throw here, before the first screen, so the app
    //    wouldn't start. Now that one value falls back, and a copy of the file is kept.
    final raw = await storage.read('settings.json');
    var settingsDamaged = raw != null && raw is! Map<String, dynamic>;
    if (raw is Map<String, dynamic>) {
      final s = _Fields(raw);
      folders = s.strings('folders') ?? [];
      final sv = raw['server'];
      if (sv is Map<String, dynamic>) {
        try {
          server = ServerConfig.fromJson(sv);
        } catch (_) {
          s.damaged = true;
        }
      }
      serverEnabled = s.get('serverEnabled', false);
      final allowed = raw['httpAllowedHost'];
      httpAllowedHost = allowed is String && allowed.isNotEmpty ? allowed : null;
      onlineCovers = s.get('onlineCovers', true);
      onlineDetails = s.get('onlineDetails', true);
      onlineLyrics = s.get('onlineLyrics', true);
      onlineVideoArt = s.get('onlineVideoArt', true);
      serverBooks = s.get('serverBooks', true);
      gaplessPlayback = s.get('gaplessPlayback', true);
      replayGain = ReplayGainMode.values.asNameMap()[raw['replayGain']] ?? ReplayGainMode.off;
      swipeToSkip = s.get('swipeToSkip', true);
      alwaysOnTop = s.get('alwaysOnTop', false);
      volumeBoost = s.get('volumeBoost', false);
      volumeBoostPercent = s.integer('volumeBoostPercent', 100).clamp(volumeBoostMin, volumeBoostMax).toInt();
      showMusicVideos = s.get('showMusicVideos', true);
      autoPlayMusicVideos = s.get('autoPlayMusicVideos', true);
      artistsGrid = s.get('artistsGrid', false);
      final pics = raw['artistPictures'];
      if (pics is Map) {
        artistPictures = {
          for (final e in pics.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String
        };
      }
      sidebarWidth = s.number('sidebarWidth', 250).clamp(sidebarMinWidth, sidebarMaxWidth).toDouble();
      sidebarFolded = s.get('sidebarFolded', false);
      scaleWithWindow = s.get('scaleWithWindow', true);
      audiobookFolders = s.strings('audiobookFolders') ?? [];
      videoFolders = s.strings('videoFolders') ?? [];
      bookGenres = s.strings('bookGenres') ?? List.of(defaultBookGenres);
      bookCoversTall = s.get('bookCoversTall', false);
      skipBackSeconds = s.integer('skipBackSeconds', 15);
      skipForwardSeconds = s.integer('skipForwardSeconds', 30);
      rewindOnResume = s.get('rewindOnResume', true);
      defaultBookSpeed = s.number('defaultBookSpeed', 1.0);
      videoSkipBackSeconds = s.integer('videoSkipBackSeconds', 10);
      videoSkipForwardSeconds = s.integer('videoSkipForwardSeconds', 10);
      defaultVideoSpeed = s.number('defaultVideoSpeed', 1.0);
      videoRewindOnResume = s.get('videoRewindOnResume', true);
      videoDirectDrawing = s.get('videoDirectDrawing', true);
      videoPictureShape = PictureShape.byName(raw['videoPictureShape']) ?? PictureShape.wide;
      collectionPictureShape = PictureShape.byName(raw['collectionPictureShape']) ?? PictureShape.wide;
      videoPlayerLook = VideoPlayerLook.fromJson(raw['videoPlayerLook']);
      sleepButtonShown = s.get('sleepButtonShown', true);
      sleepBookMinutes = s.integer('sleepBookMinutes', 30);
      sleepMusicMinutes = s.integer('sleepMusicMinutes', 30);
      sleepFadeSeconds = s.integer('sleepFadeSeconds', 10);
      final theme = raw['theme'];
      if (theme is String && theme.isNotEmpty) themeId = theme;
      final accent = raw['customAccent'], background = raw['customBackground'];
      customAccent = accent is String && _hexColour.hasMatch(accent) ? accent.toUpperCase() : null;
      customBackground = background is String && _hexColour.hasMatch(background) ? background.toUpperCase() : null;
      final saved = raw['savedThemes'];
      if (saved is List) {
        savedThemes = [
          for (final t in saved)
            if (t is Map && t['id'] is String) Map<String, dynamic>.from(t),
        ];
      }
      textSize = s.number('textSize', 1.0).clamp(0.8, 1.5).toDouble();
      cornerRoundness = s.number('cornerRoundness', 1.0).clamp(0.0, 2.0).toDouble();
      final hidden = raw['hiddenFormats'];
      if (hidden is Map) {
        hiddenFormats = {
          for (final e in hidden.entries)
            if (e.value is List)
              '${e.key}': [for (final f in e.value as List) if (f is String && f.isNotEmpty) f.toLowerCase()],
        }..removeWhere((_, v) => v.isEmpty);
      }
      final o = raw['bookOverrides'];
      if (o is Map) _kindOverrides = {for (final e in o.entries) '${e.key}': e.value == true};
      settingsDamaged = s.damaged;
    }
    if (settingsDamaged) await storage.keepCopy('settings.json');
    // The pin (0.1.60): put the window back on top if it was left that way.
    unawaited(WindowPin.set(alwaysOnTop));
    // The server password lives in the system's protected storage (0.1.17). A plain-text one in
    // settings.json (an older version, or a restored backup that included it) is moved there,
    // and settings.json is saved again without it.
    final movedPassword = await _loadServerPassword();
    _rebuildClient();
    // 2. The user's edits. A damaged entry is skipped (and a copy of the file kept), rather
    //    than losing every edit.
    final edits = await storage.read('edits.json');
    var editsDamaged = edits != null && edits is! Map;
    if (edits is Map) {
      for (final e in edits.entries) {
        try {
          _edits['${e.key}'] = TrackEdit.fromJson(e.value as Map<String, dynamic>);
        } catch (_) {
          editsDamaged = true;
        }
      }
    }
    if (editsDamaged) await storage.keepCopy('edits.json');
    // 3. The library as last scanned/synced, so the app opens instantly without rescanning.
    //    Damaged entries are skipped; the next scan finds those files again.
    final lib = await storage.read('library.json');
    var libraryDamaged = lib != null && lib is! Map;
    List<Track> tracksIn(Object? list) {
      if (list == null) return [];
      if (list is! List) {
        libraryDamaged = true;
        return [];
      }
      final out = <Track>[];
      for (final j in list) {
        try {
          out.add(Track.fromJson(j as Map<String, dynamic>));
        } catch (_) {
          libraryDamaged = true;
        }
      }
      return out;
    }

    if (lib is Map) {
      _local = tracksIn(lib['local']);
      _remote = tracksIn(lib['remote']);
      _missing = tracksIn(lib['missing']);
    }
    if (libraryDamaged) await storage.keepCopy('library.json');
    _rebuild();
    if (movedPassword) await _saveSettings();
  }

  /// True while the password has to stay in settings.json (no protected storage on this device,
  /// or saving it there failed), so it isn't lost.
  bool _passwordInSettings = false;

  /// Fills in [server]'s password from the protected storage, or moves a plain-text one from
  /// settings.json into it. Returns true when settings.json should be saved again without it.
  Future<bool> _loadServerPassword() async {
    final store = secrets;
    _passwordInSettings = store == null;
    if (store == null || server.url.trim().isEmpty) return false;
    final key = SecretStore.serverPasswordKey(server.url, server.username);
    if (server.password.isNotEmpty) {
      if (await store.write(key, server.password)) return true;
      _passwordInSettings = true; // couldn't move it: keep it where it is
      return false;
    }
    final saved = await store.read(key);
    if (saved != null) server = ServerConfig(url: server.url, username: server.username, password: saved);
    return false;
  }

  /// Saves [config]'s password in the protected storage (and forgets [previous]'s, if that was
  /// a different server or user). Falls back to settings.json if that isn't possible.
  Future<void> _storeServerPassword(ServerConfig config, {ServerConfig? previous}) async {
    final store = secrets;
    if (store == null) {
      _passwordInSettings = true;
      return;
    }
    final key = SecretStore.serverPasswordKey(config.url, config.username);
    if (previous != null && previous.url.trim().isNotEmpty) {
      final oldKey = SecretStore.serverPasswordKey(previous.url, previous.username);
      if (oldKey != key) await store.delete(oldKey);
    }
    if (config.password.isEmpty) {
      await store.delete(key);
      _passwordInSettings = false;
    } else {
      _passwordInSettings = !await store.write(key, config.password);
    }
  }

  /// Writes every setting to settings.json.
  Future<void> _saveSettings() => storage.write('settings.json', {
        'folders': folders,
        // The password only goes in here when it can't be kept in protected storage (0.1.17).
        'server': _passwordInSettings ? server.toJson() : server.toJsonWithoutPassword(),
        'serverEnabled': serverEnabled,
        if (httpAllowedHost != null) 'httpAllowedHost': httpAllowedHost,
        'onlineCovers': onlineCovers,
        'onlineDetails': onlineDetails,
        'onlineLyrics': onlineLyrics,
        'onlineVideoArt': onlineVideoArt,
        'serverBooks': serverBooks,
        'gaplessPlayback': gaplessPlayback,
        'replayGain': replayGain.name,
        'swipeToSkip': swipeToSkip,
        'alwaysOnTop': alwaysOnTop,
        'volumeBoost': volumeBoost,
        'volumeBoostPercent': volumeBoostPercent,
        'showMusicVideos': showMusicVideos,
        'autoPlayMusicVideos': autoPlayMusicVideos,
        'artistsGrid': artistsGrid,
        if (artistPictures.isNotEmpty) 'artistPictures': artistPictures,
        'sidebarWidth': sidebarWidth,
        'sidebarFolded': sidebarFolded,
        'scaleWithWindow': scaleWithWindow,
        'audiobookFolders': audiobookFolders,
        'videoFolders': videoFolders,
        'bookGenres': bookGenres,
        'bookCoversTall': bookCoversTall,
        'skipBackSeconds': skipBackSeconds,
        'skipForwardSeconds': skipForwardSeconds,
        'rewindOnResume': rewindOnResume,
        'defaultBookSpeed': defaultBookSpeed,
        'videoSkipBackSeconds': videoSkipBackSeconds,
        'videoSkipForwardSeconds': videoSkipForwardSeconds,
        'defaultVideoSpeed': defaultVideoSpeed,
        'videoRewindOnResume': videoRewindOnResume,
        'videoDirectDrawing': videoDirectDrawing,
        'videoPictureShape': videoPictureShape.name,
        'collectionPictureShape': collectionPictureShape.name,
        'videoPlayerLook': videoPlayerLook.toJson(),
        'sleepButtonShown': sleepButtonShown,
        'sleepBookMinutes': sleepBookMinutes,
        'sleepMusicMinutes': sleepMusicMinutes,
        'sleepFadeSeconds': sleepFadeSeconds,
        'theme': themeId,
        if (customAccent != null) 'customAccent': customAccent,
        if (customBackground != null) 'customBackground': customBackground,
        if (savedThemes.isNotEmpty) 'savedThemes': savedThemes,
        'textSize': textSize,
        'cornerRoundness': cornerRoundness,
        if (hiddenFormats.isNotEmpty) 'hiddenFormats': hiddenFormats,
        'bookOverrides': _kindOverrides,
      });

  /// Adds a saved theme, or replaces the one with the same id (Settings › Appearance ›
  /// Advanced). [use] switches to it.
  Future<void> saveTheme(Map<String, dynamic> theme, {bool use = true}) async {
    final id = theme['id'];
    if (id is! String) return;
    final i = savedThemes.indexWhere((t) => t['id'] == id);
    savedThemes = [...savedThemes];
    if (i < 0) {
      savedThemes.add(Map.of(theme));
    } else {
      savedThemes[i] = Map.of(theme);
    }
    if (use) themeId = id;
    notifyListeners();
    await _saveSettings();
  }

  /// "Your own" back to its starting colours (the Default theme's highlight and background).
  /// Returns what it had, as (accent, background), so the change can be undone.
  Future<(String?, String?)> resetCustomColours() async {
    final before = (customAccent, customBackground);
    customAccent = null;
    customBackground = null;
    notifyListeners();
    await _saveSettings();
    return before;
  }

  /// Puts "Your own" colours back after [resetCustomColours] (Undo).
  Future<void> restoreCustomColours((String?, String?) colours) async {
    customAccent = colours.$1;
    customBackground = colours.$2;
    notifyListeners();
    await _saveSettings();
  }

  /// Removes a saved theme; if it was in use, goes back to Default.
  Future<void> deleteTheme(String id) async {
    savedThemes = [for (final t in savedThemes) if (t['id'] != id) t];
    if (themeId == id) themeId = 'default';
    notifyListeners();
    await _saveSettings();
  }

  /// Text size and corner roundness (Settings › Appearance › Advanced).
  Future<void> setLook({double? textSize, double? cornerRoundness}) async {
    this.textSize = (textSize ?? this.textSize).clamp(0.8, 1.5).toDouble();
    this.cornerRoundness = (cornerRoundness ?? this.cornerRoundness).clamp(0.0, 2.0).toDouble();
    notifyListeners();
    await _saveSettings();
  }

  /// "#RRGGBB".
  static final _hexColour = RegExp(r'^#[0-9A-Fa-f]{6}$');

  /// Settings › Appearance (0.1.24): which colour theme ('default', 'midnight', 'forest' or
  /// 'custom'), and the two colours of "Your own" as "#RRGGBB" (null = not chosen yet). Kept as
  /// text here; ui/theme.dart turns them into colours.
  Future<void> setTheme({String? id, String? accent, String? background}) async {
    themeId = id ?? themeId;
    if (accent != null && _hexColour.hasMatch(accent)) customAccent = accent.toUpperCase();
    if (background != null && _hexColour.hasMatch(background)) customBackground = background.toUpperCase();
    notifyListeners();
    await _saveSettings();
  }

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

  Future<void> setOnlineVideoArt(bool on) async {
    onlineVideoArt = on;
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
    _serverArt?.close();
    final c = _client = serverEnabled && server.isComplete ? SubsonicClient(server) : null;
    _serverArt = c == null ? null : ServerArtCache(_serverArtDir, c);
  }

  /// Works out everything the screens show from the raw songs, the edits and the settings.
  /// Called after anything changes. It's the slow part of a scan, so scans only call it a few
  /// times rather than once per batch of files.
  void _rebuild() {
    // 1. All songs (server ones only while the server is on), then the user's edits on top.
    //    File types switched off in a folder's options are left out (0.1.27); they stay in
    //    _local so the folder still knows which types it has.
    final raw = [
      // (0.1.40) An .mp4 in a video folder is a video for the Videos tab, not a song.
      for (final t in _local) if (!_formatHidden(t) && !_isVideoFolderFile(t)) t,
      if (serverEnabled) ..._remote,
    ];
    _rawById = {for (final t in raw) t.id: t};
    final all = [for (final t in raw) _edits[t.id]?.applyTo(t) ?? t];
    _byId = {for (final t in all) t.id: t};
    // 2. Sort each file into music or audiobook. Server book files are left out entirely
    //    when "Audiobooks from the music server" is off.
    final rules = bookRules = BookRules(genres: bookGenres, bookFolders: audiobookFolders, overrides: _kindOverrides, roots: _scanFolders);
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
    hiddenFormats = {...hiddenFormats}..remove(path);
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

  /// The sidebar's width (kept between [sidebarMinWidth] and [sidebarMaxWidth]) and folded state.
  Future<void> setSidebar({double? width, bool? folded}) async {
    if (width != null) sidebarWidth = width.clamp(sidebarMinWidth, sidebarMaxWidth).toDouble();
    if (folded != null) sidebarFolded = folded;
    notifyListeners();
    await _saveSettings();
  }

  /// Volume boost on / off and how far the volume sliders go (100–500 %, 0.1.61 / 0.1.62). A
  /// volume above the new top is brought down to it by the players.
  Future<void> setVolumeBoost({bool? on, int? percent}) async {
    if (on != null) volumeBoost = on;
    if (percent != null) volumeBoostPercent = percent.clamp(volumeBoostMin, volumeBoostMax).toInt();
    notifyListeners();
    await _saveSettings();
  }

  /// PC: keep the window on top of other windows, or not (0.1.60, the pin button).
  Future<void> setAlwaysOnTop(bool on) async {
    alwaysOnTop = on;
    notifyListeners();
    await WindowPin.set(on);
    await _saveSettings();
  }

  /// Your Library › Artists: grid (true) or list (false) (0.1.52).
  Future<void> setArtistsGrid(bool on) async {
    artistsGrid = on;
    notifyListeners();
    await _saveSettings();
  }

  /// The track whose cover an artist shows: the album chosen with "Use an album cover", else
  /// their first album's (0.1.53).
  Track? artistAlbumArt(Artist a) {
    final pick = artistPictures[a.name];
    if (pick != null && pick.startsWith(artistAlbumPrefix)) {
      final key = pick.substring(artistAlbumPrefix.length);
      final album = a.albums.where((x) => x.key == key).firstOrNull;
      if (album != null) return album.artTrack;
    }
    return a.albums.isEmpty ? null : a.albums.first.artTrack;
  }

  /// The artist's own picture file (Choose an image file…), if one was chosen and it's still
  /// in HomeTunes' art folder; else null (0.1.53).
  String? artistPictureFile(Artist a) {
    final pick = artistPictures[a.name];
    if (pick == null || pick.startsWith(artistAlbumPrefix)) return null;
    return isInsideAny(pick, [storage.artDir]) ? pick : null;
  }

  /// The picture to draw for an artist: their own file, the chosen album cover, or the first
  /// album's cover.
  ImageProvider? artistImage(Artist a, {int size = 512}) {
    final file = artistPictureFile(a);
    if (file != null) return FileImage(File(file));
    return artFor(artistAlbumArt(a), size: size);
  }

  bool hasArtistPicture(Artist a) => artistPictures.containsKey(a.name);

  /// Sets an artist's picture (0.1.53): [file] (already copied in with [importCover] /
  /// [importCoverBytes]), or [album] (one of their albums), or neither to go back to automatic.
  Future<void> setArtistPicture(Artist a, {String? file, Album? album}) async {
    if (file != null) {
      artistPictures[a.name] = file;
    } else if (album != null) {
      artistPictures[a.name] = '$artistAlbumPrefix${album.key}';
    } else {
      artistPictures.remove(a.name);
    }
    PaintingBinding.instance.imageCache.clear();
    notifyListeners();
    await _saveSettings();
    await _removeUnusedCustomArt();
  }

  /// Settings › Appearance › Shrink to fit small windows.
  Future<void> setScaleWithWindow(bool on) async {
    scaleWithWindow = on;
    notifyListeners();
    await _saveSettings();
  }

  /// Changes the playback settings (Settings > Playback).
  Future<void> updatePlaybackSettings({
    bool? gaplessPlayback,
    ReplayGainMode? replayGain,
    bool? swipeToSkip,
    bool? showMusicVideos,
    bool? autoPlayMusicVideos,
  }) async {
    this.gaplessPlayback = gaplessPlayback ?? this.gaplessPlayback;
    this.replayGain = replayGain ?? this.replayGain;
    this.swipeToSkip = swipeToSkip ?? this.swipeToSkip;
    this.showMusicVideos = showMusicVideos ?? this.showMusicVideos;
    this.autoPlayMusicVideos = autoPlayMusicVideos ?? this.autoPlayMusicVideos;
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

  /// Changes any of the video settings (Settings › Videos).
  Future<void> updateVideoSettings({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    double? defaultSpeed,
    bool? rewindOnResume,
    bool? directDrawing,
    PictureShape? videoShape,
    PictureShape? collectionShape,
  }) async {
    videoDirectDrawing = directDrawing ?? videoDirectDrawing;
    videoSkipBackSeconds = skipBackSeconds ?? videoSkipBackSeconds;
    videoSkipForwardSeconds = skipForwardSeconds ?? videoSkipForwardSeconds;
    defaultVideoSpeed = defaultSpeed ?? defaultVideoSpeed;
    videoRewindOnResume = rewindOnResume ?? videoRewindOnResume;
    videoPictureShape = videoShape ?? videoPictureShape;
    collectionPictureShape = collectionShape ?? collectionPictureShape;
    notifyListeners();
    await _saveSettings();
  }

  /// Changes how the video player's buttons look (Settings › Appearance › Video player).
  Future<void> setVideoPlayerLook(VideoPlayerLook look) async {
    if (look == videoPlayerLook) return;
    videoPlayerLook = look;
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

  // ---- video folders (0.1.40) ----

  /// Adds a folder for the Videos tab. VideoLibraryModel notices and scans it.
  Future<void> addVideoFolder(String path) async {
    if (videoFolders.contains(path)) return;
    videoFolders = [...videoFolders, path];
    await _saveSettings();
    _rebuild();
  }

  /// Stops listing a video folder's videos.
  Future<void> removeVideoFolder(String path) async {
    videoFolders = videoFolders.where((f) => f != path).toList();
    hiddenFormats = {...hiddenFormats}..remove(path);
    await _saveSettings();
    _rebuild();
  }

  /// A song file that's really a video in a video folder (an .mp4 on its own there).
  bool _isVideoFolderFile(Track t) {
    final path = t.path;
    if (videoFolders.isEmpty || !t.isLocal || path == null) return false;
    return videoExtensions.contains(p.extension(path).toLowerCase()) && videoFolders.any((f) => isInside(path, f));
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
    hiddenFormats = {...hiddenFormats}..remove(path);
    await _saveSettings();
    await scanLocal();
  }

  // ---- one folder's options (Settings › Folders & scanning, 0.1.27) ----

  /// File types switched off per folder: folder path → extensions, lower case without the dot
  /// ("wav"). Anything not listed shows, so a type that turns up later shows until switched off.
  Map<String, List<String>> hiddenFormats = {};

  /// "flac" for ".../song.FLAC"; "" when there's no extension.
  static String formatOf(String path) => p.extension(path).replaceFirst('.', '').toLowerCase();

  /// The folder whose options apply to a file: the innermost music or audiobook folder that
  /// holds it (an audiobook folder inside a music folder has its own options).
  String? ownerFolder(String path) {
    String? best;
    for (final f in _scanFolders) {
      if (isInside(path, f) && (best == null || splitPath(f).length > splitPath(best).length)) best = f;
    }
    return best;
  }

  bool _formatHidden(Track t) {
    final path = t.path;
    if (!t.isLocal || path == null) return false;
    final owner = ownerFolder(path);
    return owner != null && (hiddenFormats[owner]?.contains(formatOf(path)) ?? false);
  }

  /// The file types found in [folder] at the last scan (switched off ones included), with how
  /// many files of each, A–Z.
  Map<String, int> formatsIn(String folder) {
    final counts = <String, int>{};
    for (final t in _local) {
      final path = t.path;
      if (path != null && ownerFolder(path) == folder) {
        final f = formatOf(path);
        counts[f] = (counts[f] ?? 0) + 1;
      }
    }
    return {for (final k in counts.keys.toList()..sort()) k: counts[k]!};
  }

  /// Whether files of [format] in [folder] are shown.
  bool formatShown(String folder, String format) => !(hiddenFormats[folder]?.contains(format) ?? false);

  /// Switches one file type in one folder on or off. Takes effect at once (no rescan needed).
  Future<void> setFormatShown(String folder, String format, bool shown) async {
    final set = {...?hiddenFormats[folder]};
    shown ? set.remove(format) : set.add(format);
    hiddenFormats = {...hiddenFormats};
    if (set.isEmpty) {
      hiddenFormats.remove(folder);
    } else {
      hiddenFormats[folder] = set.toList()..sort();
    }
    _rebuild(); // the screens change at once; the settings file is saved after
    await _saveSettings();
  }

  /// Rescans just [folder] (its options window). Songs elsewhere are left as they are.
  Future<void> scanFolder(String folder) => _enqueue(() async {
        musicAccess = await checkAccess();
        if (musicAccess != MusicAccess.allowed) {
          error = _noAccessMessage;
          return;
        }
        if (!await folderReachable(folder)) {
          error = 'Can\'t reach $folder right now, so what was found there before is kept.';
          return;
        }
        error = null;
        final name = p.basename(folder);
        status = 'Scanning $name…';
        notifyListeners();
        _applyPendingDurations();
        try {
          final previous = {for (final t in _local) t.id: t};
          final scanned = await _scanner.scan([folder], previous: previous, onProgress: (done, total) {
            status = 'Scanning $name: $done / $total';
          });
          final found = {for (final t in scanned) t.id};
          // Everything outside the folder stays; everything inside comes from this scan.
          _local = [
            for (final t in _local)
              if (!found.contains(t.id) && !(t.path != null && isInside(t.path!, folder))) t,
            ...scanned,
          ]..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
          offlineFolders = [for (final f in offlineFolders) if (f != folder) f];
          await _reconcile(previous);
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

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
        // Lengths learned while playing go in first, so the scan keeps them.
        _applyPendingDurations();
        try {
          // Give the scanner what we already know, so unchanged files are reused, not re-read.
          final previous = {for (final t in _local) t.id: t};
          // Progress goes into statusText only (no notifyListeners), so the app isn't redrawn.
          _local = await _scanAvailable(previous, onProgress: (done, total) {
            status = 'Scanning $done / $total';
          });
          // Follow moved files and keep gone ones that matter, save, then tidy unused covers.
          await _reconcile(previous);
          await _saveLibrary();
          await _scanner.removeUnusedArt(_local);
          status = null;
          if (offlineFolders.isNotEmpty) error = _offlineMessage();
        } catch (e) {
          status = null;
          error = 'Scan failed: $e';
        }
      });

  /// Music or audiobook folders that couldn't be reached at the last scan (a drive that isn't
  /// plugged in, a network share that's asleep). Their songs are kept as they were.
  List<String> offlineFolders = [];

  /// How long to wait for a folder (e.g. a sleeping network share) before counting it offline.
  static const folderCheckTimeout = Duration(seconds: 10);

  /// Scans the folders that can be reached. Songs in folders that can't be reached are kept
  /// exactly as they were in [previous], instead of counting as gone.
  ///
  /// HomeTunes (0.1.16): before, an unplugged drive looked like an empty folder, so its songs
  /// were dropped (all but those with edits or playlist places), their cached covers deleted,
  /// and everything read again from scratch when the drive came back.
  Future<List<Track>> _scanAvailable(Map<String, Track> previous, {void Function(int done, int total)? onProgress}) async {
    final folders = _scanFolders;
    final reachable = <String>[];
    final unreachable = <String>[];
    for (final f in folders) {
      (await folderReachable(f) ? reachable : unreachable).add(f);
    }
    // A missing folder inside one that can be reached has really gone (its drive is there).
    offlineFolders = [
      for (final f in unreachable)
        if (!reachable.any((r) => isInside(f, r))) f,
    ];
    final scanned = await _scanner.scan(reachable, previous: previous, onProgress: onProgress);
    if (offlineFolders.isEmpty) return scanned;
    final found = {for (final t in scanned) t.id};
    final kept = [
      for (final t in previous.values)
        if (!found.contains(t.id) && t.path != null && offlineFolders.any((f) => isInside(t.path!, f))) t,
    ];
    // Same order as a normal scan: by path.
    return [...scanned, ...kept]..sort((a, b) => (a.path ?? '').compareTo(b.path ?? ''));
  }

  /// Whether [folder] exists and can be listed right now. For tests it can be replaced.
  Future<bool> Function(String folder) folderReachable = _canList;

  static Future<bool> _canList(String folder) async {
    try {
      final dir = Directory(folder);
      if (!await dir.exists()) return false;
      await dir.list(followLinks: false).take(1).toList().timeout(folderCheckTimeout);
      return true;
    } catch (_) {
      return false;
    }
  }

  String _offlineMessage() {
    final names = offlineFolders.join(', ');
    return offlineFolders.length == 1
        ? 'Can\'t reach $names right now, so its songs are shown as they were. '
            'If it\'s gone for good, remove it in Settings.'
        : 'Can\'t reach $names right now, so their songs are shown as they were. '
            'If they\'re gone for good, remove them in Settings.';
  }

  // ---- server ----

  /// Saves server details after checking they work. Returns an error message or null.
  ///
  /// HomeTunes (0.1.17): an address typed without http:// or https:// is tried with https://
  /// first (so the login token isn't sent in the clear when the server supports it), then
  /// http://; whichever works is saved with its scheme. The password goes into the system's
  /// protected storage rather than settings.json.
  ///
  /// HomeTunes (0.1.21, security review #4): when https doesn't answer and the address is on the
  /// internet (not the home network or Tailscale), http isn't tried on its own any more: the
  /// login would travel where others could read it. [httpConsentNeeded] comes back instead, and
  /// Settings asks; calling again with [allowPlainHttp] (the user said yes) tries http and
  /// remembers the answer for that server. An address typed with http:// is the user's choice.
  Future<String?> connectServer(ServerConfig config, {bool allowPlainHttp = false}) async {
    final typed = config.url.trim();
    final hasScheme = typed.startsWith('http://') || typed.startsWith('https://');
    final attempts = hasScheme
        ? [config]
        : [
            ServerConfig(url: 'https://$typed', username: config.username, password: config.password),
            ServerConfig(url: 'http://$typed', username: config.username, password: config.password),
          ];
    String? lastError;
    ServerConfig? working;
    for (final attempt in attempts) {
      if (!hasScheme && attempt.url.startsWith('http://') && isPlainHttpToInternet(attempt.url)) {
        final host = _hostOf(attempt.url);
        if (!allowPlainHttp && host != httpAllowedHost) return httpConsentNeeded;
      }
      // Try the details with a throwaway connection first, so bad details never get saved.
      final test = SubsonicClient(attempt);
      try {
        await test.ping();
        working = attempt;
        break;
      } on SubsonicException catch (e) {
        lastError = e.message;
        // A real answer from the server (e.g. wrong password): no point trying http as well.
        if (e.fromServer) break;
      } catch (e) {
        // e.g. an address that isn't a valid URL at all.
        lastError = 'That server address doesn\'t look right (${hideSecrets('$e')})';
      } finally {
        test.close();
      }
    }
    if (working == null) return lastError;
    if (!hasScheme && working.url.startsWith('http://') && isPlainHttpToInternet(working.url)) {
      httpAllowedHost = _hostOf(working.url);
    }
    final previous = server;
    server = working;
    serverEnabled = true;
    await _storeServerPassword(working, previous: previous);
    _rebuildClient();
    await _saveSettings();
    await syncServer();
    return null;
  }

  /// What [connectServer] returns when the server only answered over plain http on the
  /// internet, and the user hasn't agreed to that yet.
  static const httpConsentNeeded = 'HTTP_CONSENT_NEEDED';

  static String _hostOf(String url) => Uri.tryParse(url)?.host.toLowerCase() ?? '';

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
    // Its password is removed from the protected storage too.
    if (server.url.trim().isNotEmpty) {
      await secrets?.delete(SecretStore.serverPasswordKey(server.url, server.username));
    }
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    httpAllowedHost = null;
    _remote = [];
    _rebuildClient();
    await ServerArtCache.clear(_serverArtDir);
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
          error = 'Server sync failed: ${hideSecrets('$e')}';
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

  /// Records a song's real length (found while playing it).
  ///
  /// HomeTunes (0.1.16): this used to rebuild the whole library and rewrite all of library.json
  /// (megabytes for a big library) every time. Now lengths are gathered for a moment and applied
  /// in one rebuild, and library.json is saved at most every [_librarySaveDelay] (and when the
  /// app goes to the background, see [flushPendingSaves]).
  Future<void> learnDuration(String id, Duration d) async {
    _pendingDurations[id] = d;
    _durationTimer ??= Timer(_durationApplyDelay, _applyPendingDurations);
  }

  final Map<String, Duration> _pendingDurations = {};
  Timer? _durationTimer;
  Timer? _librarySaveTimer;
  static const _durationApplyDelay = Duration(seconds: 2);
  static const _librarySaveDelay = Duration(seconds: 30);

  /// Puts gathered lengths into the library (one rebuild) and schedules a save.
  void _applyPendingDurations() {
    _durationTimer?.cancel();
    _durationTimer = null;
    if (_pendingDurations.isEmpty) return;
    final learned = Map.of(_pendingDurations);
    _pendingDurations.clear();
    var changed = false;
    // Copies the list, swapping in updated copies of songs (Tracks are never changed in place).
    List<Track> update(List<Track> list) => [
          for (final t in list)
            if (learned[t.id] case final d? when d != t.duration) (() {
              changed = true;
              return t.copyWith(duration: d);
            })() else t,
        ];
    _local = update(_local);
    _remote = update(_remote);
    if (!changed) return;
    _rebuild();
    _librarySaveTimer ??= Timer(_librarySaveDelay, () {
      _librarySaveTimer = null;
      _saveLibrary();
    });
  }

  /// Applies and saves anything waiting (learned lengths). Called when the app goes to the
  /// background or closes, so nothing learned is lost.
  Future<void> flushPendingSaves() async {
    _applyPendingDurations();
    if (_librarySaveTimer != null) {
      _librarySaveTimer!.cancel();
      _librarySaveTimer = null;
      await _saveLibrary();
    }
  }

  // ---- editing song details ----

  /// The song as read from the file/server, ignoring the user's edits.
  Track? originalById(String id) => _rawById[id];

  /// The rules that decide what's an audiobook (as last applied), for "why is this a book?".
  BookRules bookRules = BookRules();

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

  /// Replaces one song's edit (the single-song editor). Lyrics and audiobook details, which
  /// that editor doesn't show, are kept from the existing edit.
  Future<void> setEdit(String id, TrackEdit edit) async {
    final original = _rawById[id];
    if (original == null) return;
    // The details editor doesn't touch lyrics: keep the song's own.
    if (edit.lyrics == null) edit = edit.withLyrics(_edits[id]?.lyrics);
    // Nor audiobook details (narrator, series, number in series): keep those too. Before 0.1.16
    // saving a book file in the song editor lost them.
    edit = edit.withBookDetailsFrom(_edits[id]);
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
    // Not used by any edit yet (the editor saves it later): protect it from the tidy-up.
    _justImported[p.normalize(dest.path)] = DateTime.now();
    // Make sure images show the new picture even if an old one was cached.
    PaintingBinding.instance.imageCache.clear();
    return dest.path;
  }

  /// Covers imported but not yet used by any edit, by path. HomeTunes (0.1.16): a cover is copied
  /// in when it's picked but only saved into an edit when the editor's Save is pressed, so any
  /// other edit saved in between used to delete it as unused. They're left alone until an edit
  /// uses them, or for at most [_importGrace].
  final Map<String, DateTime> _justImported = {};
  static const _importGrace = Duration(minutes: 30);

  /// Deletes custom covers that no edit points at any more.
  Future<void> _removeUnusedCustomArt() async {
    final dir = Directory(_customArtDir);
    if (!await dir.exists()) return;
    final now = DateTime.now();
    final inEdits = {
      for (final e in _edits.values) if (e.art != null) p.normalize(e.art!),
      // Artists' own pictures live here too (0.1.53).
      for (final v in artistPictures.values) if (!v.startsWith(artistAlbumPrefix)) p.normalize(v),
    };
    // Protection ends once an edit uses the cover (from then on the normal rule applies), or
    // after [_importGrace] if it's never used.
    _justImported.removeWhere((path, at) => inEdits.contains(path) || now.difference(at) > _importGrace);
    final used = {...inEdits, ..._justImported.keys};
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
  /// The server password is never included (0.1.21, security review #6): it would be readable
  /// by anyone with the file. After restoring on another device it's typed in once.
  Future<Uint8List> createBackup({bool includeCoverCache = true}) =>
      AppBackup.create(storage, includeCoverCache: includeCoverCache);

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
      try {
        // 1. Save everything as it is now, so a bad restore can be undone. (Without the server
        //    password since 0.1.17: it stays in protected storage, so undoing keeps it anyway.)
        final undo = await AppBackup.create(storage);
        await File(beforeRestorePath).writeAsBytes(undo, flush: true);
        // 2. Write the backup's files, then reload this model and the others from them.
        //    (AppBackup.restore throws if a file can't be saved; the error reaches the caller.)
        result = await AppBackup.restore(storage, backup, merge: merge);
        await load();
        await reloadOthers();
        // The same server's password is still in protected storage: no need to type it again.
        if (result.needsPassword && server.password.isNotEmpty) {
          result = RestoreResult(missingFolders: result.missingFolders, needsPassword: false);
        }
      } finally {
        status = null;
      }
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
        final r = await writeTagsToFile(t.path!, edit,
            backupDir: backupDir, libraryRoots: _scanFolders, artRoots: [storage.artDir]);
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
      _local = await _scanAvailable(previous);
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
      // 0.1.21: only files inside the library folders (a restored backup could name any path).
      final path = t.path;
      return path != null && isInsideAny(path, _scanFolders) && File(path).existsSync() ? path : null;
    }
    final c = _client;
    if (c == null || t.remoteId == null) return null;
    return c.streamUrl(t.remoteId!);
  }

  /// The song's music video file, if it has one that can be shown now (0.1.40): a local song,
  /// with the video still there and inside the library folders (a restored backup could name any
  /// path, as with [playableUri]).
  String? videoFileFor(Track t) {
    final v = t.video;
    if (!t.isLocal || v == null) return null;
    return isUsableLocalFile(v, roots: _scanFolders, extensions: videoExtensions) ? v : null;
  }

  /// Cover art location for the system media controls (notification, lock screen).
  ///
  /// For a server song whose cover isn't downloaded yet this returns null, starts the download,
  /// and calls [onDownloaded] once the file is there (the media session then asks again).
  Uri? artUriFor(Track t, {int size = 512, void Function()? onDownloaded}) {
    final art = t.art;
    if (art == null) return null;
    if (_artIsFile(t)) return isInsideAny(art, coverFolders) ? Uri.file(art) : null;
    // 0.1.21 (security review #2): a server cover is handed over as a file downloaded by
    // ServerArtCache, never as the server address, which carries the login token.
    final cache = _serverArt;
    if (cache == null) return null;
    final file = cache.cachedFile(art, size: size);
    if (file != null) return Uri.file(file);
    cache.fetch(art, size: size).then((got) {
      if (got != null) onDownloaded?.call();
    });
    return null;
  }

  /// The cover image to show in the app: a file on disk, or the server's cover picture.
  ImageProvider? artFor(Track? t, {int size = 512}) {
    if (t == null || t.art == null) return null;
    if (_artIsFile(t)) return isInsideAny(t.art!, coverFolders) ? FileImage(File(t.art!)) : null;
    final c = _client;
    if (c == null) return null;
    return NetworkImage(c.coverArtUrl(t.art!, size: size));
  }
}
