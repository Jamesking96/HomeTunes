// The list of Settings pages, and the index that Settings search looks through.
//
// SettingsScreen uses [SettingsPage] to draw its list of pages, and [searchSettings] for the
// search box. Each [SettingInfo] id must match a SettingTarget on that page so a search result
// can scroll to it; test/settings_test.dart checks this. When you add a setting, add it here.
import 'package:flutter/material.dart';

/// The pages Settings is split into, in the order they're listed: alphabetical by title (the
/// user's choice, 29 Sep; test/settings_test.dart checks it stays that way). The code names stay
/// as they were (`library` is shown as "Folders & scanning") so links from other screens and
/// saved searches keep working.
enum SettingsPage {
  about('About', 'Version, updates and where your data is kept', Icons.info_outline),
  appearance('Appearance', 'Colour themes, text size, corners and the video player', Icons.palette_outlined),
  audiobooks('Audiobooks', 'Book folders, skipping, speed and covers', Icons.menu_book_outlined),
  backup('Backup & restore', 'Move everything to another PC or phone', Icons.settings_backup_restore),
  library('Folders & scanning', 'Music and audiobook folders, and rescanning', Icons.folder_outlined),
  music('Music', 'Listening to music: music videos', Icons.music_note_outlined),
  onlineLookups('Online lookups', 'Covers, song details and lyrics', Icons.travel_explore),
  playback('Playback', 'Equaliser, gapless playback and even volume', Icons.graphic_eq),
  server('Servers', 'Stream music, audiobooks and videos from your own servers', Icons.dns_outlined),
  sleepTimer('Sleep timer', 'Timer lengths and fading out', Icons.bedtime_outlined),
  videos('Videos', 'Skipping, speed, equaliser, video folders and picture shapes', Icons.movie_outlined),
  edits('Your edits', 'Save your changes into the music files', Icons.edit_note);

  /// Name shown in the list and as the page heading.
  final String title;
  /// One-line description under the title in the list.
  final String summary;
  final IconData icon;
  const SettingsPage(this.title, this.summary, this.icon);

