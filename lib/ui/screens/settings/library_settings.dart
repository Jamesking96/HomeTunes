// Settings › Folders & scanning (called "Library" before 0.1.26; its code name is still
// `library`): the music folders and the audiobook folders HomeTunes reads, the Rescan button
// (which scans both), the video folders for the Videos tab (0.1.40, scanned separately with
// their own Rescan), and the list of "missing" songs (known songs whose files have gone).
//
// Also home to [pickFolderWithPermission] and [AudiobookFoldersSection], which the Audiobooks
// page shows too (the same setting in both places, as the user asked on 29 Sep). On Android the
// app must have "Music and audio" access before a folder is added, otherwise the scan would
// find nothing and wipe the library (see 03_FEATURES_AND_DESIGN_NOTES, Android fixes).
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/music_permission.dart';
import '../../../state/library_model.dart';
import '../../../state/video_library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';


/// Asks for permission to read audio files (Android), then lets the user pick a folder.
Future<String?> pickFolderWithPermission(BuildContext context, String title) async {
  final messenger = ScaffoldMessenger.of(context);
  final lib = context.read<LibraryModel>();
  final access = await MusicPermission.request();
  // Let the library (and the "no access" banner) know the answer. No rescan here, because the
  // caller is about to add a folder, which scans anyway.
  await lib.refreshMusicAccess(rescanIfNewlyAllowed: false);
  if (access != MusicAccess.allowed) {
    messenger.showSnackBar(const SnackBar(
      content: Text('HomeTunes needs "Music and audio" access to read your music and audiobooks.'),
      action: SnackBarAction(label: 'Open settings', onPressed: MusicPermission.openSettings),
      duration: Duration(seconds: 8),
    ));
    return null;
  }
  return FilePicker.getDirectoryPath(dialogTitle: title);
}

/// The small options button on each folder row (0.1.27): opens [showFolderOptions].
class FolderOptionsButton extends StatelessWidget {
  final String folder;

  /// A video folder (0.1.40): its videos are rescanned and counted by VideoLibraryModel.
  final bool videos;
  const FolderOptionsButton({super.key, required this.folder, this.videos = false});

  @override
  Widget build(BuildContext context) => IconButton(
        key: ValueKey('folder-options:$folder'),
        tooltip: 'Folder options',
        icon: const Icon(Icons.tune),
        onPressed: () => showFolderOptions(context, folder, videos: videos),
      );
}

/// A folder's options window: rescan just this folder, and choose which file types found in
/// it are included (all are, until switched off). Music, audiobook and video folders alike.
Future<void> showFolderOptions(BuildContext context, String folder, {bool videos = false}) =>
    showDialog<void>(context: context, builder: (_) => _FolderOptions(folder: folder, videos: videos));

class _FolderOptions extends StatelessWidget {
  final String folder;
  final bool videos;
  const _FolderOptions({required this.folder, this.videos = false});

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final video = videos ? context.watch<VideoLibraryModel>() : null;
    final formats = video?.formatsIn(folder) ?? lib.formatsIn(folder);
    final hidden = [for (final f in formats.keys) if (!lib.formatShown(folder, f)) f];
    final isBooks = lib.audiobookFolders.contains(folder) && !lib.folders.contains(folder);
    final what = videos ? 'videos' : (isBooks ? 'audiobook files' : 'songs');
    final busy = video?.busy ?? lib.busy;
    String label(String f) => f.isEmpty ? '(no extension)' : f.toUpperCase();
    final summary = formats.isEmpty
        ? 'None found yet'
        : hidden.isEmpty
            ? 'All ${formats.length} included'
            : '${formats.length - hidden.length} of ${formats.length} included · ${hidden.map(label).join(', ')} left out';

