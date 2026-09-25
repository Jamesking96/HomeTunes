import 'package:flutter/material.dart';

/// The pages Settings is split into, in the order they're listed.
enum SettingsPage {
  library('Library', 'Music folders and rescanning', Icons.library_music_outlined),
  playback('Playback', 'Gapless playback and even volume', Icons.graphic_eq),
  sleepTimer('Sleep timer', 'Timer lengths and fading out', Icons.bedtime_outlined),
  audiobooks('Audiobooks', 'Book folders, skipping, speed and covers', Icons.menu_book_outlined),
  onlineLookups('Online lookups', 'Covers, song details and lyrics', Icons.travel_explore),
  server('Servers', 'Stream music and audiobooks from your own server', Icons.dns_outlined),
  edits('Your edits', 'Save your changes into the music files', Icons.edit_note),
  backup('Backup & restore', 'Move everything to another PC or phone', Icons.settings_backup_restore),
  about('About', 'Version and where your data is kept', Icons.info_outline);

  final String title;
  final String summary;
  final IconData icon;
  const SettingsPage(this.title, this.summary, this.icon);

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
  final SettingsPage page;
  final String title;

  /// Other words people might type to find it.
  final String words;
  const SettingInfo(this.id, this.page, this.title, [this.words = '']);
}

/// Every setting that's always shown on its page. (Settings that only appear
/// in some situations, like "Include the server password", aren't listed.)
const settingsCatalog = <SettingInfo>[
  SettingInfo('music-folders', SettingsPage.library, 'Music folders', 'add folder rescan scan location library'),
  SettingInfo('gapless', SettingsPage.playback, 'Gapless playback', 'gap silence live album mix'),
  SettingInfo('replaygain', SettingsPage.playback, 'Even out volume (ReplayGain)', 'loudness loud quiet level normalise normalize'),
  SettingInfo('sleep-button', SettingsPage.sleepTimer, 'Show sleep timer button', 'moon'),
  SettingInfo('sleep-music', SettingsPage.sleepTimer, 'Timer length for music', 'sleep minutes end of song'),
  SettingInfo('sleep-books', SettingsPage.sleepTimer, 'Timer length for books', 'sleep minutes end of chapter audiobook'),
  SettingInfo('sleep-fade', SettingsPage.sleepTimer, 'Fade out before pausing', 'sleep volume'),
  SettingInfo('book-folders', SettingsPage.audiobooks, 'Audiobook folders', 'add folder books location'),
  SettingInfo('book-genres', SettingsPage.audiobooks, 'Genres that mean "audiobook"', 'genre spoken word'),
  SettingInfo('skip-back', SettingsPage.audiobooks, 'Skip back', 'rewind seconds'),
  SettingInfo('skip-forward', SettingsPage.audiobooks, 'Skip forward', 'fast forward seconds'),
  SettingInfo('book-speed', SettingsPage.audiobooks, 'Speed for new books', 'playback speed faster slower'),
  SettingInfo('rewind-resume', SettingsPage.audiobooks, 'Rewind a little when resuming', 'resume pause'),
  SettingInfo('book-covers', SettingsPage.audiobooks, 'Book cover shape', 'square tall portrait'),
  SettingInfo('online-covers', SettingsPage.onlineLookups, 'Find missing covers online', 'album art artwork musicbrainz cover art archive'),
  SettingInfo('online-details', SettingsPage.onlineLookups, 'Find missing song details online', 'year genre track number musicbrainz tags'),
  SettingInfo('online-lyrics', SettingsPage.onlineLookups, 'Find lyrics online', 'lrclib words'),
  SettingInfo('server', SettingsPage.server, 'Music server address and sign-in', 'subsonic navidrome stream password username connect sync'),
  SettingInfo('server-books', SettingsPage.server, 'Audiobooks from the music server', 'books stream server'),
  SettingInfo('book-server', SettingsPage.server, 'Audiobook server', 'audiobookshelf books stream'),
  SettingInfo('write-tags', SettingsPage.edits, 'Save edits into music files', 'write tags metadata'),
  SettingInfo('write-backup', SettingsPage.edits, 'Back up each file first', 'copy original'),
  SettingInfo('backup-export', SettingsPage.backup, 'Export backup', 'save backup file move'),
  SettingInfo('backup-import', SettingsPage.backup, 'Import backup', 'restore backup file'),
  SettingInfo('backup-covers', SettingsPage.backup, 'Include cover images from music files', 'art backup size'),
  SettingInfo('version', SettingsPage.about, 'Version', 'app number update'),
  SettingInfo('data-folder', SettingsPage.about, 'Where HomeTunes keeps its data', 'data folder location files'),
];

/// Settings whose name, page or extra words contain every word typed.
List<SettingInfo> searchSettings(String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return const [];
  return [
    for (final s in settingsCatalog)
      if (words.every('${s.title} ${s.page.title} ${s.words}'.toLowerCase().contains)) s,
  ];
}
