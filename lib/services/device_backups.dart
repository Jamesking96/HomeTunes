// Backups kept on the device itself (14 Nov 2026), for TVs: Android TV has no "save a file" or
// "open a file" screen (the request goes to a stub that does nothing), so Export backup… saved
// nothing there and Import backup… couldn't pick one. On a TV, backups go to HomeTunes' own folder
// in the TV's shared storage (Android/data/<app>/files/backups), which needs no permission and can
// be copied to and from a computer over adb. Uninstalling HomeTunes removes that folder too.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_backup.dart';

/// The folder backups are kept in on this device, made if needed; null where there isn't one
/// (not Android, or no shared storage).
Future<Directory?> deviceBackupFolder() async {
  if (!Platform.isAndroid) return null;
  try {
    final base = await getExternalStorageDirectory();
    if (base == null) return null;
    return Directory(p.join(base.path, 'backups'))..createSync(recursive: true);
  } catch (_) {
    return null;
  }
}

/// Saves [bytes] as [name] in [folder]. Returns the file.
Future<File> saveDeviceBackup(Directory folder, String name, List<int> bytes) async {
  final file = File(p.join(folder.path, name));
  final tmp = File('${file.path}.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  return tmp.rename(file.path);
}

/// The backups in [folder], newest first.
List<File> deviceBackups(Directory folder) {
  try {
    final list = [
      for (final f in folder.listSync())
        if (f is File && f.path.toLowerCase().endsWith('.${AppBackup.fileExtension}')) f,
    ];
    list.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return list;
  } catch (_) {
    return const [];
  }
}
