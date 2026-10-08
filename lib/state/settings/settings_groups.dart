// The app's settings (settings.json), in groups (refactor phase 3, 8 Oct 2026). They used to be
// about 60 fields on LibraryModel. Each group is its own ChangeNotifier holding one part of
// Settings, and lists its settings once (setting.dart): key, default, how it's read and written.
// AppSettings holds every group and turns them into settings.json and back. LibraryModel keeps
// the same names as before (they pass through to these), so screens didn't have to change.
// The file is the same as before: test/refactor_safety_test.dart checks every key round-trips.
import 'package:flutter/foundation.dart';

import '../../models/quick_link.dart';
import '../../models/video_item.dart' show PictureShape;
import '../../models/video_player_look.dart';
import '../../models/volume_boost.dart';
import '../../services/subsonic_client.dart' show ServerConfig;
import '../../services/window_pin.dart';
import '../book_index.dart' show defaultBookGenres;
import 'setting.dart';

/// Evening out loudness between songs with ReplayGain information in the files.
enum ReplayGainMode { off, track, album }

/// One part of the settings: its fields, and [settings], the list that loads, saves and resets them.
abstract class SettingsGroup extends ChangeNotifier {
  List<Setting> get settings;

  /// Every setting back to its default.
  void reset() {
    for (final s in settings) {
      s.reset();
    }
  }

  void load(SettingsReader r) {
    for (final s in settings) {
      s.load(r);
    }
  }

  void writeTo(Map<String, dynamic> out) {
    for (final s in settings) {
      s.writeTo(out);
    }
  }

  /// Tells whoever watches this group that something in it changed.
  void changed() => notifyListeners();

  /// Saves settings.json (set by LibraryModel, which writes every group at once).
  Future<void> Function() save = () async {};

  /// The usual change: redraw first (so a switch moves at once), then save.
  @protected
  Future<void> commit() {
    notifyListeners();
    return save();
  }
}

/// Folders and what's in them: music, audiobook and video folders, file types switched off,
/// the genres that make a file an audiobook, and "Move to Books / Music" choices.
class FolderSettings extends SettingsGroup {
  /// The music folders the user picked.
  List<String> folders = [];

  /// Folders where everything is an audiobook (scanned as well as [folders]).
  List<String> audiobookFolders = [];

  /// Folders for the Videos tab (0.1.40). Scanned by VideoLibraryModel, not by the music scan.
  List<String> videoFolders = [];

  /// File types switched off per folder: folder path → extensions, lower case without the dot.
  Map<String, List<String>> hiddenFormats = {};

  /// Genres that mark a file as an audiobook.
  List<String> bookGenres = List.of(defaultBookGenres);

  /// "Move to Books" (true) / "Move to Music" (false), by track id.
  Map<String, bool> bookOverrides = {};

  @override
  late final List<Setting> settings = [
    Setting.texts('folders', const [], () => folders, (v) => folders = v),
    Setting.texts('audiobookFolders', const [], () => audiobookFolders, (v) => audiobookFolders = v),
    Setting.texts('videoFolders', const [], () => videoFolders, (v) => videoFolders = v),
    Setting.texts('bookGenres', defaultBookGenres, () => bookGenres, (v) => bookGenres = v),
    Setting<Map<String, List<String>>>(
      'hiddenFormats',
      fallback: () => {},
      get: () => hiddenFormats,
      set: (v) => hiddenFormats = v,
      writeIf: (v) => v.isNotEmpty,
      read: (r) {
        final hidden = r['hiddenFormats'];
        if (hidden is! Map) return {};
        return {
          for (final e in hidden.entries)
            if (e.value is List)
              '${e.key}': [for (final f in e.value as List) if (f is String && f.isNotEmpty) f.toLowerCase()],
        }..removeWhere((_, v) => v.isEmpty);
      },
    ),
    Setting<Map<String, bool>>(
      'bookOverrides',
      fallback: () => {},
      get: () => bookOverrides,
      set: (v) => bookOverrides = v,
      read: (r) {
        final o = r['bookOverrides'];
        return o is Map ? {for (final e in o.entries) '${e.key}': e.value == true} : {};
      },
    ),
  ];
}

