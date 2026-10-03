// The "No internet connection" warning (0.1.50).
//
// - At start-up (main.dart): if the internet can't be reached, a pop-up says which features
//   need it, with Carry on. Everything else keeps working.
// - Before an online feature (Find online…, Find cover online…, Find lyrics on LRCLIB…,
//   Search online for video pictures, Check for updates, Update, What's new in this version):
//   [ensureOnline] checks again. If it's still not reachable, the same warning shows, with OK
//   (don't go ahead) and Try anyway (in case the check is wrong). If it is reachable now, the
//   feature just carries on with no pop-up.
// Background lookups (covers, details and lyrics found automatically) never show it; they just
// try again later. The automatic update check at start-up is skipped when offline (0.1.51).
import 'package:flutter/material.dart';

import '../../services/internet_check.dart';
import '../theme.dart';

/// The features that need the internet, as listed in the warning.
const onlineFeatures = [
  'Finding covers, song details and book details online',
  'Finding lyrics online',
  'Searching online for video pictures and posters',
  'Checking for updates, and What\'s new',
];

/// Shows the warning. [atStart] gives the start-up version (Carry on); otherwise OK and Try
/// anyway. Returns true only when Try anyway is pressed.
Future<bool> showOfflineWarning(BuildContext context, {bool atStart = false}) async {
  final r = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      key: const ValueKey('offline-warning'),
      icon: const Icon(Icons.wifi_off),
      title: const Text('No internet connection'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('HomeTunes can\'t reach the internet right now. Your music, audiobooks and videos '
              'still play, including from your own server at home, but these won\'t work until '
              'you\'re back online:'),
          const SizedBox(height: 10),
          for (final f in onlineFeatures)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(child: Text(f)),
              ]),
            ),
          if (!atStart) ...[
            const SizedBox(height: 8),
            Text('Check your Wi-Fi or network cable, then try again.', style: TextStyle(color: AppColors.textDim)),
          ],
        ]),
      ),
      actions: atStart
          ? [FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Carry on'))]
          : [
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Try anyway')),
              FilledButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
            ],
    ),
  );
  return r ?? false;
}

/// The start-up check (main.dart): shows the warning, with Carry on, if the internet can't be
/// reached. Waits until it's closed.
Future<void> checkInternetAtStart(GlobalKey<NavigatorState> navigator) async {
  if (await InternetCheck.reachable()) return;
  final context = navigator.currentContext;
  if (context == null || !context.mounted) return;
  await showOfflineWarning(context, atStart: true);
}

/// Call before an online feature: true if it should go ahead (online, or Try anyway).
Future<bool> ensureOnline(BuildContext context) async {
  if (await InternetCheck.reachable()) return true;
  if (!context.mounted) return false;
  return showOfflineWarning(context);
}
