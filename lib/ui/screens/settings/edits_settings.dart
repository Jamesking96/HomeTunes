import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/tag_writer.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › Your edits: writing HomeTunes edits into the music files.
class EditsSettings extends StatefulWidget {
  const EditsSettings({super.key});

  @override
  State<EditsSettings> createState() => EditsSettingsState();
}

class EditsSettingsState extends State<EditsSettings> {
  bool _backup = true;
  bool _running = false;

  Future<void> _write() async {
    final lib = context.read<LibraryModel>();
    final tracks = lib.tracksWithWritableEdits;
    if (tracks.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Write ${tracks.length} song${tracks.length == 1 ? '' : 's'} to files?'),
        content: Text(
          'Your HomeTunes edits (details and covers) will be saved into the music files themselves, so other '
          'players and devices see them too.\n\n'
          '${_backup ? 'A backup copy of each file is made first.' : 'No backup copies will be made.'}\n\n'
          'Anything a file type can\'t store (for example album artist in M4A, or covers in WAV) stays as a '
          'HomeTunes edit.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Write to files')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _running = true);
    List<TagWriteResult> results;
    try {
      results = await lib.writeEditsToFiles(tracks, backup: _backup);
    } catch (e) {
      results = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Writing tags failed: $e')));
      }
    }
    if (!mounted) return;
    setState(() => _running = false);

    final failed = results.where((r) => !r.ok).toList();
    final written = results.length - failed.length;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(failed.isEmpty ? 'Done' : 'Finished with some problems'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('$written file${written == 1 ? '' : 's'} updated.'),
            if (failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${failed.length} couldn\'t be written (their edits are kept in HomeTunes):'),
              const SizedBox(height: 4),
              for (final r in failed.take(8))
                Text('• ${r.path.split(RegExp(r'[\\/]')).last}: ${r.error}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
              if (failed.length > 8) Text('…and ${failed.length - 8} more', style: const TextStyle(fontSize: 12)),
            ],
            if (_backup && results.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Backups are in:', style: TextStyle(fontSize: 12)),
              SelectableText(lib.backupRoot, style: const TextStyle(fontSize: 12, color: AppColors.textDim)),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    final writable = lib.tracksWithWritableEdits.length;
    final unwritable = lib.unwritableEditCount;
    return SettingsPageList(children: [
      const SettingsGroupTitle(
        'Save edits into music files',
        'Edits you make in HomeTunes are normally kept in the app only. This writes them into the files '
            '(MP3, FLAC, M4A, WAV) so every player sees them, including lyrics you added (not WAV). '
            'Other tags in the files (ReplayGain, comments…) are kept.',
      ),
      SettingTarget('write-backup', child: SwitchListTile(
        title: const Text('Back up each file first'),
        subtitle: const Text('Keeps a copy of the original in the HomeTunes data folder'),
        value: _backup,
        onChanged: _running ? null : (v) => setState(() => _backup = v),
      )),
      SettingTarget('write-tags', child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FilledButton.icon(
            icon: _running
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_alt),
            label: Text(writable == 0 ? 'No edits to write' : 'Write $writable song${writable == 1 ? '' : 's'} to files…'),
            onPressed: _running || lib.busy || writable == 0 ? null : _write,
          ),
          if (unwritable > 0)
            Text(
              '$unwritable edited song${unwritable == 1 ? '' : 's'} can\'t be written (server songs or OGG/Opus)',
              style: const TextStyle(color: AppColors.textDim, fontSize: 12),
            ),
        ]),
      )),
    ]);
  }
}