  /// Looks a page up by its code name (e.g. 'library'), as sent by AppNav.openSettings.
  /// Null if there's no such page.
  static SettingsPage? byName(String name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// One setting that search can find. [id] matches a [SettingTarget] on its page.
class SettingInfo {
  final String id;
  /// The page the setting lives on.
  final SettingsPage page;
  /// The setting's name as shown in the search results.
  final String title;

  /// Other words people might type to find it.
  final String words;
  const SettingInfo(this.id, this.page, this.title, [this.words = '']);
}

/// Every setting that's always shown on its page. (Settings that only appear
/// in some situations aren't listed.)
const settingsCatalog = <SettingInfo>[
  SettingInfo('music-folders', SettingsPage.library, 'Music folders', 'add folder rescan scan location library'),
  SettingInfo('library-book-folders', SettingsPage.library, 'Audiobook folders', 'add folder books location scan rescan library'),
  SettingInfo('library-video-folders', SettingsPage.library, 'Video folders', 'add folder videos films movies mp4 mkv location scan rescan folder options file types formats'),
  SettingInfo('gapless', SettingsPage.playback, 'Gapless playback', 'gap silence live album mix'),
  SettingInfo('equaliser', SettingsPage.playback, 'Equaliser', 'equalizer eq bass treble presets sound tone'),
  SettingInfo('swipe-to-skip', SettingsPage.playback, 'Swipe gestures', 'swipe gesture next previous song audiobook phone touch'),
  SettingInfo('music-videos', SettingsPage.music, 'Show music videos', 'music video mp4 film clip picture now playing cover youtube'),
  SettingInfo('music-video-autoplay', SettingsPage.music, 'Play music videos automatically',
      'music video auto play autoplay start automatically cover button'),
  SettingInfo('recently-played', SettingsPage.playback, 'Forget recently played music', 'history recent jump back in home clear played'),
  SettingInfo('volume-boost', SettingsPage.playback, 'Volume boost',
      'louder loud amplify boost 200 300 400 500 percent vlc quiet volume'),
  SettingInfo('replaygain', SettingsPage.playback, 'Even out volume (ReplayGain)', 'loudness loud quiet level normalise normalize'),
  SettingInfo('sleep-button', SettingsPage.sleepTimer, 'Show sleep timer button', 'moon'),
  SettingInfo('sleep-music', SettingsPage.sleepTimer, 'Timer length for music', 'sleep minutes end of song'),
  SettingInfo('sleep-books', SettingsPage.sleepTimer, 'Timer length for books', 'sleep minutes end of chapter audiobook'),
  SettingInfo('sleep-videos', SettingsPage.sleepTimer, 'Timer length for videos', 'sleep minutes end of video film episode'),
  SettingInfo('sleep-fade', SettingsPage.sleepTimer, 'Fade out before pausing', 'sleep volume'),
  SettingInfo('book-folders', SettingsPage.audiobooks, 'Audiobook folders', 'add folder books location'),
  SettingInfo('book-genres', SettingsPage.audiobooks, 'Genres that mean "audiobook"', 'genre spoken word'),
  SettingInfo('skip-back', SettingsPage.audiobooks, 'Skip back', 'rewind seconds'),
  SettingInfo('skip-forward', SettingsPage.audiobooks, 'Skip forward', 'fast forward seconds'),
  SettingInfo('book-speed', SettingsPage.audiobooks, 'Speed for new books', 'playback speed faster slower'),
  SettingInfo('rewind-resume', SettingsPage.audiobooks, 'Rewind a little when resuming', 'resume pause'),
  SettingInfo('book-eq', SettingsPage.audiobooks, 'Separate equaliser for audiobooks', 'equalizer eq spoken word sound'),
  SettingInfo('book-covers', SettingsPage.audiobooks, 'Book cover shape', 'square tall portrait'),
  SettingInfo('online-covers', SettingsPage.onlineLookups, 'Find missing covers online', 'album art artwork musicbrainz cover art archive'),
  SettingInfo('online-details', SettingsPage.onlineLookups, 'Find missing song details online', 'year genre track number musicbrainz tags'),
  SettingInfo('online-lyrics', SettingsPage.onlineLookups, 'Find lyrics online', 'lrclib words'),
  SettingInfo('online-video-art', SettingsPage.onlineLookups, 'Find video pictures online',
      'poster thumbnail tvmaze anilist wikipedia videos collection'),
  SettingInfo('video-skip-back', SettingsPage.videos, 'Skip back (videos)', 'rewind seconds video keys'),
  SettingInfo('video-skip-forward', SettingsPage.videos, 'Skip forward (videos)', 'fast forward seconds video keys'),
  SettingInfo('video-speed', SettingsPage.videos, 'Video speed', 'playback speed faster slower videos'),
  SettingInfo('video-rewind', SettingsPage.videos, 'Rewind a little when carrying on', 'resume videos'),
  SettingInfo('video-direct', SettingsPage.videos, 'Smoother video on phones',
      'stutter lag laggy choppy smooth hardware video chip drawing black picture videos'),
  SettingInfo('video-eq', SettingsPage.videos, 'Separate equaliser for videos', 'equalizer eq sound videos'),
  SettingInfo('video-folders', SettingsPage.videos, 'Video folders', 'add folder videos films movies location folder options rescan file types formats'),
  SettingInfo('video-nfo', SettingsPage.videos, 'Save edits into .nfo files', 'nfo kodi jellyfin plex details videos'),
  SettingInfo('video-shape', SettingsPage.videos, 'Video picture shape', 'look tall square wide thumbnail videos'),
  SettingInfo('collection-shape', SettingsPage.videos, 'Collection poster shape', 'look tall square wide poster collections'),
  SettingInfo('add-server', SettingsPage.server, 'Add a server', 'new connection jellyfin plex emby audiobookshelf hometunes test'),
  SettingInfo('server', SettingsPage.server, 'Music servers', 'subsonic navidrome stream password username connect sync main'),
  SettingInfo('server-books', SettingsPage.server, 'Audiobook servers', 'audiobooks from the music server books stream audiobookshelf'),
  SettingInfo('video-server', SettingsPage.server, 'Video servers', 'videos films movies tv stream'),
  SettingInfo('write-tags', SettingsPage.edits, 'Save edits into music files', 'write tags metadata'),
  SettingInfo('write-backup', SettingsPage.edits, 'Back up each file first', 'copy original'),
  SettingInfo('backup-export', SettingsPage.backup, 'Export backup', 'save backup file move'),
  SettingInfo('backup-import', SettingsPage.backup, 'Import backup', 'restore backup file'),
  SettingInfo('backup-covers', SettingsPage.backup, 'Include cover images from music files', 'art backup size'),
  SettingInfo('theme', SettingsPage.appearance, 'Colour theme', 'color colour colours theme dark look style midnight forest default'),
  SettingInfo('theme-custom', SettingsPage.appearance, 'Your own colours', 'custom color colour highlight accent background theme create hex code share'),
  SettingInfo('theme-advanced', SettingsPage.appearance, 'Advanced themes',
      'every colour color light theme saved new edit text panels play button hex code share export import friend file'),
  SettingInfo('text-size', SettingsPage.appearance, 'Text size', 'font bigger smaller larger read'),
  SettingInfo('corners', SettingsPage.appearance, 'Corners', 'rounded round square shape'),
  SettingInfo('scale-with-window', SettingsPage.appearance, 'Shrink to fit small windows',
      'scale scaling zoom window size small smaller resize buttons widgets fit'),
  SettingInfo('video-player-preview', SettingsPage.appearance, 'Video player look', 'video player controls buttons appearance theme preview'),
  SettingInfo('video-button-colour', SettingsPage.appearance, 'Video player button colour', 'video controls buttons colour color icons'),
  SettingInfo('video-button-size', SettingsPage.appearance, 'Video player button size', 'video controls buttons size bigger smaller'),
  SettingInfo('video-button-backing', SettingsPage.appearance, 'Behind the video player buttons', 'video controls buttons hard to see black dark bright contrast shadow glow circles readable visible'),
  SettingInfo('video-seek-colour', SettingsPage.appearance, 'Video progress bar colour', 'video seek bar progress colour color timeline'),
  SettingInfo('version', SettingsPage.about, 'Version', 'app number'),
  SettingInfo('updates', SettingsPage.about, 'Check for updates', 'update upgrade new version download install latest release'),
  SettingInfo('update-auto', SettingsPage.about, 'Check for updates automatically', 'update start open startup notify new version'),
  SettingInfo('whats-new', SettingsPage.about, 'What\'s new in this version', 'changes release notes changelog latest new features'),
  SettingInfo('playback-log', SettingsPage.about, 'Playback log', 'diagnostics problem stops stopped debug report'),
  SettingInfo('licences', SettingsPage.about, 'Licences',
      'licence license mit open source copyright legal third party lgpl mpv ffmpeg credits'),
  SettingInfo('data-folder', SettingsPage.about, 'Where HomeTunes keeps its data', 'data folder location files'),
];

/// Settings whose name, page or extra words contain every word typed.
List<SettingInfo> searchSettings(String query) {
  // Split what was typed into lower-case words; an empty box gives no results (not all of them).
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    // Every word must appear somewhere (in any order), and part-words count: "gap" finds
    // "Gapless".
    for (final s in settingsCatalog)
      if (words.every('${s.title} ${s.page.title} ${s.words}'.toLowerCase().contains)) s,
  ];
}
