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
import '../../tv/tv_focus.dart' show tvModeOf;

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
      // Where and how (29 Oct, the user: "add a note … that where & how they are used by the user").
      HowItWorks(key: const ValueKey('downloads-how'), lines: downloadsHow(HelpDevice.of(context))),
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
      // The queue (27 Oct, the user: "a new button near the downloading settings that takes you
      // to a list of all medias being downloaded in a queue format").
      SettingTarget(
        'downloads-queue',
        child: ListTile(
          key: const ValueKey('downloads-queue-open'),
          leading: Badge(
            isLabelVisible: dl.queue.isNotEmpty,
            label: Text('${dl.queue.length}'),
            child: const Icon(Icons.queue_outlined),
          ),
          title: const Text('Download queue'),
          subtitle: Text(dl.queue.isEmpty
              ? 'Nothing waiting to download'
              : '${dl.queue.length} in the queue · ${dl.queue.where((e) => e.state == DownloadState.running).length} downloading now'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.read<AppNav>().openDownloadQueue(),
        ),
      ),
      // What Download and Keep offline each do (27 Oct, the user: "add the description of what
      // download vs keep offline are somewhere so people can refer to it").
      SettingTarget(
        'downloads-help',
        child: ListTile(
          key: const ValueKey('downloads-help'),
          leading: const Icon(Icons.help_outline),
          title: const Text('Download or Keep offline?'),
          subtitle: const Text('What each one does, and how temporary copies differ'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showDownloadHelp(context),
        ),
      ),
      // The whole row is the button (27 Oct: "Change…" sat in the row's corner, which the TV
      // remote couldn't reach, so pressing OK on it did nothing). Once another folder is chosen,
      // the row offers going back to HomeTunes' own as well.
      SettingTarget(
        'downloads-folder',
        child: ListTile(
          key: const ValueKey('downloads-folder'),
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Download folder'),
          subtitle: Text(dl.customFolder == null ? 'HomeTunes\' data folder (${dl.folder})' : dl.folder),
          trailing: Text('Change…', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
          onTap: () => chooseFolder(context, dl),
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
      SettingTarget(
        'downloads-remove-watched',
        child: SwitchListTile(
          key: const ValueKey('downloads-remove-watched'),
          title: const Text('Remove downloaded videos once watched'),
          subtitle: const Text('A film or episode you\'ve downloaded is removed when you finish watching it, '
              'to free the space. One already watched before you downloaded it stays until you watch it again.'),
          value: dl.removeWatched,
          onChanged: dl.setRemoveWatched,
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

  /// The Download folder row: picks a folder (with HomeTunes' own as a choice once another is
  /// set), checks HomeTunes can save there, then switches to it.
  static Future<void> chooseFolder(BuildContext context, DownloadsModel dl,
      {Future<String?> Function(BuildContext, String)? picker}) async {
    if (dl.customFolder != null) {
      final which = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Download folder'),
          children: [
            SimpleDialogOption(
              key: const ValueKey('downloads-folder-pick'),
              onPressed: () => Navigator.pop(ctx, 'pick'),
              child: const ListTile(leading: Icon(Icons.folder_open), title: Text('Choose another folder')),
            ),
            SimpleDialogOption(
              key: const ValueKey('downloads-folder-default'),
              onPressed: () => Navigator.pop(ctx, 'default'),
              child: const ListTile(leading: Icon(Icons.restore), title: Text('Back to HomeTunes\' data folder')),
            ),
          ],
        ),
      );
      if (which == null || !context.mounted) return;
      if (which == 'default') return _change(context, dl, null);
    }
    final path = await (picker ?? pickFolder)(context, 'Where downloads go');
    if (path == null || !context.mounted) return;
    if (!await canWriteTo(path)) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('HomeTunes can\'t save files in $path. Choose another folder'
            '${Platform.isAndroid ? ', such as one inside Download or Movies' : ''}.'),
      ));
      return;
    }
    if (context.mounted) await _change(context, dl, path);
  }

  /// Whether a file can be made in [dir] (made if it isn't there).
  static Future<bool> canWriteTo(String dir) async {
    try {
      await Directory(dir).create(recursive: true);
      final probe = File('$dir${Platform.pathSeparator}.hometunes-write-test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A new folder: asks whether to move what's already downloaded.
  static Future<void> _change(BuildContext context, DownloadsModel dl, String? path) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var move = false;
    if (dl.done.isNotEmpty || dl.temporaries.isNotEmpty) {
      final answer = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Move your downloads?'),
          content: Text('Move the ${dl.done.length + dl.temporaries.length} downloads already made to the new folder too?'),
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

/// Settings › Servers › Temporary copies (0.2.4, step 4 of the Servers & Downloads plan): save
/// what streams so it replays without the server, then clear it away some days after it's
/// finished (or never, with Don't delete automatically), within its own space, and Clear now.
/// Nothing when the app has no DownloadsModel.
class TemporaryCopySettings extends StatelessWidget {
  const TemporaryCopySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final dl = downloadsOf(context, listen: true);
    if (dl == null) return const SizedBox.shrink();
    final n = dl.temporaryCount;
    final used = fileSizeText(dl.tempUsedBytes);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SettingsGroupTitle('Temporary copies',
          'Save what you stream so it plays again without the server, then clear it away. Downloads are never cleared.'),
      HowItWorks(key: const ValueKey('temp-how'), lines: temporaryHow(HelpDevice.of(context), days: dl.tempKeep ? null : dl.tempDays)),
      SettingTarget(
        'temp-save',
        child: SwitchListTile(
          key: const ValueKey('temp-save'),
          title: const Text('Save a copy while streaming'),
          subtitle: const Text('Plays straight away, and saves the file in the background.'),
          value: dl.tempSave,
          onChanged: dl.setTempSave,
        ),
      ),
      SettingTarget(
        'temp-days',
        child: ChoiceTile<int>(
          key: const ValueKey('temp-days'),
          title: 'Delete after',
          subtitle: dl.tempKeep
              ? 'Off while "Don\'t delete automatically" is on.'
              : 'Counted from when it\'s finished: watched to the end, played through, or the book finished. '
                  'Something part-played stays until it\'s finished.',
          value: dl.tempDays,
          options: DownloadsModel.tempDayChoices,
          label: (d) => d == 1 ? '1 day' : '$d days',
          onChanged: dl.setTempDays,
        ),
      ),
      SettingTarget(
        'temp-keep',
        child: SwitchListTile(
          key: const ValueKey('temp-keep'),
          title: const Text('Don\'t delete automatically'),
          subtitle: const Text('Temporary copies stay until you clear them. Once their space is full, no more are saved.'),
          value: dl.tempKeep,
          onChanged: dl.setTempKeep,
        ),
      ),
      SettingTarget(
        'temp-limit',
        child: ChoiceTile<int>(
          key: const ValueKey('temp-limit'),
          title: 'Space for temporary copies',
          subtitle: 'Using $used. When it\'s full, the oldest finished copies go first.',
          value: dl.tempLimitGb,
          options: DownloadsModel.tempLimitChoices,
          label: (gb) => '$gb GB',
          onChanged: dl.setTempLimitGb,
        ),
      ),
      SettingTarget(
        'temp-clear',
        child: ListTile(
          leading: const Icon(Icons.cleaning_services_outlined),
          title: const Text('Clear now'),
          subtitle: Text(n == 0 ? 'No temporary copies' : '$n temporary cop${n == 1 ? 'y' : 'ies'} · $used'),
          trailing: TextButton(
            key: const ValueKey('temp-clear'),
            onPressed: n == 0
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('Clear $n temporary cop${n == 1 ? 'y' : 'ies'}?'),
                        content: const Text('They stream from the server again. Your downloads stay.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(
                              key: const ValueKey('temp-clear-ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (ok == true) await dl.clearTemporary();
                  },
            child: const Text('Clear now'),
          ),
        ),
      ),
    ]);
  }
}


// ---- Where and how (0.2.5) ----

/// The kind of device, for saying how to open a thing's menu there.
enum HelpDevice {
  tv,
  phone,
  computer;

  static HelpDevice of(BuildContext context) => tvModeOf(context) ? tv : (Platform.isAndroid || Platform.isIOS ? phone : computer);

  /// How to open the menu of a film, song or book here.
  String get menu => switch (this) {
        tv => 'Hold OK on',
        phone => 'Press and hold',
        computer => 'Right-click (or use the ⋮ menu of)',
      };
}

/// What the Downloads section's note says on [d] (29 Oct): how to download, and where
/// downloads are used.
List<(String, String)> downloadsHow(HelpDevice d) {
  return [
    (
      'How to download',
      '${d.menu} a film, episode, season, collection, song, album or audiobook from a server, and choose '
          'Download. You pick the copy each time: the original file, or a smaller one.',
    ),
    (
      'Keep offline',
      'In the same menu, for a whole collection, season, album or playlist: everything in it downloads, and '
          'anything added to it later downloads by itself.',
    ),
    (
      'Where they\'re used',
      'Something downloaded plays from this device first, even when the server is off or there\'s no '
          'internet.${d == HelpDevice.tv ? '' : ' A small cloud-and-tick mark shows on it, and the Filter button\'s Source › Downloaded shows just those.'}',
    ),
    (
      'Finding and removing them',
      'See downloads below lists them all, with the space they take. Remove one there, or with Remove download '
          'in its menu: it then streams from the server again.',
    ),
  ];
}

/// What the Temporary copies section's note says on [d] (29 Oct). [days]: how long a copy
/// stays once finished (null: kept until cleared).
List<(String, String)> temporaryHow(HelpDevice d, {int? days}) {
  return [
    (
      'How they\'re made',
      'Nothing to do: with Save a copy while streaming on, whatever you play from a server is saved on this '
          'device as it plays.',
    ),
    (
      'Where they\'re used',
      'Play it again and it plays from the copy: it starts quicker, and works when the server is off.',
    ),
    (
      'When they go',
      days == null
          ? 'Don\'t delete automatically is on, so they stay until you use Clear now below.'
          : 'Each is cleared $days day${days == 1 ? '' : 's'} after you finish it (a video watched, a song played '
              'through, a book finished), or sooner when their space is full. Downloads are never cleared.',
    ),
    (
      'Keeping one',
      'They show in See downloads as Temporary copy. Keep this copy there, or in its menu (${d.menu.toLowerCase()} it), '
          'turns it into a normal download.',
    ),
  ];
}

/// A small panel of short headed lines saying where and how a section's feature is used.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key, required this.lines});
  final List<(String, String)> lines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppShape.circular(10)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < lines.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Text(lines[i].$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(lines[i].$2, style: TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.35)),
            ],
          ]),
        ),
      ),
    );
  }
}