/// The music server: its address and login, the on / off switch, a host allowed over plain http,
/// and whether its audiobooks show.
class ServerSettings extends SettingsGroup {
  /// The Subsonic server's address and login.
  ServerConfig server = const ServerConfig(url: '', username: '', password: '');

  /// The server switch in Settings → Servers. Its songs are kept while off, just hidden.
  bool serverEnabled = false;

  /// A host the user agreed to use over plain http (0.1.21, security review #4).
  String? httpAllowedHost;

  /// Audiobooks on the music server show in the Books tab (Settings › Servers).
  bool serverBooks = true;

  /// True while the password has to stay in settings.json (no protected storage on this device,
  /// or saving it there failed), so it isn't lost. Not saved itself.
  bool passwordInSettings = false;

  @override
  late final List<Setting> settings = [
    Setting<ServerConfig>(
      'server',
      fallback: () => const ServerConfig(url: '', username: '', password: ''),
      get: () => server,
      set: (v) => server = v,
      // The password only goes in here when it can't be kept in protected storage (0.1.17).
      write: (v) => passwordInSettings ? v.toJson() : v.toJsonWithoutPassword(),
      read: (r) {
        final sv = r['server'];
        if (sv is Map<String, dynamic>) {
          try {
            return ServerConfig.fromJson(sv);
          } catch (_) {
            r.damaged = true;
          }
        }
        return const ServerConfig(url: '', username: '', password: '');
      },
    ),
    Setting.flag('serverEnabled', false, () => serverEnabled, (v) => serverEnabled = v),
    Setting<String?>(
      'httpAllowedHost',
      fallback: () => null,
      get: () => httpAllowedHost,
      set: (v) => httpAllowedHost = v,
      writeIf: (v) => v != null,
      read: (r) {
        final allowed = r['httpAllowedHost'];
        return allowed is String && allowed.isNotEmpty ? allowed : null;
      },
    ),
    Setting.flag('serverBooks', true, () => serverBooks, (v) => serverBooks = v),
  ];
}

/// Settings › Online lookups.
class OnlineSettings extends SettingsGroup {
  /// Offer to look up missing cover art online (MusicBrainz / Cover Art Archive).
  bool onlineCovers = true;

  /// Offer to look up missing song details (year, artist, genre…) on MusicBrainz.
  bool onlineDetails = true;

  /// Look up lyrics on LRCLIB when a song has none of its own.
  bool onlineLyrics = true;

  /// Offer "Search online" for video pictures and collection posters (0.1.40).
  bool onlineVideoArt = true;

  @override
  late final List<Setting> settings = [
    Setting.flag('onlineCovers', true, () => onlineCovers, (v) => onlineCovers = v),
    Setting.flag('onlineDetails', true, () => onlineDetails, (v) => onlineDetails = v),
    Setting.flag('onlineLyrics', true, () => onlineLyrics, (v) => onlineLyrics = v),
    Setting.flag('onlineVideoArt', true, () => onlineVideoArt, (v) => onlineVideoArt = v),
  ];

  // The simple on/off settings redraw first (so the switch moves at once), then save.
  Future<void> setOnlineCovers(bool on) {
    onlineCovers = on;
    return commit();
  }

  Future<void> setOnlineDetails(bool on) {
    onlineDetails = on;
    return commit();
  }

  Future<void> setOnlineLyrics(bool on) {
    onlineLyrics = on;
    return commit();
  }

  Future<void> setOnlineVideoArt(bool on) {
    onlineVideoArt = on;
    return commit();
  }
}

/// Settings › Playback and Settings › Music, plus the PC's always-on-top pin.
class PlaybackSettings extends SettingsGroup {
  /// Load the next song ahead so it follows with no gap.
  bool gaplessPlayback = true;

  /// Even out volume using ReplayGain info in the files (off / by song / by album).
  ReplayGainMode replayGain = ReplayGainMode.off;

  /// Swipe the player left or right (touch screens) to skip (0.1.17).
  bool swipeToSkip = true;

  /// PC: the window stays on top of other windows (0.1.60).
  bool alwaysOnTop = false;

  /// Volume boost (0.1.61 / 0.1.62): the volume sliders go up to [volumeBoostPercent] while on.
  bool volumeBoost = false;
  int volumeBoostPercent = 100;

  /// A small "65%" bubble above a volume slider while it's being changed (0.1.65).
  bool showVolumePercent = true;

