// The update screens (0.1.23): the "Check for updates" rows on Settings › About, the
// "Update to HomeTunes x?" question, and the notice shown when the daily check finds one.
//
// UpdateModel (state/update_model.dart) does the work. On an installed Windows copy, saying
// Update downloads the installer, checks it, closes HomeTunes (after pausing and saving the
// audiobook place), and the installer updates it and opens it again. On the phone, and on a
// copy unzipped from the zip file, it opens the release page in the browser instead.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/update_checker.dart';
import '../../../state/library_model.dart';
import '../../../state/player_model.dart';
import '../../../state/update_model.dart';
import '../../theme.dart';
import 'settings_widgets.dart';

/// Given to MaterialApp so the start-up notice can be shown from outside the widget tree.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
final appNavigatorKey = GlobalKey<NavigatorState>();

/// "Last checked today at 14:02" / "…on 3 Oct".
String lastCheckedText(DateTime when, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(when.hour)}:${two(when.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  if (day == today) return 'Last checked today at $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Last checked yesterday at $time';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return 'Last checked on ${when.day} ${months[when.month - 1]}';
}

/// The two rows on Settings › About.
class UpdateSettings extends StatelessWidget {
  const UpdateSettings({super.key});

  Future<void> _check(BuildContext context) async {
    final found = await context.read<UpdateModel>().check();
    if (found != null && context.mounted) await showUpdateDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateModel>();
    final accent = Theme.of(context).colorScheme.primary;
    final latest = u.latest;

    Widget subtitle;
    Widget? trailing;
    switch (u.stage) {
      case UpdateStage.checking:
        subtitle = const Text('Checking…');
        trailing = const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
      case UpdateStage.available:
        subtitle = Text('HomeTunes ${latest?.version} is available', style: TextStyle(color: accent));
        trailing = FilledButton(onPressed: () => showUpdateDialog(context), child: const Text('Update…'));
      case UpdateStage.downloading:
        subtitle = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(u.progress == null ? 'Downloading…' : 'Downloading… ${(u.progress! * 100).round()}%'),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: u.progress),
        ]);
      case UpdateStage.installing:
        subtitle = const Text('Closing HomeTunes to update…');
      case UpdateStage.failed:
        subtitle = Text(u.error ?? 'Something went wrong.', style: const TextStyle(color: Colors.redAccent));
        trailing = OutlinedButton(onPressed: () => _check(context), child: const Text('Try again'));
      case UpdateStage.upToDate:
        subtitle = Text('You have the latest version (${u.currentVersion ?? latest?.version ?? '?'})');
        trailing = OutlinedButton(onPressed: () => _check(context), child: const Text('Check now'));
      case UpdateStage.idle:
        subtitle = Text(u.lastCheck == null
            ? 'See if there\'s a newer version of HomeTunes'
            : lastCheckedText(u.lastCheck!.toLocal(), DateTime.now()));
        trailing = OutlinedButton(onPressed: () => _check(context), child: const Text('Check now'));
    }

    return Column(children: [
      SettingTarget(
        'updates',
        child: ListTile(
          leading: const Icon(Icons.system_update_alt),
          title: const Text('Check for updates'),
          subtitle: subtitle,
          trailing: trailing,
        ),
      ),
      SettingTarget(
        'update-auto',
        child: SwitchListTile(
          secondary: const Icon(Icons.update),
          title: const Text('Check for updates automatically'),
          subtitle: const Text('Once a day, HomeTunes looks for a newer version and lets you know. '
              'Nothing is downloaded unless you say so.'),
          value: u.autoCheck,
          onChanged: u.setAutoCheck,
        ),
      ),
    ]);
  }
}

/// The start-up notice: "HomeTunes x is available" with an Update… button.
void showUpdateNotice(ReleaseInfo release) {
  appMessengerKey.currentState?.showSnackBar(SnackBar(
    content: Text('A new version of HomeTunes (${release.version}) is available'),
    duration: const Duration(seconds: 12),
    action: SnackBarAction(
      label: 'Update…',
      onPressed: () {
        final context = appNavigatorKey.currentContext;
        if (context != null) showUpdateDialog(context);
      },
    ),
  ));
}

/// Asks whether to update to the version found, and does it if the answer is yes.
Future<void> showUpdateDialog(BuildContext context) =>
    showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const _UpdateDialog());

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog();

  /// Pauses (saving the audiobook place and anything else waiting) and closes HomeTunes, so the
  /// installer can replace it.
  static Future<void> _closeForUpdate(BuildContext context) async {
    final player = context.read<PlayerModel>();
    final lib = context.read<LibraryModel>();
    try {
      await player.pause();
      player.saveBookPlace();
      await lib.flushPendingSaves();
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 600));
    exit(0);
  }

  Future<void> _update(BuildContext context) async {
    final u = context.read<UpdateModel>();
    if (u.canInstallHere) {
      final started = await u.downloadAndInstall();
      if (started && context.mounted) await _closeForUpdate(context);
    } else {
      final opened = await u.openDownloadPage();
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (!opened) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
          content: Text('Couldn\'t open the browser. The download page is ${(u.latest?.page ?? releasesPage)}'),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = context.watch<UpdateModel>();
    final latest = u.latest;
    final install = u.canInstallHere;
    final dim = TextStyle(color: AppColors.textDim, fontSize: 13);

    // Downloading / installing: just the progress, no buttons.
    if (u.stage == UpdateStage.downloading || u.stage == UpdateStage.installing) {
      final installing = u.stage == UpdateStage.installing;
      return AlertDialog(
        title: Text(installing ? 'Updating HomeTunes' : 'Downloading the update'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          LinearProgressIndicator(value: installing ? null : u.progress),
          const SizedBox(height: 12),
          Text(installing
              ? 'HomeTunes will close now and open again by itself in a moment.'
              : u.progress == null
                  ? 'Downloading…'
                  : 'Downloading… ${(u.progress! * 100).round()}%'),
        ]),
      );
    }

    if (u.stage == UpdateStage.failed) {
      return AlertDialog(
        title: const Text('The update didn\'t work'),
        content: Text(u.error ?? 'Something went wrong.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
          if (latest != null)
            TextButton(
              onPressed: () {
                u.openDownloadPage();
                Navigator.of(context).pop();
              },
              child: const Text('Open download page'),
            ),
        ],
      );
    }

    if (latest == null) {
      return AlertDialog(
        content: const Text('No update found.'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      );
    }

    final how = install
        ? 'HomeTunes will download the update, close, install it and open again. Your library, playlists, '
            'settings and audiobook places are kept.'
        : Platform.isAndroid
            ? 'The download page will open in your browser. Download the Android file (the one ending in .apk) '
                'and open it to install the update over this one. Your library and settings are kept.'
            : 'This copy was unzipped rather than installed, so it can\'t update itself. The download page will '
                'open in your browser.';

    return AlertDialog(
      title: Text('Update to HomeTunes ${latest.version}?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (u.currentVersion != null) Text('You have ${u.currentVersion}.', style: dim),
          if (latest.whatsNew.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('What\'s new', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(child: Text(latest.whatsNew, style: const TextStyle(fontSize: 13))),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(how, style: dim),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Not now')),
        FilledButton(
          onPressed: () => _update(context),
          child: Text(install ? 'Update' : 'Open download page'),
        ),
      ],
    );
  }
}
