// Settings › Backup & restore: save all of HomeTunes' own data to one .htbackup file, or load
// one back (merging with what's here, or replacing it).
//
// The actual packing/unpacking is done by AppBackup (services/app_backup.dart) through
// LibraryModel.createBackup / restoreBackup. This page just handles the file picker, the
// "what's in this backup?" dialog, and reloading the other models after a restore.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/app_backup.dart';
import '../../../state/bookmarks_model.dart';
import '../../../state/equalizer_model.dart';
import '../../../state/library_model.dart';
import '../../../state/listening_model.dart';
import '../../../state/lyrics_model.dart';
import '../../../state/playlists_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Backup & restore.
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  @override
  State<BackupSettings> createState() => BackupSettingsState();
}

class BackupSettingsState extends State<BackupSettings> {
  bool _includeCoverCache = true;
  bool _working = false; // true while exporting/reading/restoring; disables the buttons

  /// Suggested file name, e.g. "HomeTunes-backup-2026-09-25.htbackup".
  String get _fileName {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'HomeTunes-backup-${d.year}-${two(d.month)}-${two(d.day)}.${AppBackup.fileExtension}';
  }

  /// Builds the backup in memory, then asks where to save it.
  Future<void> _export() async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = true);
    try {
      final bytes = await lib.createBackup(
        includeCoverCache: _includeCoverCache,
      );
      // The picker is given the bytes and writes the file itself (on Android the app can't
      // write to the chosen place directly). Null means the user cancelled.
      final saved = await FilePicker.saveFile(
        fileName: _fileName,
        bytes: bytes,
        dialogTitle: 'Save HomeTunes backup',
      );
      if (saved != null) {
        final mb = (bytes.length / (1024 * 1024)).toStringAsFixed(1);
        messenger.showSnackBar(SnackBar(content: Text('Backup saved ($mb MB)')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Couldn\'t make the backup: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Restores a backup in three steps: read the file, ask Merge or Replace, then restore.
  Future<void> _import() async {
    // Grab all the models now; after the awaits below, `context` may no longer be usable.
    final lib = context.read<LibraryModel>();
    final playlists = context.read<PlaylistsModel>();
    final listening = context.read<ListeningModel>();
    final bookmarks = context.read<BookmarksModel>();
    final lyrics = context.read<LyricsModel>();
    final equalizer = context.read<EqualizerModel>();
    final messenger = ScaffoldMessenger.of(context);

    // 1. Pick and read the file. A file that isn't a backup (or is from a newer HomeTunes)
    //    throws a FormatException whose message is already written for the user.
    BackupContents backup;
    try {
      final file = await FilePicker.pickFile(type: FileType.any, dialogTitle: 'Choose a HomeTunes backup');
      final path = file?.path;
      if (path == null) return;
      setState(() => _working = true);
      backup = AppBackup.read(await File(path).readAsBytes());
    } catch (e) {
      if (mounted) setState(() => _working = false);
      messenger.showSnackBar(SnackBar(content: Text(e is FormatException ? e.message : 'Couldn\'t read it: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _working = false);

    // 2. Show what's in it and ask how to restore. true = Merge, false = Replace,
    //    null = Cancel (or tapped outside the dialog).
    final merge = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (backup.created != null)
            Text('Made ${_date(backup.created!)}${backup.from != null ? ' on ${_os(backup.from!)}' : ''}'),
          const SizedBox(height: 8),
          Text('• ${backup.songCount} songs in the library\n'
              '• ${backup.playlistCount} playlist${backup.playlistCount == 1 ? '' : 's'}, '
              '${backup.likedCount} liked song${backup.likedCount == 1 ? '' : 's'}\n'
              '• ${backup.editCount} edited song${backup.editCount == 1 ? '' : 's'}\n'
              '• your place in ${backup.bookProgressCount} audiobook${backup.bookProgressCount == 1 ? '' : 's'}, '
              '${backup.bookmarkCount} bookmark${backup.bookmarkCount == 1 ? '' : 's'}\n'
              '• ${backup.folders.length} music folder${backup.folders.length == 1 ? '' : 's'}'
              '${backup.hasPassword ? '\n• server password included' : ''}'),
          const SizedBox(height: 12),
          Text(
            'Replace: this device\'s HomeTunes data becomes the backup\'s.\n'
            'Merge: the backup\'s playlists, likes and edits are added to what\'s here.\n\n'
            'Your music files aren\'t touched. A copy of the current data is saved first.',
            style: TextStyle(color: AppColors.textDim, fontSize: 13),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Merge')),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Replace')),
        ],
      ),
    );
    if (merge == null || !mounted) return;

    // 3. Restore. LibraryModel writes the files, then the other models re-read theirs from disk
    //    (reloadOthers), and finally we explain anything that couldn't be brought across.
    setState(() => _working = true);
    try {
      final result = await lib.restoreBackup(backup, merge: merge, reloadOthers: () async {
        await playlists.load();
        await listening.load();
        await bookmarks.load();
        await lyrics.load();
        await equalizer.load();
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Backup restored'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${lib.tracks.length} songs are available on this device.'),
            if (lib.missingTracks.isNotEmpty)
              Text('${lib.missingTracks.length} songs from the backup aren\'t here yet; their details and playlist '
                  'places are kept and are picked up when you add the folder they\'re in.'),
            if (result.missingFolders.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('These music folders don\'t exist on this device, so they weren\'t added. '
                  'Use "Add folder" to point HomeTunes at your music here:'),
              for (final f in result.missingFolders)
                Text('• $f', style: TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
            if (result.needsPassword) ...[
              const SizedBox(height: 12),
              const Text('The server password wasn\'t in the backup: enter it under Settings › Servers.'),
            ],
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// "25 Sep 2026" style date for the restore dialog.
  static String _date(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// Nicer name for the platform the backup was made on.
  static String _os(String os) => switch (os) {
        'windows' => 'Windows',
        'android' => 'Android',
        'macos' => 'macOS',
        'linux' => 'Linux',
        'ios' => 'iOS',
        _ => os,
      };

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final busy = _working || lib.busy;
    return SettingsPageList(
      intro: 'Save everything HomeTunes keeps – music and audiobook folders, server (not its password), playlists, Liked Songs, song and '
            'book edits, covers, your place in each audiobook, bookmarks, equaliser presets, settings and the library – to one file, '
            'to restore later or move to another PC or phone.',
      children: [
      SettingTarget('backup-covers', child: SwitchListTile(
        title: const Text('Include cover images from music files'),
        subtitle: const Text('Makes the file bigger; without them they\'re re-read from your music. '
            'Covers you chose or found online are always included.'),
        value: _includeCoverCache,
        onChanged: busy ? null : (v) => setState(() => _includeCoverCache = v),
      )),
      // 0.1.21 (security review #6): the server password is never put in a backup (it would be
      // plain text in the file), so it's typed in again after restoring on another device.
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SettingTarget('backup-export', child: FilledButton.icon(
            icon: _working
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.upload_file),
            label: const Text('Export backup…'),
            onPressed: busy ? null : _export,
          )),
          SettingTarget('backup-import', child: OutlinedButton.icon(
            icon: const Icon(Icons.download),
            label: const Text('Import backup…'),
            onPressed: busy ? null : _import,
          )),
        ]),
      ),
      ],
    );
  }
}