  /// Now Playing can show a song's music video in place of its cover (0.1.40).
  bool showMusicVideos = true;

  /// The music video starts by itself when a song with one plays.
  bool autoPlayMusicVideos = true;

  @override
  late final List<Setting> settings = [
    Setting.flag('gaplessPlayback', true, () => gaplessPlayback, (v) => gaplessPlayback = v),
    Setting<ReplayGainMode>(
      'replayGain',
      fallback: () => ReplayGainMode.off,
      get: () => replayGain,
      set: (v) => replayGain = v,
      write: (v) => v.name,
      read: (r) => ReplayGainMode.values.asNameMap()[r['replayGain']] ?? ReplayGainMode.off,
    ),
    Setting.flag('swipeToSkip', true, () => swipeToSkip, (v) => swipeToSkip = v),
    Setting.flag('alwaysOnTop', false, () => alwaysOnTop, (v) => alwaysOnTop = v),
    Setting.flag('volumeBoost', false, () => volumeBoost, (v) => volumeBoost = v),
    Setting.whole('volumeBoostPercent', 100, () => volumeBoostPercent, (v) => volumeBoostPercent = v,
        min: volumeBoostMin, max: volumeBoostMax),
    Setting.flag('showVolumePercent', true, () => showVolumePercent, (v) => showVolumePercent = v),
    Setting.flag('showMusicVideos', true, () => showMusicVideos, (v) => showMusicVideos = v),
    Setting.flag('autoPlayMusicVideos', true, () => autoPlayMusicVideos, (v) => autoPlayMusicVideos = v),
  ];

  /// Changes the playback settings (Settings > Playback).
  Future<void> update({
    bool? gaplessPlayback,
    ReplayGainMode? replayGain,
    bool? swipeToSkip,
    bool? showMusicVideos,
    bool? autoPlayMusicVideos,
  }) {
    this.gaplessPlayback = gaplessPlayback ?? this.gaplessPlayback;
    this.replayGain = replayGain ?? this.replayGain;
    this.swipeToSkip = swipeToSkip ?? this.swipeToSkip;
    this.showMusicVideos = showMusicVideos ?? this.showMusicVideos;
    this.autoPlayMusicVideos = autoPlayMusicVideos ?? this.autoPlayMusicVideos;
    return commit();
  }

  /// Volume boost on / off and how far the volume sliders go (100–500 %, 0.1.61 / 0.1.62). A
  /// volume above the new top is brought down to it by the players.
  Future<void> setVolumeBoost({bool? on, int? percent}) {
    if (on != null) volumeBoost = on;
    if (percent != null) volumeBoostPercent = percent.clamp(volumeBoostMin, volumeBoostMax).toInt();
    return commit();
  }

  /// The volume percentage bubble on or off (0.1.65).
  Future<void> setShowVolumePercent(bool on) {
    showVolumePercent = on;
    return commit();
  }

  /// PC: keep the window on top of other windows, or not (0.1.60, the pin button).
  Future<void> setAlwaysOnTop(bool on) async {
    alwaysOnTop = on;
    notifyListeners();
    await WindowPin.set(on);
    await save();
  }
}

/// Settings › Audiobooks and Settings › Sleep timer.
class ListeningSettings extends SettingsGroup {
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

  /// Sleep timer lengths in minutes; 0 or less means "end of chapter / song / video".
  int sleepBookMinutes = 30;
  int sleepMusicMinutes = 30;
  int sleepVideoMinutes = 30;

  /// Fade the volume out over this many seconds before the timer pauses (0 = off).
  int sleepFadeSeconds = 10;

  @override
  late final List<Setting> settings = [
    Setting.flag('bookCoversTall', false, () => bookCoversTall, (v) => bookCoversTall = v),
    Setting.whole('skipBackSeconds', 15, () => skipBackSeconds, (v) => skipBackSeconds = v),
    Setting.whole('skipForwardSeconds', 30, () => skipForwardSeconds, (v) => skipForwardSeconds = v),
    Setting.flag('rewindOnResume', true, () => rewindOnResume, (v) => rewindOnResume = v),
    Setting.decimal('defaultBookSpeed', 1.0, () => defaultBookSpeed, (v) => defaultBookSpeed = v),
    Setting.flag('sleepButtonShown', true, () => sleepButtonShown, (v) => sleepButtonShown = v),
    Setting.whole('sleepBookMinutes', 30, () => sleepBookMinutes, (v) => sleepBookMinutes = v),
    Setting.whole('sleepMusicMinutes', 30, () => sleepMusicMinutes, (v) => sleepMusicMinutes = v),
    Setting.whole('sleepVideoMinutes', 30, () => sleepVideoMinutes, (v) => sleepVideoMinutes = v),
    Setting.whole('sleepFadeSeconds', 10, () => sleepFadeSeconds, (v) => sleepFadeSeconds = v),
  ];

