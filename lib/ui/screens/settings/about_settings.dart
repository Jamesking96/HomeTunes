// Settings › About: shows the app version, "Check for updates" (0.1.23, see update_ui.dart) and
// the folder where HomeTunes keeps its own files (library.json, settings.json, covers, etc. — see
// Storage). On Windows there's a button to open that folder in Explorer. Shown by
// settings_screen.dart.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../../services/playback_log.dart';
import '../../../state/library_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';
import 'update_ui.dart';
import 'whats_new_ui.dart';

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
      // Check for updates + the daily-check switch (0.1.23, update_ui.dart).
      const UpdateSettings(),
      // The release notes for this version (0.1.28, whats_new_ui.dart).
      const WhatsNewRow(),
      SettingTarget(
        'data-folder',
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Where HomeTunes keeps its data'),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your library, playlists, edits, settings and saved covers. Your music files are never '
                'stored here.'),
            const SizedBox(height: 4),
            SelectableText(dataDir, style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ]),
          trailing: Platform.isWindows
              ? OutlinedButton(
                  onPressed: () => Process.run('explorer', [dataDir]),
                  child: const Text('Open folder'),
                )
              : null,
        ),
      ),
      SettingTarget(
        'playback-log',
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Playback log'),
          subtitle: const Text('What the player did recently: songs opening, playing and pausing, the app going to '
              'the background, and any problem it fixed. Useful if playback stops by itself.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlaybackLogScreen())),
        ),
      ),
    ]);
  }
}

/// The playback log, newest at the bottom, with Copy and Clear.
class PlaybackLogScreen extends StatefulWidget {
  const PlaybackLogScreen({super.key});

  @override
  State<PlaybackLogScreen> createState() => _PlaybackLogScreenState();
}

class _PlaybackLogScreenState extends State<PlaybackLogScreen> {
  @override
  Widget build(BuildContext context) {
    final lines = PlaybackLog.lines;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Playback log'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: lines.join('\n')));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Playback log copied')));
              }
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(PlaybackLog.clear),
          ),
        ],
      ),
      body: lines.isEmpty
          ? Center(child: Text('Nothing logged yet', style: TextStyle(color: AppColors.textDim)))
          : ListView.builder(
              reverse: true, // newest at the bottom, scrolled to the end
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: SelectableText(lines[lines.length - 1 - i],
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            ),
    );
  }
}
