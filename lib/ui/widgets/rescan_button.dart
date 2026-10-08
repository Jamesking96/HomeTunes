// 0.1.73: a quick "Rescan" in the top bar of Your Library (music) and Audiobooks, like the one on
// the Videos tab. It runs the same rescan as Settings › Folders & scanning (music and audiobook
// folders together), and turns into a small spinner while it works.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/library_model.dart';

class RescanButton extends StatelessWidget {
  /// What the tooltip says, e.g. "Rescan music folders".
  final String tooltip;
  const RescanButton({super.key, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final busy = context.select<LibraryModel, bool>((l) => l.busy);
    final none = context.select<LibraryModel, bool>((l) => l.folders.isEmpty && l.audiobookFolders.isEmpty);
    if (busy) {
      return const Tooltip(
        message: 'Rescanning…',
        child: Padding(
          padding: EdgeInsets.all(14),
          child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return IconButton(
      key: const ValueKey('rescan-library'),
      tooltip: none ? 'Add folders in Settings first' : tooltip,
      icon: const Icon(Icons.refresh),
      onPressed: none ? null : () => context.read<LibraryModel>().scanLocal(),
    );
  }
}