  /// Changes any of the listening settings (Settings > Audiobooks) and sleep timer settings
  /// (Settings > Sleep timer).
  Future<void> update({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    bool? rewindOnResume,
    double? defaultBookSpeed,
    bool? sleepButtonShown,
    int? sleepBookMinutes,
    int? sleepMusicMinutes,
    int? sleepVideoMinutes,
    int? sleepFadeSeconds,
  }) {
    this.sleepVideoMinutes = sleepVideoMinutes ?? this.sleepVideoMinutes;
    this.skipBackSeconds = skipBackSeconds ?? this.skipBackSeconds;
    this.skipForwardSeconds = skipForwardSeconds ?? this.skipForwardSeconds;
    this.rewindOnResume = rewindOnResume ?? this.rewindOnResume;
    this.defaultBookSpeed = defaultBookSpeed ?? this.defaultBookSpeed;
    this.sleepButtonShown = sleepButtonShown ?? this.sleepButtonShown;
    this.sleepBookMinutes = sleepBookMinutes ?? this.sleepBookMinutes;
    this.sleepMusicMinutes = sleepMusicMinutes ?? this.sleepMusicMinutes;
    this.sleepFadeSeconds = sleepFadeSeconds ?? this.sleepFadeSeconds;
    return commit();
  }

  /// Book covers tall or square (saved first, then redrawn, as before).
  Future<void> setBookCoversTall(bool tall) async {
    bookCoversTall = tall;
    await save();
    notifyListeners();
  }
}

/// Settings › Videos (0.1.40).
class VideoSettings extends SettingsGroup {
  /// Titles offered when marking a video season as special (0.1.66).
  static const defaultSpecialSeasonTitles = ['Specials', 'OVA', 'Movies', 'Bonus episodes'];
  List<String> specialSeasonTitles = List.of(defaultSpecialSeasonTitles);

  /// Skip buttons (and ← → keys) while a video plays (seconds).
  int videoSkipBackSeconds = 10;
  int videoSkipForwardSeconds = 10;

  /// Speed for collections that haven't had one chosen (each remembers its own).
  double defaultVideoSpeed = 1.0;

  /// Go back a few seconds when carrying on with a video.
  bool videoRewindOnResume = true;

  /// Phone: videos are drawn straight from the video chip (0.1.57, services/video_drawing.dart).
  bool videoDirectDrawing = true;

  /// The usual picture shape for videos and for collections (each can have its own).
  PictureShape videoPictureShape = PictureShape.wide;
  PictureShape collectionPictureShape = PictureShape.wide;

  static Setting<PictureShape> _shape(String key, PictureShape Function() get, void Function(PictureShape) set) =>
      Setting<PictureShape>(key,
          fallback: () => PictureShape.wide,
          get: get,
          set: set,
          write: (v) => v.name,
          read: (r) => PictureShape.byName(r[key]) ?? PictureShape.wide);

  @override
  late final List<Setting> settings = [
    Setting.texts('specialSeasonTitles', defaultSpecialSeasonTitles, () => specialSeasonTitles, (v) => specialSeasonTitles = v),
    Setting.whole('videoSkipBackSeconds', 10, () => videoSkipBackSeconds, (v) => videoSkipBackSeconds = v),
    Setting.whole('videoSkipForwardSeconds', 10, () => videoSkipForwardSeconds, (v) => videoSkipForwardSeconds = v),
    Setting.decimal('defaultVideoSpeed', 1.0, () => defaultVideoSpeed, (v) => defaultVideoSpeed = v),
    Setting.flag('videoRewindOnResume', true, () => videoRewindOnResume, (v) => videoRewindOnResume = v),
    Setting.flag('videoDirectDrawing', true, () => videoDirectDrawing, (v) => videoDirectDrawing = v),
    _shape('videoPictureShape', () => videoPictureShape, (v) => videoPictureShape = v),
    _shape('collectionPictureShape', () => collectionPictureShape, (v) => collectionPictureShape = v),
  ];