    return AlertDialog(
      title: const Text('Folder options'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(folder, style: TextStyle(color: AppColors.textDim, fontSize: 13)),
            const SizedBox(height: 12),
            // 1. Rescan just this folder.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh),
              title: const Text('Rescan this folder'),
              subtitle: video != null
                  ? Text(video.busy
                      ? (video.status ?? 'Working…')
                      : 'Looks for new, changed and removed $what in this folder only')
                  : ValueListenableBuilder<String?>(
                      valueListenable: lib.statusText,
                      builder: (_, status, _) => Text(
                          lib.busy ? (status ?? 'Working…') : 'Looks for new, changed and removed $what in this folder only'),
                    ),
              trailing: FilledButton(
                key: const ValueKey('rescan-folder'),
                onPressed: busy ? null : () => video != null ? video.scanFolder(folder) : lib.scanFolder(folder),
                child: const Text('Rescan'),
              ),
            ),
            const Divider(),
            // 2. Which file types to include: a drop-down list with a tick box for each.
            Theme(
              // No divider lines around the drop-down.
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const ValueKey('format-filter'),
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.filter_list),
                title: const Text('File types'),
                subtitle: Text(summary),
                children: [
                  if (formats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Rescan the folder to see which file types it has.',
                          style: TextStyle(color: AppColors.textDim)),
                    ),
                  for (final e in formats.entries)
                    CheckboxListTile(
                      key: ValueKey('format:${e.key}'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(label(e.key)),
                      subtitle: Text(videos
                          ? '${e.value} video${e.value == 1 ? '' : 's'}'
                          : '${e.value} file${e.value == 1 ? '' : 's'}'),
                      value: lib.formatShown(folder, e.key),
                      onChanged: (on) => lib.setFormatShown(folder, e.key, on ?? true),
                    ),
                  if (formats.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        videos
                            ? 'Unticked types are left out of the Videos tab straight away. Nothing is deleted, '
                                'and ticking them again brings them back with their places and edits.'
                            : 'Unticked types are left out of your library straight away. Nothing is deleted, '
                                'and ticking them again brings them back.',
                        style: TextStyle(color: AppColors.textDim, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }
}

/// The audiobook folders list with its Add button and book count. Shown on both Settings ›
/// Folders & scanning and Settings › Audiobooks; it's one setting.
class AudiobookFoldersSection extends StatelessWidget {
  /// Show the bold "Audiobook folders" heading (the Audiobooks page has no group title for it).
  final bool heading;
  const AudiobookFoldersSection({super.key, this.heading = true});

  /// Asks for an audiobook folder, adds it (which scans it) and says how many books there are now.
  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    // Grab the messenger before the awaits, as this page may have been rebuilt by then.
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickFolderWithPermission(context, 'Choose your audiobooks folder');
    if (path == null) return;
    await lib.addAudiobookFolder(path);
    messenger.showSnackBar(SnackBar(content: Text('${lib.books.length} audiobooks found')));
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (heading)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text('Audiobook folders', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      for (final f in lib.audiobookFolders)
        ListTile(
          leading: const Icon(Icons.folder_special_outlined),
          title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
          // (0.1.16) A folder that couldn't be reached at the last scan keeps its books.
          subtitle: lib.offlineFolders.contains(f)
              ? const Text('Not available right now: its books are kept as they were')
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            FolderOptionsButton(folder: f),
            IconButton(
              tooltip: 'Remove folder',
              icon: const Icon(Icons.close),
              // Folder buttons are disabled while a scan/sync is running.
              onPressed: lib.busy ? null : () => lib.removeAudiobookFolder(f),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add audiobook folder'),
            onPressed: lib.busy ? null : () => _addFolder(context),
          ),
          Text('${lib.books.length} audiobook${lib.books.length == 1 ? '' : 's'}',
              style: TextStyle(color: AppColors.textDim)),
        ]),
      ),
    ]);
  }
}

/// The video folders for the Videos tab (0.1.40), with Add, Rescan and a count. The folders are
/// a setting in LibraryModel; VideoLibraryModel scans them.
class VideoFoldersSection extends StatelessWidget {
  const VideoFoldersSection({super.key});

  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    // Android keeps video files behind "Photos and videos", separate from "Music and audio".
    final access = await MusicPermission.requestVideos();
    if (access != MusicAccess.allowed) {
      messenger.showSnackBar(const SnackBar(
        content: Text('HomeTunes needs "Photos and videos" access to list your videos.'),
        action: SnackBarAction(label: 'Open settings', onPressed: MusicPermission.openSettings),
        duration: Duration(seconds: 8),
      ));
      return;
    }
    final path = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a video folder');
    if (path == null) return;
    await lib.addVideoFolder(path);
    messenger.showSnackBar(const SnackBar(content: Text('Looking for videos… They appear in the Videos tab.')));
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final videos = context.watch<VideoLibraryModel>();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final f in lib.videoFolders)
        ListTile(
          leading: const Icon(Icons.video_library_outlined),
          title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: videos.offlineFolders.contains(f)
              ? const Text('Not available right now: its videos are kept as they were')
              : null,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            FolderOptionsButton(folder: f, videos: true),
            IconButton(
              tooltip: 'Remove folder',
              icon: const Icon(Icons.close),
              onPressed: videos.busy ? null : () => lib.removeVideoFolder(f),
            ),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text('Add video folder'),
            onPressed: videos.busy ? null : () => _addFolder(context),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Rescan videos'),
            onPressed: videos.busy || lib.videoFolders.isEmpty ? null : videos.scan,
          ),
          Text(
            videos.busy
                ? (videos.status ?? 'Working…')
                : '${videos.videos.length} video${videos.videos.length == 1 ? '' : 's'}',
            style: TextStyle(color: AppColors.textDim),
          ),
        ]),
      ),
      if (videos.error != null && !videos.busy)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(videos.error!, style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ),
    ]);
  }
}

