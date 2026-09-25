import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/book_index.dart';
import '../../../state/library_model.dart';
import '../../../state/player_model.dart';
import '../../theme.dart';
import '../../widgets/listening_controls.dart' show SpeedButton;
import '../../widgets/track_tile.dart' show askForName;
import 'library_settings.dart' show pickFolderWithPermission;
import 'settings_widgets.dart';

/// Settings › Audiobooks: where books come from and how they play.
class AudiobookSettings extends StatelessWidget {
  const AudiobookSettings({super.key});

  Future<void> _addFolder(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final messenger = ScaffoldMessenger.of(context);
    final path = await pickFolderWithPermission(context, 'Choose your audiobooks folder');
    if (path == null) return;
    await lib.addAudiobookFolder(path);
    messenger.showSnackBar(SnackBar(content: Text('${lib.books.length} audiobooks found')));
  }

  Future<void> _addGenre(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    final name = await askForName(context, title: 'Genre that means "audiobook"');
    if (name == null) return;
    await lib.setBookGenres([...lib.bookGenres, name]);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryModel>();
    return SettingsPageList(
      intro: 'Audiobooks have their own tab and never show up with your music. Everything in an audiobook folder '
          'is a book; so are .m4b files and files with an audiobook genre in your music folders.',
      children: [
        const SettingsGroupTitle('Listening'),
        SettingTarget(
          'skip-back',
          child: ChoiceTile<int>(
            title: 'Skip back',
            value: lib.skipBackSeconds,
            options: const [5, 10, 15, 30, 45, 60],
            label: (v) => '$v seconds',
            onChanged: (v) => lib.updateListeningSettings(skipBackSeconds: v),
          ),
        ),
        SettingTarget(
          'skip-forward',
          child: ChoiceTile<int>(
            title: 'Skip forward',
            value: lib.skipForwardSeconds,
            options: const [5, 10, 15, 30, 45, 60],
            label: (v) => '$v seconds',
            onChanged: (v) => lib.updateListeningSettings(skipForwardSeconds: v),
          ),
        ),
        SettingTarget(
          'book-speed',
          child: ChoiceTile<double>(
            title: 'Speed for new books',
            subtitle: 'Each book remembers its own speed once you change it',
            value: lib.defaultBookSpeed,
            options: PlayerModel.speeds,
            label: SpeedButton.label,
            onChanged: (v) => lib.updateListeningSettings(defaultBookSpeed: v),
          ),
        ),
        SettingTarget(
          'rewind-resume',
          child: SwitchListTile(
            title: const Text('Rewind a little when resuming'),
            subtitle: const Text('A few seconds after a short pause, up to 30 seconds after a long break'),
            value: lib.rewindOnResume,
            onChanged: (v) => lib.updateListeningSettings(rewindOnResume: v),
          ),
        ),
        const SettingsGroupTitle('Where your audiobooks are'),
        SettingTarget(
          'book-folders',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text('Audiobook folders', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            for (final f in lib.audiobookFolders)
              ListTile(
                leading: const Icon(Icons.folder_special_outlined),
                title: Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: 'Remove folder',
                  icon: const Icon(Icons.close),
                  onPressed: lib.busy ? null : () => lib.removeAudiobookFolder(f),
                ),
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
                    style: const TextStyle(color: AppColors.textDim)),
              ]),
            ),
          ]),
        ),
        SettingTarget(
          'book-genres',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('Genres that mean "audiobook"', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 4, children: [
                for (final g in lib.bookGenres)
                  InputChip(
                    label: Text(g),
                    onDeleted: () => lib.setBookGenres([for (final x in lib.bookGenres) if (x != g) x]),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                  onPressed: () => _addGenre(context),
                ),
                if (!_sameGenres(lib.bookGenres, defaultBookGenres))
                  TextButton(
                    onPressed: () => lib.setBookGenres(List.of(defaultBookGenres)),
                    child: const Text('Reset'),
                  ),
              ]),
            ),
          ]),
        ),
        const SettingsGroupTitle('Look'),
        SettingTarget(
          'book-covers',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Book cover shape', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.crop_square), label: Text('Match music (square)')),
                  ButtonSegment(value: true, icon: Icon(Icons.crop_portrait), label: Text('Book (tall)')),
                ],
                selected: {lib.bookCoversTall},
                onSelectionChanged: (v) => lib.setBookCoversTall(v.first),
              ),
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text('The sleep timer for books is under Settings › Sleep timer.',
              style: TextStyle(color: AppColors.textDim, fontSize: 13)),
        ),
      ],
    );
  }

  static bool _sameGenres(List<String> a, List<String> b) =>
      a.length == b.length && [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((x) => x);
}