  /// Changes any of the video settings (Settings › Videos).
  Future<void> update({
    int? skipBackSeconds,
    int? skipForwardSeconds,
    double? defaultSpeed,
    bool? rewindOnResume,
    bool? directDrawing,
    PictureShape? videoShape,
    PictureShape? collectionShape,
  }) {
    videoDirectDrawing = directDrawing ?? videoDirectDrawing;
    videoSkipBackSeconds = skipBackSeconds ?? videoSkipBackSeconds;
    videoSkipForwardSeconds = skipForwardSeconds ?? videoSkipForwardSeconds;
    defaultVideoSpeed = defaultSpeed ?? defaultVideoSpeed;
    videoRewindOnResume = rewindOnResume ?? videoRewindOnResume;
    videoPictureShape = videoShape ?? videoPictureShape;
    collectionPictureShape = collectionShape ?? collectionPictureShape;
    return commit();
  }

  /// The titles offered for special seasons (0.1.66): blank ones and repeats (any case) dropped,
  /// order kept.
  Future<void> setSpecialSeasonTitles(List<String> titles) {
    final seen = <String>{};
    specialSeasonTitles = [
      for (final t in titles)
        if (t.trim().isNotEmpty && seen.add(t.trim().toLowerCase())) t.trim(),
    ];
    return commit();
  }

  /// Adds a title to the special season list if it isn't there yet (typed in the Mark as special
  /// box, so it's offered next time).
  Future<void> addSpecialSeasonTitle(String title) => setSpecialSeasonTitles([...specialSeasonTitles, title]);
}

/// Settings › Appearance: colour themes, text size, corners, the video player's look, and
/// shrinking to fit small windows.
class AppearanceSettings extends SettingsGroup {
  /// The colour theme, and "Your own" colours ("#RRGGBB"). See LibraryModel.setTheme.
  String themeId = 'default';
  String? customAccent;
  String? customBackground;

  /// The user's saved themes (0.1.25), as saved (each a map of id, name and colours).
  List<Map<String, dynamic>> savedThemes = [];

  /// Text size (a multiple of the system size) and how rounded corners are (0 = square).
  double textSize = 1.0;
  double cornerRoundness = 1.0;

  /// How the video player's buttons look (Settings › Appearance › Video player).
  VideoPlayerLook videoPlayerLook = VideoPlayerLook.standard;

  /// On a computer, buttons and text get a little smaller when the window is small (0.1.41).
  bool scaleWithWindow = true;

  /// "#RRGGBB".
  static final hexColour = RegExp(r'^#[0-9A-Fa-f]{6}$');

  static Setting<String?> _colour(String key, String? Function() get, void Function(String?) set) =>
      Setting<String?>(key, fallback: () => null, get: get, set: set, writeIf: (v) => v != null, read: (r) {
        final c = r[key];
        return c is String && hexColour.hasMatch(c) ? c.toUpperCase() : null;
      });