/// Settings › Folders & scanning: the music and audiobook folders HomeTunes reads.
class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});

  /// Asks for a folder, adds it (which scans it), then reports how many local songs there are.
  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickFolderWithPermission(context, 'Choose your music folder');
    if (path == null) return;
    await lib.addFolder(path);
    // Only count local files; server songs are in lib.tracks too.
    final n = lib.tracks.where((t) => t.isLocal).length;
    messenger.showSnackBar(SnackBar(content: Text('Library now has $n local songs')));
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final localCount = lib.tracks.where((t) => t.isLocal).length;
    return SettingsPageList(children: [
      const SettingsGroupTitle(
        'Music folders',
        'HomeTunes plays the MP3, FLAC, M4A, OGG, Opus and WAV files in these folders (and their subfolders).',
      ),
      SettingTarget(
        'music-folders',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final f in lib.folders)
            ListTile(
              leading: const Icon(Icons.folder),
              title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
              // (0.1.16) A folder that couldn't be reached at the last scan keeps its songs.
              subtitle: lib.offlineFolders.contains(f)
                  ? const Text('Not available right now: its songs are kept as they were')
                  : null,
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                FolderOptionsButton(folder: f),
                IconButton(
                  tooltip: 'Remove folder',
                  icon: const Icon(Icons.close),
                  onPressed: lib.busy ? null : () => lib.removeFolder(f),
                ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add folder'),
                onPressed: lib.busy ? null : () => _addFolder(context),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Rescan'),
                // Rescans music and audiobook folders alike.
                onPressed: lib.busy || (lib.folders.isEmpty && lib.audiobookFolders.isEmpty) ? null : lib.scanLocal,
              ),
              // While scanning, show the live progress text; otherwise the song count.
              ValueListenableBuilder<String?>(
                valueListenable: lib.statusText,
                builder: (_, status, _) => Text(lib.busy ? (status ?? 'Working…') : '$localCount songs found',
                    style: TextStyle(color: AppColors.textDim)),
              ),
            ]),
          ),
        ]),
      ),
      const SettingsGroupTitle(
        'Audiobook folders',
        'Everything in these folders is an audiobook and shows in the Books tab. The same list is under '
            'Settings › Audiobooks. Rescan above checks these too.',
      ),
      SettingTarget('library-book-folders', child: const AudiobookFoldersSection(heading: false)),
      const SettingsGroupTitle(
        'Video folders',
        'Every video in these folders shows in the Videos tab: MP4, MKV, WebM, AVI, MOV and most other video '
            'files. An MP4 in one of these is a video, not a song. They have their own Rescan below.',
      ),
      SettingTarget('library-video-folders', child: const VideoFoldersSection()),
      // Only shown when there are missing songs, so it isn't in the search catalog.
      if (lib.missingTracks.isNotEmpty) _MissingSongsTile(count: lib.missingTracks.length),
    ]);
  }
}

/// Songs HomeTunes knows about (edited, in playlists or liked) whose files
/// aren't on this device. They're kept in case the files come back.
class _MissingSongsTile extends StatelessWidget {
  final int count;
  const _MissingSongsTile({required this.count});

  /// Lists the missing songs, then (after a second "are you sure?") can forget them.
  Future<void> _showList(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final songs = lib.missingTracks;
    final forget = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$count song${count == 1 ? '' : 's'} not on this device'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text(
              'These songs have edits or are in playlists / Liked Songs, but their files weren\'t found. '
              'They\'re skipped when playing. If the files come back – even in a different folder – '
              'everything is picked up again on the next scan.',
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final t in songs)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(t.path ?? '${t.artist} · ${t.album}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget them')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
        ],
      ),
    );
    if (forget != true || !context.mounted) return;
    // Forgetting deletes edits and playlist entries, so double-check first.
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Forget these songs?'),
        content: const Text('Their edits are deleted and they\'re removed from your playlists and Liked Songs. '
            'Your music files aren\'t touched.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget')),
        ],
      ),
    );
    if (sure == true) await lib.forgetMissing();
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(Icons.help_outline, color: AppColors.textDim),
        title: Text('$count song${count == 1 ? '' : 's'} not on this device'),
        subtitle: const Text('Their details and playlist places are kept in case they come back'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showList(context),
      );
}
