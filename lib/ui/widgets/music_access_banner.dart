// The amber "HomeTunes can't read your music" card (Android only in practice).
//
// Shown at the top of Home, Books and Settings when LibraryModel says folders are set up but the
// "Music and audio" permission is missing. Without that permission a scan would find nothing
// and wipe the library, so the app never scans until access is back. The button asks again,
// or sends the user to the phone's Settings if Android won't ask any more.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/music_permission.dart';
import '../../state/library_model.dart';
import '../theme.dart';

/// Shown when folders are set up but Android won't let HomeTunes read them.
class MusicAccessBanner extends StatelessWidget {
  const MusicAccessBanner({super.key});

  /// Asks for access; if given, re-checks it and rescans. Other screens can call this too.
  static Future<void> fix(BuildContext context) async {
    final lib = context.read<LibraryModel>();
    var access = await MusicPermission.request();
    if (access != MusicAccess.allowed) {
      // Android won't ask again: the switch is in the phone's Settings.
      await MusicPermission.openSettings();
      return; // checked again when the app comes back
    }
    await lib.refreshMusicAccess();
    access = lib.musicAccess;
    if (access == MusicAccess.allowed) await lib.scanLocal();
  }

  @override
  Widget build(BuildContext context) {
    // select: only rebuild when this one yes/no changes, not on every library change.
    final needed = context.select<LibraryModel, bool>((l) => l.needsMusicAccess);
    if (!needed) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: const Color(0xFF3A2A12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(children: [
          const Icon(Icons.lock_outline, color: Color(0xFFF2C45A)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('HomeTunes can\'t read your music', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 2),
              Text(
                'Android needs you to allow "Music and audio" access. If it sends you to Settings, choose '
                'Permissions › Music and audio › Allow.',
                style: TextStyle(color: AppColors.textDim, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: () => fix(context), child: const Text('Allow access')),
        ]),
      ),
    );
  }
}
