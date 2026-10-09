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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import '../models/quick_link.dart';
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
import '../services/storage.dart';
import '../services/subsonic_client.dart';
import '../services/tag_writer.dart';
import '../services/track_matching.dart';
import '../services/window_pin.dart';
import 'book_index.dart';
import 'custom_art_store.dart';
import 'library_index.dart' as index;
import 'media_folders.dart';
import 'server_connection.dart';
import 'settings/settings_groups.dart';

export 'settings/settings_groups.dart' show ReplayGainMode;
// What writing edits into files reports, for Settings › Your edits (refactor phase 7: screens don't
// import the tag writer itself).
export '../services/tag_writer.dart' show TagWriteResult;

/// Where a picture comes from: a file on disk, or (for the server's covers) its address. The
/// screens turn it into an image (ui/widgets/library_images.dart, refactor phase 3).
typedef PictureSource = ({String? file, String? url});

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
    // Refactor phase 3: each settings group saves settings.json through here, and a change in a
    // group redraws whatever watches LibraryModel, as when the settings lived here.
    for (final g in settings.groups) {
      g.save = _saveSettings;
      g.addListener(_onSettingsChanged);
    }
  }

  // Off while load() tells the groups' own watchers about the settings it read (LibraryModel
  // redraws once at the end of load anyway).
  bool _quietSettings = false;
  void _onSettingsChanged() {
    if (!_quietSettings) notifyListeners();
  }

  // ---- settings ----
  // Every setting lives in [settings] (state/settings/settings_groups.dart: one group per part of
  // Settings, each setting described once), and is saved in settings.json by _saveSettings and
  // read back in load. Refactor phase 3 (8 Oct 2026): the names below are kept and pass straight
  // through, so screens and tests didn't have to change.
  final AppSettings settings = AppSettings();

  // Folders (FolderSettings).
  List<String> get folders => settings.folders.folders;
  set folders(List<String> v) => settings.folders.folders = v;
  List<String> get audiobookFolders => settings.folders.audiobookFolders;
  set audiobookFolders(List<String> v) => settings.folders.audiobookFolders = v;
  List<String> get videoFolders => settings.folders.videoFolders;
  set videoFolders(List<String> v) => settings.folders.videoFolders = v;
  List<String> get bookGenres => settings.folders.bookGenres;
  set bookGenres(List<String> v) => settings.folders.bookGenres = v;
  Map<String, List<String>> get hiddenFormats => settings.folders.hiddenFormats;
  set hiddenFormats(Map<String, List<String>> v) => settings.folders.hiddenFormats = v;
  Map<String, bool> get _kindOverrides => settings.folders.bookOverrides;

  // The server (ServerSettings).
  ServerConfig get server => settings.server.server;
  set server(ServerConfig v) => settings.server.server = v;
  bool get serverEnabled => settings.server.serverEnabled;
  set serverEnabled(bool v) => settings.server.serverEnabled = v;
  /// The server address (host, lower case) the user agreed may be reached over plain http even
  /// though it's on the internet (0.1.21, security review #4). Null when they haven't.
  String? get httpAllowedHost => settings.server.httpAllowedHost;
  set httpAllowedHost(String? v) => settings.server.httpAllowedHost = v;
  bool get serverBooks => settings.server.serverBooks;
  set serverBooks(bool v) => settings.server.serverBooks = v;

  // Online lookups (OnlineSettings).
  bool get onlineCovers => settings.online.onlineCovers;
  set onlineCovers(bool v) => settings.online.onlineCovers = v;
  bool get onlineDetails => settings.online.onlineDetails;
  set onlineDetails(bool v) => settings.online.onlineDetails = v;
  bool get onlineLyrics => settings.online.onlineLyrics;
  set onlineLyrics(bool v) => settings.online.onlineLyrics = v;
  bool get onlineVideoArt => settings.online.onlineVideoArt;
  set onlineVideoArt(bool v) => settings.online.onlineVideoArt = v;

  // Playback (PlaybackSettings).
  bool get gaplessPlayback => settings.playback.gaplessPlayback;
  set gaplessPlayback(bool v) => settings.playback.gaplessPlayback = v;
  ReplayGainMode get replayGain => settings.playback.replayGain;
  set replayGain(ReplayGainMode v) => settings.playback.replayGain = v;
  bool get swipeToSkip => settings.playback.swipeToSkip;
  set swipeToSkip(bool v) => settings.playback.swipeToSkip = v;
  bool get alwaysOnTop => settings.playback.alwaysOnTop;
  set alwaysOnTop(bool v) => settings.playback.alwaysOnTop = v;
  bool get volumeBoost => settings.playback.volumeBoost;
  set volumeBoost(bool v) => settings.playback.volumeBoost = v;
  int get volumeBoostPercent => settings.playback.volumeBoostPercent;
  set volumeBoostPercent(int v) => settings.playback.volumeBoostPercent = v;
  bool get showVolumePercent => settings.playback.showVolumePercent;
  set showVolumePercent(bool v) => settings.playback.showVolumePercent = v;
  bool get showMusicVideos => settings.playback.showMusicVideos;
  set showMusicVideos(bool v) => settings.playback.showMusicVideos = v;
  bool get autoPlayMusicVideos => settings.playback.autoPlayMusicVideos;
  set autoPlayMusicVideos(bool v) => settings.playback.autoPlayMusicVideos = v;

  /// The top of every volume slider: 100, or the boost's percentage while it's on.
  double get maxVolume => maxVolumeFor(on: volumeBoost, percent: volumeBoostPercent);

  // Audiobooks and the sleep timer (ListeningSettings).
  bool get bookCoversTall => settings.listening.bookCoversTall;
  set bookCoversTall(bool v) => settings.listening.bookCoversTall = v;
  int get skipBackSeconds => settings.listening.skipBackSeconds;
  set skipBackSeconds(int v) => settings.listening.skipBackSeconds = v;
  int get skipForwardSeconds => settings.listening.skipForwardSeconds;
  set skipForwardSeconds(int v) => settings.listening.skipForwardSeconds = v;
  bool get rewindOnResume => settings.listening.rewindOnResume;
  set rewindOnResume(bool v) => settings.listening.rewindOnResume = v;
  double get defaultBookSpeed => settings.listening.defaultBookSpeed;
  set defaultBookSpeed(double v) => settings.listening.defaultBookSpeed = v;
  bool get sleepButtonShown => settings.listening.sleepButtonShown;
  set sleepButtonShown(bool v) => settings.listening.sleepButtonShown = v;
  int get sleepBookMinutes => settings.listening.sleepBookMinutes;
  set sleepBookMinutes(int v) => settings.listening.sleepBookMinutes = v;
  int get sleepMusicMinutes => settings.listening.sleepMusicMinutes;
  set sleepMusicMinutes(int v) => settings.listening.sleepMusicMinutes = v;
  int get sleepVideoMinutes => settings.listening.sleepVideoMinutes;
  set sleepVideoMinutes(int v) => settings.listening.sleepVideoMinutes = v;
  int get sleepFadeSeconds => settings.listening.sleepFadeSeconds;
  set sleepFadeSeconds(int v) => settings.listening.sleepFadeSeconds = v;
  // (The sleep timer treats any length of 0 or less the same way.)
  static const sleepAtEnd = -1;

  // Videos (VideoSettings).
  static const defaultSpecialSeasonTitles = VideoSettings.defaultSpecialSeasonTitles;
  List<String> get specialSeasonTitles => settings.video.specialSeasonTitles;
  set specialSeasonTitles(List<String> v) => settings.video.specialSeasonTitles = v;
  int get videoSkipBackSeconds => settings.video.videoSkipBackSeconds;
  set videoSkipBackSeconds(int v) => settings.video.videoSkipBackSeconds = v;
  int get videoSkipForwardSeconds => settings.video.videoSkipForwardSeconds;
  set videoSkipForwardSeconds(int v) => settings.video.videoSkipForwardSeconds = v;
  double get defaultVideoSpeed => settings.video.defaultVideoSpeed;
  set defaultVideoSpeed(double v) => settings.video.defaultVideoSpeed = v;
  bool get videoRewindOnResume => settings.video.videoRewindOnResume;
  set videoRewindOnResume(bool v) => settings.video.videoRewindOnResume = v;
  bool get videoDirectDrawing => settings.video.videoDirectDrawing;
  set videoDirectDrawing(bool v) => settings.video.videoDirectDrawing = v;
  PictureShape get videoPictureShape => settings.video.videoPictureShape;
  set videoPictureShape(PictureShape v) => settings.video.videoPictureShape = v;
  PictureShape get collectionPictureShape => settings.video.collectionPictureShape;
  set collectionPictureShape(PictureShape v) => settings.video.collectionPictureShape = v;

  // Appearance (AppearanceSettings).
  String get themeId => settings.appearance.themeId;
  set themeId(String v) => settings.appearance.themeId = v;
  String? get customAccent => settings.appearance.customAccent;
  set customAccent(String? v) => settings.appearance.customAccent = v;
  String? get customBackground => settings.appearance.customBackground;
  set customBackground(String? v) => settings.appearance.customBackground = v;
  List<Map<String, dynamic>> get savedThemes => settings.appearance.savedThemes;
  set savedThemes(List<Map<String, dynamic>> v) => settings.appearance.savedThemes = v;
  double get textSize => settings.appearance.textSize;
  set textSize(double v) => settings.appearance.textSize = v;
  double get cornerRoundness => settings.appearance.cornerRoundness;
  set cornerRoundness(double v) => settings.appearance.cornerRoundness = v;
  VideoPlayerLook get videoPlayerLook => settings.appearance.videoPlayerLook;
  set videoPlayerLook(VideoPlayerLook v) => settings.appearance.videoPlayerLook = v;
  bool get scaleWithWindow => settings.appearance.scaleWithWindow;
  set scaleWithWindow(bool v) => settings.appearance.scaleWithWindow = v;

  // Layout (LayoutSettings).
  bool get artistsGrid => settings.layout.artistsGrid;
  set artistsGrid(bool v) => settings.layout.artistsGrid = v;
  static const sidebarMinWidth = LayoutSettings.sidebarMinWidth, sidebarMaxWidth = LayoutSettings.sidebarMaxWidth;
  double get sidebarWidth => settings.layout.sidebarWidth;
  set sidebarWidth(double v) => settings.layout.sidebarWidth = v;
  bool get sidebarFolded => settings.layout.sidebarFolded;
  set sidebarFolded(bool v) => settings.layout.sidebarFolded = v;
  List<QuickLink> get quickLinks => settings.layout.quickLinks;
  set quickLinks(List<QuickLink> v) => settings.layout.quickLinks = v;
  Map<String, String> get artistPictures => settings.layout.artistPictures;
  set artistPictures(Map<String, String> v) => settings.layout.artistPictures = v;
  static const artistAlbumPrefix = 'album:';
  Map<String, Map<String, String>> get seriesInfo => settings.layout.seriesInfo;
  set seriesInfo(Map<String, Map<String, String>> v) => settings.layout.seriesInfo = v;
  static const seriesBookPrefix = 'book:';
  /// The connection to the music server: its password, the client and its covers
  /// (state/server_connection.dart, refactor phase 3).
  late final ServerConnection connection = ServerConnection(settings.server, secrets: secrets, artDir: storage.artDir);

  // The connection to the server, or null when there's no server or it's switched off.
  SubsonicClient? get _client => connection.client;
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
    settings.reset();
    _edits = {};
    _local = [];
    _remote = [];
    _missing = [];
    // 1. Settings. Each value falls back to its default if it's missing (e.g. a setting added
    //    in a newer version than the one that wrote the file) or has the wrong type.
    //    HomeTunes: a wrong type used to throw here, before the first screen, so the app
    //    wouldn't start. Now that one value falls back, and a copy of the file is kept.
    //    (Refactor phase 3: each setting's key, default and checks are in settings_groups.dart.)
    final raw = await storage.read('settings.json');
    var settingsDamaged = raw != null && raw is! Map<String, dynamic>;
    if (raw is Map<String, dynamic>) settingsDamaged = settings.load(raw);
    if (settingsDamaged) await storage.keepCopy('settings.json');
    // The pin (0.1.60): put the window back on top if it was left that way.
    unawaited(WindowPin.set(alwaysOnTop));
    // The server password lives in the system's protected storage (0.1.17). A plain-text one in
    // settings.json (an older version, or a restored backup that included it) is moved there,
    // and settings.json is saved again without it.
    final movedPassword = await connection.loadPassword();
    connection.reconnect();
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
    _quietSettings = true;
    settings.changedAll();
    _quietSettings = false;
    _rebuild();
    if (movedPassword) await _saveSettings();
  }

  // The server password: kept in the protected storage by ServerConnection (loadPassword /
  // storePassword); settings.json holds it only when that isn't possible.
  /// Writes every setting to settings.json.
  Future<void> _saveSettings() => storage.write('settings.json', settings.toJson());

  /// Adds a saved theme, or replaces the one with the same id (Settings › Appearance ›
  /// Advanced). [use] switches to it.
  Future<void> saveTheme(Map<String, dynamic> theme, {bool use = true}) => settings.appearance.saveTheme(theme, use: use);

  /// "Your own" back to its starting colours (the Default theme's highlight and background).
  /// Returns what it had, as (accent, background), so the change can be undone.
  Future<(String?, String?)> resetCustomColours() => settings.appearance.resetCustomColours();

  /// Puts "Your own" colours back after [resetCustomColours] (Undo).
  Future<void> restoreCustomColours((String?, String?) colours) => settings.appearance.restoreCustomColours(colours);

  /// Removes a saved theme; if it was in use, goes back to Default.
  Future<void> deleteTheme(String id) => settings.appearance.deleteTheme(id);

  /// Text size and corner roundness (Settings › Appearance › Advanced).
  Future<void> setLook({double? textSize, double? cornerRoundness}) =>
      settings.appearance.setLook(textSize: textSize, cornerRoundness: cornerRoundness);


  /// Settings › Appearance (0.1.24): which colour theme ('default', 'midnight', 'forest' or
  /// 'custom'), and the two colours of "Your own" as "#RRGGBB" (null = not chosen yet). Kept as
  /// text here; ui/theme.dart turns them into colours.
  Future<void> setTheme({String? id, String? accent, String? background}) =>
      settings.appearance.setTheme(id: id, accent: accent, background: background);

  // The simple on/off settings redraw first (so the switch moves at once), then save.
  Future<void> setOnlineDetails(bool on) => settings.online.setOnlineDetails(on);

  Future<void> setOnlineLyrics(bool on) => settings.online.setOnlineLyrics(on);

  Future<void> setOnlineVideoArt(bool on) => settings.online.setOnlineVideoArt(on);

  /// Shows or leaves out the audiobooks found on the music server.
  Future<void> setServerBooks(bool on) async {
    serverBooks = on;
    // Changes which files go on the Books tab, so everything has to be rebuilt.
    _rebuild();
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setOnlineCovers(bool on) => settings.online.setOnlineCovers(on);

  /// Writes the scanned/synced songs (and the missing ones being kept) to library.json.
  Future<void> _saveLibrary() => storage.write('library.json', {
        'local': [for (final t in _local) t.toJson()],
        'remote': [for (final t in _remote) t.toJson()],
        'missing': [for (final t in _missing) t.toJson()],
      });

  /// Makes a fresh server connection from the current settings (or none).
  void _rebuildClient() => connection.reconnect();
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

  /// The titles offered for special seasons (0.1.66): blank ones and repeats (any case) dropped,
  /// order kept.
  Future<void> setSpecialSeasonTitles(List<String> titles) => settings.video.setSpecialSeasonTitles(titles);

  /// Adds a title to the special season list if it isn't there yet (typed in the Mark as special
  /// box, so it's offered next time).
  Future<void> addSpecialSeasonTitle(String title) => settings.video.addSpecialSeasonTitle(title);

  Future<void> setBookCoversTall(bool tall) => settings.listening.setBookCoversTall(tall);

  /// The sidebar's width (kept between [sidebarMinWidth] and [sidebarMaxWidth]) and folded state.
  Future<void> setSidebar({double? width, bool? folded}) => settings.layout.setSidebar(width: width, folded: folded);

  /// Volume boost on / off and how far the volume sliders go (100–500 %, 0.1.61 / 0.1.62). A
  /// volume above the new top is brought down to it by the players.
  Future<void> setVolumeBoost({bool? on, int? percent}) => settings.playback.setVolumeBoost(on: on, percent: percent);

  /// The volume percentage bubble on or off (0.1.65).
  Future<void> setShowVolumePercent(bool on) => settings.playback.setShowVolumePercent(on);

  /// PC: keep the window on top of other windows, or not (0.1.60, the pin button).
  Future<void> setAlwaysOnTop(bool on) => settings.playback.setAlwaysOnTop(on);

  /// Whether this album / artist / book / collection / video is a quick link in the sidebar.
  bool isQuickLink(QuickLinkKind kind, String id) => settings.layout.isQuickLink(kind, id);

  /// Adds a quick link at the end of the sidebar's list (0.1.64); one per item.
  Future<void> addQuickLink(QuickLink link) => settings.layout.addQuickLink(link);

  /// Takes a quick link off the sidebar.
  Future<void> removeQuickLink(QuickLinkKind kind, String id) => settings.layout.removeQuickLink(kind, id);

  /// Adds it if it isn't there, takes it off if it is (the menus' "Add to / Remove from sidebar").
  Future<void> toggleQuickLink(QuickLink link) => settings.layout.toggleQuickLink(link);

  /// Your Library › Artists: grid (true) or list (false) (0.1.52).
  Future<void> setArtistsGrid(bool on) => settings.layout.setArtistsGrid(on);

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

  /// Where the picture to draw for an artist comes from: their own file, the chosen album cover,
  /// or the first album's cover (the screens use LibraryImages.artistImage).
  PictureSource? artistSource(Artist a, {int size = 512}) {
    final file = artistPictureFile(a);
    if (file != null) return (file: file, url: null);
    return coverSource(artistAlbumArt(a), size: size);
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
    picturesChanged();
    notifyListeners();
    await _saveSettings();
    await _removeUnusedCustomArt();
  }

  // ---- audiobook series (0.1.76, Edit series) ----

  /// The series' own description, if one was written.
  String? seriesDescription(String name) => seriesInfo[name]?['description'];

  /// Whether a picture was chosen for the series.
  bool hasSeriesPicture(String name) => seriesInfo[name]?['picture'] != null;

  /// The series' own picture file (Choose an image file…), if it's still in HomeTunes' art
  /// folder; else null.
  String? seriesPictureFile(String name) {
    final pick = seriesInfo[name]?['picture'];
    if (pick == null || pick.startsWith(seriesBookPrefix)) return null;
    return isInsideAny(pick, [storage.artDir]) ? pick : null;
  }

  /// The book whose cover the series shows: the one picked, else its first book with a cover.
  Book seriesCoverBook(BookSeries s) {
    final pick = seriesInfo[s.name]?['picture'];
    if (pick != null && pick.startsWith(seriesBookPrefix)) {
      final id = pick.substring(seriesBookPrefix.length);
      final b = s.books.where((b) => b.id == id).firstOrNull;
      if (b != null) return b;
    }
    return s.coverBook;
  }

  void _setSeriesField(String name, String key, String? value) {
    final m = {...?seriesInfo[name]};
    if (value == null || value.isEmpty) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    if (m.isEmpty) {
      seriesInfo.remove(name);
    } else {
      seriesInfo[name] = m;
    }
  }

  /// Sets a series' picture: [file] (already copied in with [importCover]), or [book] (one of
  /// its books' covers), or neither to go back to the first book's cover.
  Future<void> setSeriesPicture(String name, {String? file, Book? book}) async {
    _setSeriesField(name, 'picture', file ?? (book == null ? null : '$seriesBookPrefix${book.id}'));
    picturesChanged();
    notifyListeners();
    await _saveSettings();
    await _removeUnusedCustomArt();
  }

  /// Sets (or with null or "", removes) a series' description.
  Future<void> setSeriesDescription(String name, String? text) async {
    _setSeriesField(name, 'description', text?.trim());
    notifyListeners();
    await _saveSettings();
  }

  /// Changes a whole series at once, saved as edits on its books' files (the files themselves
  /// aren't changed, like Edit book / Edit collection):
  ///  * [name]: renames the series on every book; its description, picture and sidebar link
  ///    follow (its favourite is PlaylistsModel.renameFavouriteSeries);
  ///  * [author]: the author of every book;
  ///  * [order]: the books in a new order, numbered 1, 2, 3…;
  ///  * [add]: books to put in the series, numbered after the last one;
  ///  * [remove]: books to take out (no series and no number).
  Future<void> editSeries(
    BookSeries s, {
    String? name,
    String? author,
    List<Book>? order,
    List<Book> add = const [],
    List<Book> remove = const [],
  }) async {
    final to = (name == null || name.trim().isEmpty) ? s.name : name.trim();
    final who = (author == null || author.trim().isEmpty) ? null : author.trim();
    final out = {for (final b in remove) b.id};
    final kept = [for (final b in order ?? s.books) if (!out.contains(b.id)) b];
    final keptIds = {for (final b in kept) b.id};
    final adding = [for (final b in add) if (!out.contains(b.id) && keptIds.add(b.id)) b];

    // 1. Each book's new series, number and author (only what changes).
    final changes = <String, TrackEdit>{};
    void change(Book b, {double? number}) {
      final e = TrackEdit(
        series: b.series != to ? to : null,
        seriesIndex: number != null && number != b.seriesIndex ? number : null,
        artist: who != null && who != b.author ? who : null,
        albumArtist: who != null && who != b.author ? who : null,
      );
      if (e.isEmpty) return;
      for (final t in b.parts) {
        changes[t.id] = e;
      }
    }

    for (final (i, b) in kept.indexed) {
      change(b, number: order == null ? null : (i + 1).toDouble());
    }
    var last = order != null
        ? kept.length.toDouble()
        : kept.fold<double>(0, (m, b) => (b.seriesIndex ?? 0) > m ? b.seriesIndex! : m);
    for (final b in adding) {
      change(b, number: ++last);
    }
    for (final b in remove) {
      for (final t in b.parts) {
        changes[t.id] = const TrackEdit(series: '', cleared: {'seriesIndex'});
      }
    }

    // 2. A new name: the series' details and its sidebar link come along.
    if (to != s.name) {
      final info = seriesInfo.remove(s.name);
      if (info != null) seriesInfo[to] = {...?seriesInfo[to], ...info};
      final had = isQuickLink(QuickLinkKind.series, s.name);
      quickLinks = [
        for (final l in quickLinks)
          if (!l.sameAs(QuickLinkKind.series, s.name) && !(had && l.sameAs(QuickLinkKind.series, to))) l
          else if (l.sameAs(QuickLinkKind.series, s.name)) QuickLink(QuickLinkKind.series, to, to)
      ];
      await _saveSettings();
    }
    if (changes.isNotEmpty) {
      await editTracks(changes);
    } else {
      notifyListeners();
    }
  }

  /// Settings › Appearance › Shrink to fit small windows.
  Future<void> setScaleWithWindow(bool on) => settings.appearance.setScaleWithWindow(on);

  /// Changes the playback settings (Settings > Playback).
  Future<void> updatePlaybackSettings({
    bool? gaplessPlayback,
    ReplayGainMode? replayGain,
    bool? swipeToSkip,
    bool? showMusicVideos,
    bool? autoPlayMusicVideos,
  }) =>
      settings.playback.update(
        gaplessPlayback: gaplessPlayback,
        replayGain: replayGain,
        swipeToSkip: swipeToSkip,
        showMusicVideos: showMusicVideos,
        autoPlayMusicVideos: autoPlayMusicVideos,
      );

  /// Changes any of the listening settings (Settings > Audiobooks) and sleep timer settings (Settings > Sleep timer).
  Future<void> updateListeningSettings({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    bool? rewindOnResume,
    double? defaultBookSpeed,
    bool? sleepButtonShown,
    int? sleepBookMinutes,
    int? sleepMusicMinutes,
    int? sleepVideoMinutes,
    int? sleepFadeSeconds,
  }) =>
      settings.listening.update(
        skipBackSeconds: skipBackSeconds,
        skipForwardSeconds: skipForwardSeconds,
        rewindOnResume: rewindOnResume,
        defaultBookSpeed: defaultBookSpeed,
        sleepButtonShown: sleepButtonShown,
        sleepBookMinutes: sleepBookMinutes,
        sleepMusicMinutes: sleepMusicMinutes,
        sleepVideoMinutes: sleepVideoMinutes,
        sleepFadeSeconds: sleepFadeSeconds,
      );

  /// Changes any of the video settings (Settings › Videos).
  Future<void> updateVideoSettings({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    double? defaultSpeed,
    bool? rewindOnResume,
    bool? directDrawing,
    PictureShape? videoShape,
    PictureShape? collectionShape,
  }) =>
      settings.video.update(
        skipBackSeconds: skipBackSeconds,
        skipForwardSeconds: skipForwardSeconds,
        defaultSpeed: defaultSpeed,
        rewindOnResume: rewindOnResume,
        directDrawing: directDrawing,
        videoShape: videoShape,
        collectionShape: collectionShape,
      );

  /// Changes how the video player's buttons look (Settings › Appearance › Video player).
  Future<void> setVideoPlayerLook(VideoPlayerLook look) => settings.appearance.setVideoPlayerLook(look);

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

  // File types switched off per folder (folder path → extensions, lower case without the dot,
  // "wav"): [hiddenFormats], with the folders above. Anything not listed shows, so a type that
  // turns up later shows until switched off.

  /// "flac" for ".../song.FLAC"; "" when there's no extension.
  static String formatOf(String path) => fileFormatOf(path);

  /// The folder whose options apply to a file: the innermost music or audiobook folder that
  /// holds it (an audiobook folder inside a music folder has its own options).
  String? ownerFolder(String path) => owningFolder(path, _scanFolders);

  bool _formatHidden(Track t) {
    final path = t.path;
    if (!t.isLocal || path == null) return false;
    final owner = ownerFolder(path);
    return owner != null && (hiddenFormats[owner]?.contains(formatOf(path)) ?? false);
  }

  /// The file types found in [folder] at the last scan (switched off ones included), with how
  /// many files of each, A–Z.
  Map<String, int> formatsIn(String folder) =>
      formatCounts([for (final t in _local) ?t.path], folder, _scanFolders);

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
  static const folderCheckTimeout = Duration(seconds: 10); // the same as media_folders.dart's

  /// Scans the folders that can be reached. Songs in folders that can't be reached are kept
  /// exactly as they were in [previous], instead of counting as gone.
  ///
  /// HomeTunes (0.1.16): before, an unplugged drive looked like an empty folder, so its songs
  /// were dropped (all but those with edits or playlist places), their cached covers deleted,
  /// and everything read again from scratch when the drive came back.
  Future<List<Track>> _scanAvailable(Map<String, Track> previous, {void Function(int done, int total)? onProgress}) async {
    // A missing folder inside one that can be reached has really gone (its drive is there).
    final (:reachable, :offline) = await checkFolders(_scanFolders, folderReachable);
    offlineFolders = offline;
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
  Future<bool> Function(String folder) folderReachable = canListFolder;

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
    final (:working, :error) = await connection.connectionTo(config, allowPlainHttp: allowPlainHttp);
    if (working == null) return error;
    if (ServerConnection.needsHttpAllowance(config.url, working)) {
      httpAllowedHost = ServerConnection.hostOf(working.url);
    }
    final previous = server;
    server = working;
    serverEnabled = true;
    await connection.storePassword(working, previous: previous);
    _rebuildClient();
    await _saveSettings();
    await syncServer();
    return null;
  }
  /// What [connectServer] returns when the server only answered over plain http on the
  /// internet, and the user hasn't agreed to that yet.
  static const httpConsentNeeded = ServerConnection.httpConsentNeeded;

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
    await connection.forgetPassword();
    server = const ServerConfig(url: '', username: '', password: '');
    serverEnabled = false;
    httpAllowedHost = null;
    _remote = [];
    _rebuildClient();
    await connection.clearArtCache();
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
  late final CustomArtStore _customArt = CustomArtStore(_customArtDir, protectNew: true);

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
    // Named after a fingerprint (md5) of its contents, so the same picture is stored once. Not
    // used by any edit yet (the editor saves it later), so it's kept from the tidy-up for a while.
    final path = await _customArt.store(bytes, ext);
    // Make sure images show the new picture even if an old one was cached.
    picturesChanged();
    return path;
  }

  // Covers imported but not yet used by any edit are kept from the tidy-up for a while
  // (HomeTunes 0.1.16; CustomArtStore.protectNew).
  /// Deletes custom covers that no edit points at any more.
  Future<void> _removeUnusedCustomArt() => _customArt.removeUnused({
        for (final e in _edits.values) if (e.art != null) e.art!,
        // Artists' own pictures live here too (0.1.53), and series' (0.1.76).
        for (final v in artistPictures.values) if (!v.startsWith(artistAlbumPrefix)) v,
        for (final i in seriesInfo.values)
          if (i['picture'] case final v? when !v.startsWith(seriesBookPrefix)) v,
      });
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
    final cache = connection.art;
    if (cache == null) return null;
    final file = cache.cachedFile(art, size: size);
    if (file != null) return Uri.file(file);
    cache.fetch(art, size: size).then((got) {
      if (got != null) onDownloaded?.call();
    });
    return null;
  }

  /// Where the cover to show in the app comes from: a file on disk, or the server's cover picture
  /// (the screens use LibraryImages.artFor).
  PictureSource? coverSource(Track? t, {int size = 512}) {
    if (t == null || t.art == null) return null;
    if (_artIsFile(t)) return isInsideAny(t.art!, coverFolders) ? (file: t.art!, url: null) : null;
    final c = _client;
    if (c == null) return null;
    return (file: null, url: c.coverArtUrl(t.art!, size: size));
  }}
