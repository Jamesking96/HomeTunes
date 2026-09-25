// Settings › About: shows the app version and the folder where HomeTunes keeps its own files
// (library.json, settings.json, covers, etc. — see Storage). On Windows there's a button to open
// that folder in Explorer. Shown by settings_screen.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Settings › About: which version this is and where its data lives.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  // Read the version once for the whole app run (static), and turn a failure into null so
  // the page shows "Unknown" instead of an error.
  static final Future<PackageInfo?> _info = PackageInfo.fromPlatform().then<PackageInfo?>((i) => i, onError: (_) => null);

  @override
  Widget build(BuildContext context) {
    final dataDir = context.read<LibraryModel>().storage.root.path;
    return SettingsPageList(children: [
      SettingTarget(
        'version',
        child: FutureBuilder<PackageInfo?>(
          future: _info,
          builder: (context, snap) {
            final i = snap.data;
            // "…" while still loading, "Unknown" if it couldn't be read.
            final text = i == null
                ? (snap.connectionState == ConnectionState.done ? 'Unknown' : '…')
                : '${i.version} (build ${i.buildNumber})';
            return ListTile(
              leading: const Icon(Icons.graphic_eq),
              title: const Text('HomeTunes'),
              subtitle: Text('Version $text'),
            );
          },
        ),
      ),
      SettingTarget(
        'data-folder',
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Where HomeTunes keeps its data'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your library, playlists, edits, settings and saved covers. Your music files are never '
                'stored here.'),
            const SizedBox(height: 4),
            SelectableText(dataDir, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
          ]),
          trailing: Platform.isWindows
              ? OutlinedButton(
                  onPressed: () => Process.run('explorer', [dataDir]),
                  child: const Text('Open folder'),
                )
              : null,
        ),
      ),
    ]);
  }
}
