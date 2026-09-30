// Videos (0.1.32): the "Also save into .nfo files" tick box shared by Edit details and Edit
// collection, and the step after saving that writes the files (VideoLibraryModel.saveNfoFiles,
// services/video_nfo.dart) and says how it went. Not offered on Android, where the app can't
// write into the phone's video folders.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/video_item.dart';
import '../../state/video_library_model.dart';
import '../theme.dart';

/// Whether .nfo files can be written on this device.
bool get canSaveNfo => !Platform.isAndroid;

/// The tick box (remembered between edits).
class SaveNfoCheckbox extends StatelessWidget {
  const SaveNfoCheckbox({super.key});

  @override
  Widget build(BuildContext context) {
    if (!canSaveNfo) return const SizedBox.shrink();
    final model = context.watch<VideoLibraryModel>();
    return CheckboxListTile(
      key: const ValueKey('save-nfo'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      value: model.saveNfo,
      onChanged: (on) => model.setSaveNfo(on ?? false),
      title: const Text('Also save into .nfo files beside the videos'),
      subtitle: Text(
          'Kodi, Jellyfin and Plex read these too, and HomeTunes reads them back when it scans. '
          'The videos themselves aren\'t changed.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12)),
    );
  }
}

/// After an edit is saved: writes the .nfo files for [items] if the box is ticked, in the
/// background, then says how it went. Call it before closing the dialog (it needs [context]
/// only to find the messenger).
void saveNfoAfterEdit(BuildContext context, Iterable<VideoItem> items) {
  final model = context.read<VideoLibraryModel>();
  if (!canSaveNfo || !model.saveNfo) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final list = items.toList();
  unawaited(() async {
    final r = await model.saveNfoFiles(list);
    if (r.written == 0 && r.errors.isEmpty) return;
    final files = '${r.written} .nfo file${r.written == 1 ? '' : 's'}';
    messenger?.showSnackBar(SnackBar(
      content: Text(r.errors.isEmpty
          ? 'Saved into $files'
          : 'Saved into $files; ${r.errors.length} couldn\'t be written (${r.errors.first})'),
    ));
  }());
}