  @override
  late final List<Setting> settings = [
    Setting<String>('theme', fallback: () => 'default', get: () => themeId, set: (v) => themeId = v, read: (r) {
      final theme = r['theme'];
      return theme is String && theme.isNotEmpty ? theme : 'default';
    }),
    _colour('customAccent', () => customAccent, (v) => customAccent = v),
    _colour('customBackground', () => customBackground, (v) => customBackground = v),
    Setting<List<Map<String, dynamic>>>(
      'savedThemes',
      fallback: () => [],
      get: () => savedThemes,
      set: (v) => savedThemes = v,
      writeIf: (v) => v.isNotEmpty,
      read: (r) {
        final saved = r['savedThemes'];
        return saved is List ? [for (final t in saved) if (t is Map && t['id'] is String) Map<String, dynamic>.from(t)] : [];
      },
    ),
    Setting.decimal('textSize', 1.0, () => textSize, (v) => textSize = v, min: 0.8, max: 1.5),
    Setting.decimal('cornerRoundness', 1.0, () => cornerRoundness, (v) => cornerRoundness = v, min: 0.0, max: 2.0),
    Setting<VideoPlayerLook>('videoPlayerLook',
        fallback: () => VideoPlayerLook.standard,
        get: () => videoPlayerLook,
        set: (v) => videoPlayerLook = v,
        write: (v) => v.toJson(),
        read: (r) => VideoPlayerLook.fromJson(r['videoPlayerLook'])),
    Setting.flag('scaleWithWindow', true, () => scaleWithWindow, (v) => scaleWithWindow = v),
  ];

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
    await commit();
  }

  /// "Your own" back to its starting colours (the Default theme's highlight and background).
  /// Returns what it had, as (accent, background), so the change can be undone.
  Future<(String?, String?)> resetCustomColours() async {
    final before = (customAccent, customBackground);
    customAccent = null;
    customBackground = null;
    await commit();
    return before;
  }

  /// Puts "Your own" colours back after [resetCustomColours] (Undo).
  Future<void> restoreCustomColours((String?, String?) colours) {
    customAccent = colours.$1;
    customBackground = colours.$2;
    return commit();
  }

  /// Removes a saved theme; if it was in use, goes back to Default.
  Future<void> deleteTheme(String id) {
    savedThemes = [for (final t in savedThemes) if (t['id'] != id) t];
    if (themeId == id) themeId = 'default';
    return commit();
  }

  /// Text size and corner roundness (Settings › Appearance › Advanced).
  Future<void> setLook({double? textSize, double? cornerRoundness}) {
    this.textSize = (textSize ?? this.textSize).clamp(0.8, 1.5).toDouble();
    this.cornerRoundness = (cornerRoundness ?? this.cornerRoundness).clamp(0.0, 2.0).toDouble();
    return commit();
  }

  /// Settings › Appearance (0.1.24): which colour theme ('default', 'midnight', 'forest' or
  /// 'custom'), and the two colours of "Your own" as "#RRGGBB" (null = not chosen yet). Kept as
  /// text here; ui/theme.dart turns them into colours.
  Future<void> setTheme({String? id, String? accent, String? background}) {
    themeId = id ?? themeId;
    if (accent != null && hexColour.hasMatch(accent)) customAccent = accent.toUpperCase();
    if (background != null && hexColour.hasMatch(background)) customBackground = background.toUpperCase();
    return commit();
  }

  /// Settings › Appearance › Shrink to fit small windows.
  Future<void> setScaleWithWindow(bool on) {
    scaleWithWindow = on;
    return commit();
  }

  /// Changes how the video player's buttons look (Settings › Appearance › Video player).
  Future<void> setVideoPlayerLook(VideoPlayerLook look) async {
    if (look == videoPlayerLook) return;
    videoPlayerLook = look;
    await commit();
  }
}

/// How the library is laid out on the computer: the sidebar (width, folded, quick links), the
/// Artists tab's grid, and pictures chosen for artists and series.
class LayoutSettings extends SettingsGroup {
  /// Your Library › Artists shows round pictures in a grid instead of a list (0.1.52).
  bool artistsGrid = false;

  /// The computer's left-hand sidebar (1 Oct): how wide it's been dragged, and whether it's folded.
  static const sidebarMinWidth = 180.0, sidebarMaxWidth = 420.0;
  double sidebarWidth = 250;
  bool sidebarFolded = false;

  /// The sidebar's quick links (0.1.64), in the order added.
  List<QuickLink> quickLinks = [];

  /// Pictures chosen for artists (0.1.53), by artist name: a file in art/custom, or "album:"
  /// plus an album key.
  Map<String, String> artistPictures = {};

  /// Audiobook series' own details (0.1.76), by series name: 'description' and 'picture'.
  Map<String, Map<String, String>> seriesInfo = {};

