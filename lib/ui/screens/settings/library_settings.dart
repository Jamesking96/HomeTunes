import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/music_permission.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';


/// Asks for permission to read audio files (Android), then lets the user pick a folder.
Future<String?> pickFolderWithPermission(BuildContext context, String title) async {
  final messenger = ScaffoldMessenger.of(context);
  final lib = context.read<LibraryModel>();
  final access = await MusicPermission.request();
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

/// Settings › Library: the music folders HomeTunes reads.
class LibrarySettings extends StatelessWidget {
  const LibrarySettings({super.key});

  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickFolderWithPermission(context, 'Choose your music folder');
    if (path == null) return;
    await lib.addFolder(path);
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
              trailing: IconButton(
                tooltip: 'Remove folder',
                icon: const Icon(Icons.close),
                onPressed: lib.busy ? null : () => lib.removeFolder(f),
              ),
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
                onPressed: lib.busy || lib.folders.isEmpty ? null : lib.scanLocal,
              ),
              ValueListenableBuilder<String?>(
                valueListenable: lib.statusText,
                builder: (_, status, _) => Text(lib.busy ? (status ?? 'Working…') : '$localCount songs found',
                    style: const TextStyle(color: AppColors.textDim)),
              ),
            ]),
          ),
        ]),
      ),
      if (lib.missingTracks.isNotEmpty) _MissingSongsTile(count: lib.missingTracks.length),
    ]);
  }
}

/// Songs HomeTunes knows about (edited, in playlists or liked) whose files
/// aren't on this device. They're kept in case the files come back.
class _MissingSongsTile extends StatelessWidget {
  final int count;
  const _MissingSongsTile({required this.count});

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
        leading: const Icon(Icons.help_outline, color: AppColors.textDim),
        title: Text('$count song${count == 1 ? '' : 's'} not on this device'),
        subtitle: const Text('Their details and playlist places are kept in case they come back'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showList(context),
      );
}
