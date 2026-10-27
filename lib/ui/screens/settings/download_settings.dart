// Settings › Servers › Downloads (0.2.3, step 3 of the Servers & Downloads plan): where downloads
// go (HomeTunes' data folder unless you pick another), the space they may take, how many
// episodes to download ahead while watching a series from a server (and which copy), and on
// phones and TVs Wi-Fi only and carrying on in the background. "See downloads" opens the
// Downloads page. Everything is kept by DownloadsModel (state/downloads_model.dart).
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/download.dart';
import '../../../state/downloads_model.dart';
import '../../nav.dart';
import '../../theme.dart';
import '../../widgets/download_ui.dart';
import '../../widgets/folder_browser.dart';
import 'package:provider/provider.dart';
import 'settings_widgets.dart';

/// The Downloads section (nothing when the app has no DownloadsModel, as in some tests).
class DownloadSettings extends StatelessWidget {
  /// Phones and TVs (Wi-Fi only and background); defaults to this device.
  final bool? phone;
  const DownloadSettings({super.key, this.phone});

  static const limits = <int?>[null, 5, 10, 20, 50, 100, 200, 500];

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context, listen: true);
    if (dl == null) return const SizedBox.shrink();
    final android = phone ?? Platform.isAndroid;
    final used = fileSizeText(dl.usedBytes);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SettingsGroupTitle('Downloads',
          'Download from your servers to play without them (Download… in any streamed thing\'s menu).'),
      SettingTarget(
        'downloads',
        child: ListTile(
          key: const ValueKey('downloads-open'),
          leading: const Icon(Icons.download_for_offline_outlined),
          title: const Text('See downloads'),
          subtitle: Text('${dl.done.length} downloaded · $used'
              '${dl.waiting.isEmpty ? '' : ' · ${dl.waiting.length} downloading'}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.read<AppNav>().openDownloads(),
        ),
      ),
      SettingTarget(
        'downloads-folder',
        child: ListTile(
          key: const ValueKey('downloads-folder'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Download folder'),
          subtitle: Text(dl.customFolder == null ? 'HomeTunes\' data folder (${dl.folder})' : dl.folder),
          trailing: Wrap(spacing: 4, children: [
            if (dl.customFolder != null)
              TextButton(
                key: const ValueKey('downloads-folder-default'),
                onPressed: () => _change(context, dl, null),
                child: const Text('Default'),
              ),
            TextButton(
              key: const ValueKey('downloads-folder-change'),
              onPressed: () async {
                final path = await pickFolder(context, 'Where downloads go');
                if (path != null && context.mounted) await _change(context, dl, path);
              },
              child: const Text('Change…'),
            ),
          ]),
        ),
      ),
      SettingTarget(
        'downloads-limit',
        child: ChoiceTile<int?>(
          key: const ValueKey('downloads-limit'),
          title: 'Space for downloads',
          subtitle: 'Using $used. When it\'s full, new downloads wait.',
          value: dl.limitGb,
          options: limits,
          label: (gb) => gb == null ? 'No limit' : '$gb GB',
          onChanged: dl.setLimitGb,
        ),
      ),
      SettingTarget(
        'downloads-ahead',
        child: ChoiceTile<int>(
          key: const ValueKey('downloads-ahead'),
          title: 'Download next episodes',
          subtitle: 'While you watch a series from a server, the next ones download. Each is removed once '
              'you\'ve watched it.',
          value: dl.ahead,
          options: const [0, 1, 2, 3, 4, 5],
          label: (n) => n == 0 ? 'Off' : (n == 1 ? 'The next one' : 'The next $n'),
          onChanged: dl.setAhead,
        ),
      ),
      if (dl.ahead > 0)
        SettingTarget(
          'downloads-ahead-quality',
          child: ChoiceTile<String>(
            key: const ValueKey('downloads-ahead-quality'),
            title: 'Copy for next episodes',
            value: dl.aheadQuality.code,
            options: [
              const DownloadQuality.original(video: true).code,
              for (final h in DownloadQuality.videoHeights) DownloadQuality.videoHeight(h).code,
            ],
            label: (c) {
              final q = DownloadQuality.parse(c, video: true);
              return q.isOriginal ? 'Original file' : 'Smaller copy, ${q.limit}p';
            },
            onChanged: (c) => dl.setAheadQuality(DownloadQuality.parse(c, video: true)),
          ),
        ),
      if (android) ...[
        SettingTarget(
          'downloads-wifi',
          child: SwitchListTile(
            key: const ValueKey('downloads-wifi'),
            title: const Text('Download over Wi-Fi only'),
            subtitle: const Text('Downloads wait until you\'re on Wi-Fi, so they don\'t use mobile data.'),
            value: dl.wifiOnly,
            onChanged: dl.setWifiOnly,
          ),
        ),
        SettingTarget(
          'downloads-background',
          child: SwitchListTile(
            key: const ValueKey('downloads-background'),
            title: const Text('Keep downloading in the background'),
            subtitle: const Text('Keep offline and next episodes carry on while HomeTunes isn\'t on screen. '
                'Off: they pause until you come back. Downloads you start yourself always carry on.'),
            value: dl.background,
            onChanged: dl.setBackground,
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          'Downloads stay private to HomeTunes. The server\'s sign-in is kept with each download while it '
          'runs, in HomeTunes\' own data.',
          style: TextStyle(color: AppColors.textDim, fontSize: 12),
        ),
      ),
    ]);
  }

  /// A new folder: asks whether to move what's already downloaded.
  static Future<void> _change(BuildContext context, DownloadsModel dl, String? path) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var move = false;
    if (dl.done.isNotEmpty) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Move your downloads?'),
          content: Text('Move the ${dl.done.length} downloads already made to the new folder too?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
                key: const ValueKey('downloads-move-no'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Leave them')),
            FilledButton(key: const ValueKey('downloads-move-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Move them')),
          ],
        ),
      );
      if (answer == null) return;
      move = answer;
    }
    final failed = await dl.setFolder(path, move: move);
    if (failed > 0) {
      messenger?.showSnackBar(SnackBar(content: Text('$failed downloads couldn\'t be moved; they stay where they were.')));
    }
  }
}