  @override
  late final List<Setting> settings = [
    Setting.flag('artistsGrid', false, () => artistsGrid, (v) => artistsGrid = v),
    Setting<Map<String, String>>(
      'artistPictures',
      fallback: () => {},
      get: () => artistPictures,
      set: (v) => artistPictures = v,
      writeIf: (v) => v.isNotEmpty,
      read: (r) {
        final pics = r['artistPictures'];
        if (pics is! Map) return {};
        return {
          for (final e in pics.entries)
            if (e.key is String && e.value is String) e.key as String: e.value as String
        };
      },
    ),
    Setting<Map<String, Map<String, String>>>(
      'seriesInfo',
      fallback: () => {},
      get: () => seriesInfo,
      set: (v) => seriesInfo = v,
      writeIf: (v) => v.isNotEmpty,
      read: (r) {
        final series = r['seriesInfo'];
        if (series is! Map) return {};
        return {
          for (final e in series.entries)
            if (e.key is String && e.value is Map)
              e.key as String: {
                for (final f in (e.value as Map).entries)
                  if (f.key is String && f.value is String) f.key as String: f.value as String
              }
        };
      },
    ),
    Setting<List<QuickLink>>(
      'quickLinks',
      fallback: () => [],
      get: () => quickLinks,
      set: (v) => quickLinks = v,
      writeIf: (v) => v.isNotEmpty,
      write: (v) => [for (final l in v) l.toJson()],
      read: (r) {
        final links = r['quickLinks'];
        return links is List ? [for (final j in links) ?QuickLink.fromJson(j)] : [];
      },
    ),
    Setting.decimal('sidebarWidth', 250, () => sidebarWidth, (v) => sidebarWidth = v, min: sidebarMinWidth, max: sidebarMaxWidth),
    Setting.flag('sidebarFolded', false, () => sidebarFolded, (v) => sidebarFolded = v),
  ];

  /// The sidebar's width (kept between [sidebarMinWidth] and [sidebarMaxWidth]) and folded state.
  Future<void> setSidebar({double? width, bool? folded}) {
    if (width != null) sidebarWidth = width.clamp(sidebarMinWidth, sidebarMaxWidth).toDouble();
    if (folded != null) sidebarFolded = folded;
    return commit();
  }

  /// Your Library › Artists: grid (true) or list (false) (0.1.52).
  Future<void> setArtistsGrid(bool on) {
    artistsGrid = on;
    return commit();
  }

  /// Whether this album / artist / book / collection / video is a quick link in the sidebar.
  bool isQuickLink(QuickLinkKind kind, String id) => quickLinks.any((l) => l.sameAs(kind, id));

  /// Adds a quick link at the end of the sidebar's list (0.1.64); one per item.
  Future<void> addQuickLink(QuickLink link) async {
    if (isQuickLink(link.kind, link.id)) return;
    quickLinks = [...quickLinks, link];
    await commit();
  }

  /// Takes a quick link off the sidebar.
  Future<void> removeQuickLink(QuickLinkKind kind, String id) async {
    final before = quickLinks.length;
    quickLinks = [for (final l in quickLinks) if (!l.sameAs(kind, id)) l];
    if (quickLinks.length == before) return;
    await commit();
  }

  /// Adds it if it isn't there, takes it off if it is (the menus' "Add to / Remove from sidebar").
  Future<void> toggleQuickLink(QuickLink link) =>
      isQuickLink(link.kind, link.id) ? removeQuickLink(link.kind, link.id) : addQuickLink(link);
}

/// Every settings group, and settings.json made from them and read back into them.
class AppSettings {
  final folders = FolderSettings();
  final server = ServerSettings();
  final online = OnlineSettings();
  final playback = PlaybackSettings();
  final listening = ListeningSettings();
  final video = VideoSettings();
  final appearance = AppearanceSettings();
  final layout = LayoutSettings();

  List<SettingsGroup> get groups => [folders, server, online, playback, listening, video, appearance, layout];

  /// Every setting back to its default (so reloading after a restore doesn't keep old values).
  void reset() {
    for (final g in groups) {
      g.reset();
    }
  }

  /// Reads settings.json's contents (after [reset]); returns true when something in it had the
  /// wrong type (a copy of the file is then kept).
  bool load(Map<String, dynamic> raw) {
    final r = SettingsReader(raw);
    for (final g in groups) {
      g.load(r);
    }
    return r.damaged;
  }

  /// What settings.json holds.
  Map<String, dynamic> toJson() {
    final out = <String, dynamic>{};
    for (final g in groups) {
      g.writeTo(out);
    }
    return out;
  }

  /// Tells every group's watchers that settings may have changed (after a load or restore).
  void changedAll() {
    for (final g in groups) {
      g.changed();
    }
  }
}
